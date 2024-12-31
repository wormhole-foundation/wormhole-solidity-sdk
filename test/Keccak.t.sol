// SPDX-License-Identifier: Apache 2

// forge test --match-contract TestKeccak

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { keccak256Word, keccak256SliceUnchecked, keccak256Cd } from "../src/Utils.sol";

contract TestKeccak is Test {
  using { keccak256Word } for bytes32;
  using { keccak256SliceUnchecked } for bytes;

  function test_bytesShouldHashTheSame(bytes calldata data) public {
    bytes32 hash = data.keccak256SliceUnchecked(0, data.length);
    bytes32 hashCd = keccak256Cd(data);
    bytes32 expectedHash = keccak256(abi.encodePacked(data));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_bytesSubArrayEndShouldHashTheSame(bytes calldata data, uint seed) public {
    vm.assume(data.length > 0);
    uint length = seed % data.length;
    bytes calldata slice = data[0 : length];

    bytes32 hash = data.keccak256SliceUnchecked(0, length);
    bytes32 hashCd = keccak256Cd(slice);

    bytes32 expectedHash = keccak256(abi.encodePacked(slice));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_bytesSubArrayStartShouldHashTheSame(bytes calldata data, uint seed) public {
    vm.assume(data.length > 0);
    uint start = seed % data.length;
    bytes calldata slice = data[start : data.length];

    bytes32 hash = data.keccak256SliceUnchecked(start, data.length - start);
    bytes32 hashCd = keccak256Cd(slice);

    bytes32 expectedHash = keccak256(abi.encodePacked(slice));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_bytesSubArrayStartEndShouldHashTheSame(bytes calldata data, uint seed) public {
    vm.assume(data.length > 0);
    uint end = bound(seed, 1, data.length);
    uint start = uint(keccak256(abi.encodePacked(seed))) % end;
    bytes calldata slice = data[start : end];

    bytes32 hash = data.keccak256SliceUnchecked(start, end - start);
    bytes32 hashCd = keccak256Cd(slice);

    bytes32 expectedHash = keccak256(abi.encodePacked(slice));
    assertEq(hash, expectedHash);
    assertEq(hashCd, expectedHash);
  }

  function test_wordShouldHashTheSame(bytes32 data) public {
    bytes32 hash = data.keccak256Word();
    assertEq(hash, keccak256(abi.encodePacked(data)));
  }
}