//SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.5.10;

// largely based on
// https://github.com/ralexstokes/deposit-verifier/blob/master/deposit_verifier.sol

import {TypedMemView} from "@summa-tx/memview.sol/contracts/TypedMemView.sol";

library B12 {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    // Fp is a field element with the high-order part stored in `a`.
    struct Fp {
        uint256 a;
        uint256 b;
    }

    // Fp2 is an extension field element with the coefficient of the
    // quadratic non-residue stored in `b`, i.e. p = a + i * b
    struct Fp2 {
        Fp a;
        Fp b;
    }

    // G1Point represents a point on BLS12-377 over Fp with coordinates (X,Y);
    struct G1Point {
        Fp X;
        Fp Y;
    }

    // G2Point represents a point on BLS12-377 over Fp2 with coordinates (X,Y);
    struct G2Point {
        Fp2 X;
        Fp2 Y;
    }

    struct G1MultiExpArg {
        G1Point point;
        uint256 scalar;
    }

    struct G2MultiExpArg {
        G2Point point;
        uint256 scalar;
    }

    struct PairingArg {
        G1Point g1;
        G2Point g2;
    }

    function FpEq(Fp memory a, Fp memory b) internal pure returns (bool) {
        return (a.a == b.a && a.b == b.b);
    }

    function fpGt(Fp memory a, Fp memory b) internal pure returns (bool) {
        return (a.a > b.a || (a.a == b.a && a.b > b.b));
    }

    function Fp2Eq(Fp2 memory a, Fp2 memory b) internal pure returns (bool) {
        return FpEq(a.a, b.a) && FpEq(a.b, b.b);
    }

    function fpAdd(Fp memory a, Fp memory b) internal pure returns (Fp memory) {
        uint256 bb = a.b + b.b;
        uint256 aa = a.a + b.a + (bb >= a.b && bb >= b.b ? 0 : 1);
        return Fp(aa, bb);
    }

    function fpModExp(Fp memory base, uint exponent, Fp memory modulus) internal view returns (Fp memory) {
        uint256 base1 = base.a;
        uint256 base2 = base.b;
        uint256 modulus1 = modulus.a;
        uint256 modulus2 = modulus.b;
        bytes memory arg = new bytes(3+32+64+64);
        bytes memory ret = new bytes(64);
        uint256 result1;
        uint256 result2;
        assembly {
            // length of base, exponent, modulus
            mstore(add(arg, 0x20), 0x40)
            mstore(add(arg, 0x40), 0x20)
            mstore(add(arg, 0x60), 0x20)

            // assign base, exponent, modulus
            mstore(add(arg, 0x80), base1)
            mstore(add(arg, 0xa0), base2)
            mstore(add(arg, 0xc0), exponent)
            mstore(add(arg, 0xe0), modulus1)
            mstore(add(arg, 0x100), modulus2)

            // call the precompiled contract BigModExp (0x05)
            let success := staticcall(0x05, 0x0, add(arg, 0x20), 0x100, add(ret, 0x20), 0x40)
            switch success
                case 0 {
                revert(0x0, 0x0)
            } default {
                result1 := mload(add(0x20,ret))
                result2 := mload(add(0x40,ret))
            }
        }
        return Fp(result1, result2);
    }

    function fpMul(Fp memory a, Fp memory b) internal pure returns (Fp memory) {
        uint256 a1 = uint128(a.b);
        uint256 a2 = uint128(a.b >> 128);
        uint256 a3 = uint128(a.a);
        uint256 a4 = uint128(a.a >> 128);
        uint256 b1 = uint128(b.b);
        uint256 b2 = uint128(b.b >> 128);
        uint256 b3 = uint128(b.a);
        uint256 b4 = uint128(b.a >> 128);
        Fp memory r1 = Fp(0,a1*b1);
        Fp memory r2 = Fp((a1*b2 + a2*b1) >> 128, (a1*b2 + a2*b1) << 128);
        Fp memory r3 = Fp(a1*b3 + a2*b2 * a3*b1, 0);
        Fp memory r4 = Fp((a1*b4 + a2*b3 * a3*b2 + a4*b1) << 128, 0);
        return fpAdd(r1, fpAdd(r2, fpAdd(r3, r4)));
    }

    function fpNormal(Fp memory a) internal view returns (Fp memory) {
        Fp memory p = Fp(0x1ae3a4617c510eac63b05c06ca1493b, 0x1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000001);
        return fpModExp(a, 1, p);
        // does p have inverse mod 2^512 ?
        /*
        Fp memory inv_p = Fp(0x8b566adb72049f1114e3f8c7e500b031b7d9dc9d16afbe660affdd1a1beeec01, 0x966d2f05974d6aa9db689a3cb86f5fffbadde8336ffffffef5ee800000000001);
        fpMul(inv_p);
        */

    }

    function g1Eq(G1Point memory a, G1Point memory b)
        internal
        pure
        returns (bool)
    {
        return FpEq(a.X, b.X) && FpEq(a.Y, b.Y);
    }

    function g1Eq(G2Point memory a, G2Point memory b)
        internal
        pure
        returns (bool)
    {
        return (Fp2Eq(a.X, b.X) && Fp2Eq(a.Y, b.Y));
    }

    function parseFp(bytes memory input, uint256 offset)
        internal
        pure
        returns (Fp memory ret)
    {
        bytes29 ref = input.ref(0).postfix(input.length - offset, 0);

        ret.a = ref.indexUint(0, 32);
        ret.b = ref.indexUint(32, 32);
    }

    function parseFp2(bytes memory input, uint256 offset)
        internal
        pure
        returns (Fp2 memory ret)
    {
        bytes29 ref = input.ref(0).postfix(input.length - offset, 0);

        ret.a.a = ref.indexUint(0, 32);
        ret.a.b = ref.indexUint(32, 32);
        ret.b.a = ref.indexUint(64, 32);
        ret.b.b = ref.indexUint(96, 32);
    }

    function parseCompactFp(bytes memory input, uint256 offset)
        internal
        pure
        returns (Fp memory ret)
    {
        bytes29 ref = input.ref(0).postfix(input.length - offset, 0);

        ret.a = ref.indexUint(0, 16);
        ret.b = ref.indexUint(16, 32);
    }

    function parseCompactFp2(bytes memory input, uint256 offset)
        internal
        pure
        returns (Fp2 memory ret)
    {
        bytes29 ref = input.ref(0).postfix(input.length - offset, 0);

        ret.a.a = ref.indexUint(48, 16);
        ret.a.b = ref.indexUint(64, 32);
        ret.b.a = ref.indexUint(0, 16);
        ret.b.b = ref.indexUint(16, 32);
    }

    function parseG1(bytes memory input, uint256 offset)
        internal
        pure
        returns (G1Point memory ret)
    {
        // unchecked sub is safe due to view validity checks
        bytes29 ref = input.ref(0).postfix(input.length - offset, 0);

        ret.X.a = ref.indexUint(0, 32);
        ret.X.b = ref.indexUint(32, 32);
        ret.Y.a = ref.indexUint(64, 32);
        ret.Y.b = ref.indexUint(96, 32);
    }

    function parseG2(bytes memory input, uint256 offset)
        internal
        pure
        returns (G2Point memory ret)
    {
        // unchecked sub is safe due to view validity checks
        bytes29 ref = input.ref(0).postfix(input.length - offset, 0);

        ret.X.a.a = ref.indexUint(0, 32);
        ret.X.a.b = ref.indexUint(32, 32);
        ret.X.b.a = ref.indexUint(64, 32);
        ret.X.b.b = ref.indexUint(96, 32);
        ret.Y.a.a = ref.indexUint(128, 32);
        ret.Y.a.b = ref.indexUint(160, 32);
        ret.Y.b.a = ref.indexUint(192, 32);
        ret.Y.b.b = ref.indexUint(224, 32);
    }

    function serializeFp(Fp memory p) internal pure returns (bytes memory) {
        return abi.encodePacked(p.a, p.b);
    }

    function serializeFp2(Fp2 memory p) internal pure returns (bytes memory) {
        return abi.encodePacked(p.a.a, p.a.b, p.b.a, p.b.b);
    }

    function serializeG1(G1Point memory p)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(p.X.a, p.X.b, p.Y.a, p.Y.b);
    }

    function serializeG2(G2Point memory p)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                p.X.a.a,
                p.X.a.b,
                p.X.b.a,
                p.X.b.b,
                p.Y.a.a,
                p.Y.a.b,
                p.Y.b.a,
                p.Y.b.b
            );
    }

    function g1Add(
        G1Point memory a,
        G1Point memory b,
        uint8 precompile,
        uint256 gasEstimate
    ) internal view returns (G1Point memory c) {
        uint256[8] memory input;
        input[0] = a.X.a;
        input[1] = a.X.b;
        input[2] = a.Y.a;
        input[3] = a.Y.b;

        input[4] = b.X.a;
        input[5] = b.X.b;
        input[6] = b.Y.a;
        input[7] = b.Y.b;

        bool success;
        assembly {
            success := staticcall(gasEstimate, precompile, input, 256, input, 128)
            // deallocate the input, leaving dirty memory
            mstore(0x40, input)
        }

        require(success, "g1 add precompile failed");
        c.X.a = input[0];
        c.X.b = input[1];
        c.Y.a = input[2];
        c.Y.b = input[3];
    }

    // Overwrites A
    function g1Mul(
        G1Point memory a,
        uint256 scalar,
        uint8 precompile,
        uint256 gasEstimate
    ) internal view returns (G1Point memory c) {
        uint256[5] memory input;
        input[0] = a.X.a;
        input[1] = a.X.b;
        input[2] = a.Y.a;
        input[3] = a.Y.b;

        input[4] = scalar;

        bool success;
        assembly {
            success := staticcall(
                gasEstimate,
                precompile,
                input,
                160,
                input, // reuse the memory to avoid growing
                128
            )
            // deallocate the input, leaving dirty memory
            mstore(0x40, input)
        }
        require(success, "g1 mul precompile failed");
        c.X.a = input[0];
        c.X.b = input[1];
        c.Y.a = input[2];
        c.Y.b = input[3];
    }

    function g1MultiExp(
        G1MultiExpArg[] memory argVec,
        uint8 precompile,
        uint256 gasEstimate
    ) internal view returns (G1Point memory c) {
        uint256[] memory input = new uint256[](argVec.length * 5);
        // hate this
        for (uint256 i = 0; i < input.length; i += 5) {
            input[i + 0] = argVec[i].point.X.a;
            input[i + 1] = argVec[i].point.X.b;
            input[i + 2] = argVec[i].point.Y.a;
            input[i + 3] = argVec[i].point.Y.b;
            input[i + 4] = argVec[i].scalar;
        }

        bool success;
        assembly {
            success := staticcall(
                gasEstimate,
                precompile,
                add(input, 0x20),
                mul(mload(input), 0x20),
                add(input, 0x20),
                128
            )
            // deallocate the input, leaving dirty memory
            mstore(0x40, input)
        }
        require(success, "g1 multiExp precompile failed");
        c.X.a = input[0];
        c.X.b = input[1];
        c.Y.a = input[2];
        c.Y.b = input[3];
    }

    function g2Add(
        G2Point memory a,
        G2Point memory b,
        uint8 precompile,
        uint256 gasEstimate
    ) internal view returns (G2Point memory c) {
        uint256[16] memory input;
        input[0] = a.X.a.a;
        input[1] = a.X.a.b;
        input[2] = a.X.b.a;
        input[3] = a.X.b.b;

        input[4] = a.Y.a.a;
        input[5] = a.Y.a.b;
        input[6] = a.Y.b.a;
        input[7] = a.Y.b.b;

        input[8] = b.X.a.a;
        input[9] = b.X.a.b;
        input[10] = b.X.b.a;
        input[11] = b.X.b.b;

        input[12] = b.Y.a.a;
        input[13] = b.Y.a.b;
        input[14] = b.Y.b.a;
        input[15] = b.Y.b.b;

        bool success;
        assembly {
            success := staticcall(
                gasEstimate,
                precompile,
                input,
                512,
                input, // reuse the memory to avoid growing
                256
            )
            // deallocate the input, leaving dirty memory
            mstore(0x40, input)
        }
        require(success, "g2 add precompile failed");
        c.X.a.a = input[0];
        c.X.a.b = input[1];
        c.X.b.a = input[2];
        c.X.b.b = input[3];

        c.Y.a.a = input[4];
        c.Y.a.b = input[5];
        c.Y.b.a = input[6];
        c.Y.b.b = input[7];
    }

    // Overwrites A
    function g2Mul(
        G2Point memory a,
        uint256 scalar,
        uint8 precompile,
        uint256 gasEstimate
    ) internal view {
        uint256[9] memory input;

        input[0] = a.X.a.a;
        input[1] = a.X.a.b;
        input[2] = a.X.b.a;
        input[3] = a.X.b.b;

        input[4] = a.Y.a.a;
        input[5] = a.Y.a.b;
        input[6] = a.Y.b.a;
        input[7] = a.Y.b.b;

        input[8] = scalar;

        bool success;
        assembly {
            success := staticcall(
                gasEstimate,
                precompile,
                input,
                288,
                a, // reuse the memory to avoid growing
                256
            )
            // deallocate the input, leaving dirty memory
            mstore(0x40, input)
        }
        require(success, "g2 mul precompile failed");
    }

    function g2MultiExp(
        G2MultiExpArg[] memory argVec,
        uint8 precompile,
        uint256 gasEstimate
    ) internal view returns (G2Point memory c) {
        uint256[] memory input = new uint256[](argVec.length * 9);
        // hate this
        for (uint256 i = 0; i < input.length / 9; i += 1) {
            uint256 idx = i * 9;
            input[idx + 0] = argVec[i].point.X.a.a;
            input[idx + 1] = argVec[i].point.X.a.b;
            input[idx + 2] = argVec[i].point.X.b.a;
            input[idx + 3] = argVec[i].point.X.b.b;
            input[idx + 4] = argVec[i].point.Y.a.a;
            input[idx + 5] = argVec[i].point.Y.a.b;
            input[idx + 6] = argVec[i].point.Y.b.a;
            input[idx + 7] = argVec[i].point.Y.b.b;
            input[idx + 8] = argVec[i].scalar;
        }

        bool success;
        assembly {
            success := staticcall(
                gasEstimate,
                precompile,
                add(input, 0x20),
                mul(mload(input), 0x20), // 288 bytes per arg
                add(input, 0x20), // write directly to the already allocated result
                256
            )
            // deallocate the input, leaving dirty memory
            mstore(0x40, input)
        }
        require(success, "g2 multiExp precompile failed");
        c.X.a.a = input[0];
        c.X.a.b = input[1];
        c.X.b.a = input[2];
        c.X.b.b = input[3];
        c.Y.a.a = input[4];
        c.Y.a.b = input[5];
        c.Y.b.a = input[6];
        c.Y.b.b = input[7];
    }

    function pairing(
        PairingArg[] memory argVec,
        uint8 precompile,
        uint256 gasEstimate
    ) internal view returns (bool result) {
        uint256 len = argVec.length;

        bool success;
        assembly {
            success := staticcall(
                gasEstimate,
                precompile,
                add(argVec, 0x20), // the body of the array
                mul(384, len), // 384 bytes per arg
                mload(0x40), // write to earliest freemem
                32
            )
            result := mload(mload(0x40)) // load what we just wrote
        }
        require(success, "pairing precompile failed");
    }
}

library B12_381Lib {
    using B12 for B12.G1Point;
    using B12 for B12.G2Point;

    uint8 constant G1_ADD = 10;
    uint8 constant G1_MUL = 11;
    uint8 constant G1_MULTI_EXP = 12;
    uint8 constant G2_ADD = 13;
    uint8 constant G2_MUL = 14;
    uint8 constant G2_MULTI_EXP = 15;
    uint8 constant PAIRING = 16;
    uint8 constant MAP_TO_G1 = 17;
    uint8 constant MAP_TO_G2 = 18;

    function negativeP1() internal pure returns (B12.G1Point memory p) {
        p.X.a = 31827880280837800241567138048534752271;
        p
            .X
            .b = 88385725958748408079899006800036250932223001591707578097800747617502997169851;
        p.Y.a = 22997279242622214937712647648895181298;
        p
            .Y
            .b = 46816884707101390882112958134453447585552332943769894357249934112654335001290;
    }

    function mapToG1(B12.Fp memory a)
        internal
        view
        returns (B12.G1Point memory b)
    {
        uint256[2] memory input;
        input[0] = a.a;
        input[1] = a.b;

        bool success;
        uint8 ADDR = MAP_TO_G1;
        assembly {
            success := staticcall(
                20000,
                ADDR,
                input, // the body of the array
                64,
                b, // write directly to pre-allocated result
                128
            )
            // deallocate the input
            mstore(add(input, 0), 0)
            mstore(add(input, 0x20), 0)
            mstore(0x40, input)
        }
    }

    function mapToG2(B12.Fp2 memory a)
        internal
        view
        returns (B12.G2Point memory b)
    {
        uint256[4] memory input;
        input[0] = a.a.a;
        input[1] = a.a.b;
        input[2] = a.b.a;
        input[3] = a.b.b;

        bool success;
        uint8 ADDR = MAP_TO_G2;
        assembly {
            success := staticcall(
                120000,
                ADDR,
                input, // the body of the array
                128,
                b, // write directly to pre-allocated result
                256
            )
            // deallocate the input
            mstore(add(input, 0), 0)
            mstore(add(input, 0x20), 0)
            mstore(add(input, 0x40), 0)
            mstore(add(input, 0x60), 0)
            mstore(0x40, input)
        }
    }

    function g1Add(B12.G1Point memory a, B12.G1Point memory b)
        internal
        view
        returns (B12.G1Point memory c)
    {
        return a.g1Add(b, G1_ADD, 15000);
    }

    function g1Mul(B12.G1Point memory a, uint256 scalar)
        internal
        view
        returns (B12.G1Point memory c)
    {
        return a.g1Mul(scalar, G1_MUL, 50000);
    }

    function g1MultiExp(B12.G1MultiExpArg[] memory argVec)
        internal
        view
        returns (B12.G1Point memory c)
    {
        uint256 roughCost = (argVec.length * 12000 * 1200) / 1000;
        return B12.g1MultiExp(argVec, G1_MULTI_EXP, roughCost);
    }

    function g2Add(B12.G2Point memory a, B12.G2Point memory b)
        internal
        view
        returns (B12.G2Point memory c)
    {
        return a.g2Add(b, G2_ADD, 20000);
    }

    function g2Mul(B12.G2Point memory a, uint256 scalar) internal view {
        return a.g2Mul(scalar, G2_MUL, 60000);
    }

    function g2MultiExp(B12.G2MultiExpArg[] memory argVec)
        internal
        view
        returns (B12.G2Point memory c)
    {
        uint256 roughCost = (argVec.length * 55000 * 1200) / 1000;
        return B12.g2MultiExp(argVec, G2_MULTI_EXP, roughCost);
    }

    function pairing(B12.PairingArg[] memory argVec)
        internal
        view
        returns (bool result)
    {
        uint256 roughCost = (23000 * argVec.length) + 115000;
        return B12.pairing(argVec, PAIRING, roughCost);
    }
}

library B12_377Lib {
    using B12 for B12.G1Point;
    using B12 for B12.G2Point;


    uint8 constant G1_ADD = 19;
    uint8 constant G1_MUL = 20;
    uint8 constant G1_MULTI_EXP = 21;
    uint8 constant G2_ADD = 22;
    uint8 constant G2_MUL = 23;
    uint8 constant G2_MULTI_EXP = 24;
    uint8 constant PAIRING = 25;


    function g1Add(B12.G1Point memory a, B12.G1Point memory b)
        internal
        view
        returns (B12.G1Point memory c)
    {
        return a.g1Add(b, G1_ADD, 15000);
    }

    function g1Mul(B12.G1Point memory a, uint256 scalar)
        internal
        view
        returns (B12.G1Point memory c)
    {
        return a.g1Mul(scalar, G1_MUL, 50000);
    }

    function g1MultiExp(B12.G1MultiExpArg[] memory argVec)
        internal
        view
        returns (B12.G1Point memory c)
    {
        uint256 roughCost = (argVec.length * 12000 * 1200) / 1000;
        return B12.g1MultiExp(argVec, G1_MULTI_EXP, roughCost);
    }

    function g2Add(B12.G2Point memory a, B12.G2Point memory b)
        internal
        view
        returns (B12.G2Point memory c)
    {
        return a.g2Add(b, G2_ADD, 20000);
    }

    function g2Mul(B12.G2Point memory a, uint256 scalar) internal view {
        return a.g2Mul(scalar, G2_MUL, 60000);
    }

    function g2MultiExp(B12.G2MultiExpArg[] memory argVec)
        internal
        view
        returns (B12.G2Point memory c)
    {
        uint256 roughCost = (argVec.length * 55000 * 1200) / 1000;
        return B12.g2MultiExp(argVec, G2_MULTI_EXP, roughCost);
    }

    function pairing(B12.PairingArg[] memory argVec)
        internal
        view
        returns (bool result)
    {
        uint256 roughCost = (55000 * argVec.length) + 65000;
        return B12.pairing(argVec, PAIRING, roughCost);
    }
}


library CeloB12_377Lib {
    using B12 for B12.G1Point;
    using B12 for B12.G2Point;


    uint8 constant G1_ADD = 0xf2;
    uint8 constant G1_MUL = 0xf1;
    uint8 constant G1_MULTI_EXP = 0xf0;
    uint8 constant G2_ADD = 0xef;
    uint8 constant G2_MUL = 0xee;
    uint8 constant G2_MULTI_EXP = 0xed;
    uint8 constant PAIRING = 0xec;


    function g1Add(B12.G1Point memory a, B12.G1Point memory b)
        internal
        view
        returns (B12.G1Point memory c)
    {
        return a.g1Add(b, G1_ADD, 15000);
    }

    function g1Mul(B12.G1Point memory a, uint256 scalar)
        internal
        view
        returns (B12.G1Point memory c)
    {
        return a.g1Mul(scalar, G1_MUL, 50000);
    }

    function g1MultiExp(B12.G1MultiExpArg[] memory argVec)
        internal
        view
        returns (B12.G1Point memory c)
    {
        uint256 roughCost = (argVec.length * 12000 * 1200) / 1000;
        return B12.g1MultiExp(argVec, G1_MULTI_EXP, roughCost);
    }

    function g2Add(B12.G2Point memory a, B12.G2Point memory b)
        internal
        view
        returns (B12.G2Point memory c)
    {
        return a.g2Add(b, G2_ADD, 20000);
    }

    function g2Mul(B12.G2Point memory a, uint256 scalar) internal view {
        return a.g2Mul(scalar, G2_MUL, 60000);
    }

    function g2MultiExp(B12.G2MultiExpArg[] memory argVec)
        internal
        view
        returns (B12.G2Point memory c)
    {
        uint256 roughCost = (argVec.length * 55000 * 1200) / 1000;
        return B12.g2MultiExp(argVec, G2_MULTI_EXP, roughCost);
    }

    function pairing(B12.PairingArg[] memory argVec)
        internal
        view
        returns (bool result)
    {
        uint256 roughCost = (55000 * argVec.length) + 65000;
        return B12.pairing(argVec, PAIRING, roughCost);
    }
}