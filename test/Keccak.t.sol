// SPDX-License-Identifier: Apache 2

// forge test --match-contract TestKeccak

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { keccak256Word, keccak256SliceUnchecked, keccak256SliceCdUnchecked } from "../src/Utils.sol";

contract TestKeccak is Test {
  using { keccak256Word } for bytes32;
  using { keccak256SliceUnchecked, keccak256SliceCdUnchecked } for bytes;

  function test_bytesShouldHashTheSame(bytes calldata data) public {
    bytes32 hash = data.keccak256SliceUnchecked(0, data.length);
    bytes32 hashCd = data.keccak256SliceCdUnchecked(0, data.length);
    bytes32 expectedHash = keccak256(abi.encodePacked(data));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_bytesSubArrayEndShouldHashTheSame(bytes calldata data, uint seed) public {
    vm.assume(data.length > 0);
    uint length = seed % data.length;
    bytes32 hash = data.keccak256SliceUnchecked(0, length);
    bytes32 hashCd = data.keccak256SliceCdUnchecked(0, length);
    bytes32 expectedHash = keccak256(abi.encodePacked(data[0:length]));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_bytesSubArrayStartShouldHashTheSame(bytes calldata data, uint seed) public {
    vm.assume(data.length > 0);
    uint start = seed % data.length;
    bytes32 hash = data.keccak256SliceUnchecked(start, data.length - start);
    bytes32 hashCd = data.keccak256SliceCdUnchecked(start, data.length - start);
    bytes32 expectedHash = keccak256(abi.encodePacked(data[start:data.length]));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_bytesSubArrayStartEndShouldHashTheSame(bytes calldata data, uint seed) public {
    vm.assume(data.length > 0);
    uint end = bound(seed, 1, data.length);
    uint start = uint(keccak256(abi.encodePacked(seed))) % end;
    bytes32 hash = data.keccak256SliceUnchecked(start, end - start);
    bytes32 hashCd = data.keccak256SliceCdUnchecked(start, end - start);
    bytes32 expectedHash = keccak256(abi.encodePacked(data[start:end]));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_wordShouldHashTheSame(bytes32 data) public {
    bytes32 hash = data.keccak256Word();
    assertEq(hash, keccak256(abi.encodePacked(data)));
  }
}