// SPDX-License-Identifier: Apache 2

// forge test --match-contract TestKeccak

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { BytesParsing } from "../src/libraries/BytesParsing.sol";
import { keccak256Word } from "../src/Utils.sol";

contract TestKeccak is Test {
    using BytesParsing for bytes;

    function test_bytesShouldHashTheSame(bytes memory data) public {
        bytes32 hash = data.keccak256Subarray(0, data.length);
        assertEq(hash, keccak256(abi.encodePacked(data)));
    }

    function test_bytesSubArrayEndShouldHashTheSame(bytes calldata data, uint256 indexSeed) public {
        vm.assume(data.length > 0);
        uint256 length = indexSeed % data.length;
        bytes32 hash = data.keccak256Subarray(0, length);
        assertEq(hash, keccak256(abi.encodePacked(data[0:length])));
    }

    function test_bytesSubArrayStartShouldHashTheSame(bytes calldata data, uint256 indexSeed) public {
        vm.assume(data.length > 0);
        uint256 start = indexSeed % data.length;
        bytes32 hash = data.keccak256Subarray(start, data.length - start);
        assertEq(hash, keccak256(abi.encodePacked(data[start:data.length])));
    }

    function test_bytesSubArrayStartEndShouldHashTheSame(bytes calldata data, uint256 startSeed, uint256 endSeed) public {
        vm.assume(data.length > 0);
        uint256 end = endSeed % data.length;
        vm.assume(end > 0);
        uint256 start = startSeed % end;
        bytes32 hash = data.keccak256Subarray(start, end - start);
        assertEq(hash, keccak256(abi.encodePacked(data[start:end])));
    }

    function test_wordShouldHashTheSame(bytes32 data) public {
        bytes32 hash = keccak256Word(data);
        assertEq(hash, keccak256(abi.encodePacked(data)));
    }
}