// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

import { WORD_SIZE, SCRATCH_SPACE_PTR, FREE_MEMORY_PTR } from "./constants/Common.sol";

import {tokenOrNativeTransfer} from "wormhole-sdk/utils/Transfer.sol";
import {reRevert} from "wormhole-sdk/utils/Revert.sol";
import {toUniversalAddress, fromUniversalAddress} from "wormhole-sdk/utils/UniversalAddress.sol";

//see Optimization.md for rationale on avoiding short-circuiting
function eagerAnd(bool lhs, bool rhs) pure returns (bool ret) {
  /// @solidity memory-safe-assembly
  assembly {
    ret := and(lhs, rhs)
  }
}

//see Optimization.md for rationale on avoiding short-circuiting
function eagerOr(bool lhs, bool rhs) pure returns (bool ret) {
  /// @solidity memory-safe-assembly
  assembly {
    ret := or(lhs, rhs)
  }
}

function keccak256Word(bytes32 word) pure returns (bytes32 hash) {
  /// @solidity memory-safe-assembly
  assembly {
    mstore(SCRATCH_SPACE_PTR, word)
    hash := keccak256(SCRATCH_SPACE_PTR, WORD_SIZE)
  }
}

function keccak256SliceUnchecked(
  bytes memory encoded,
  uint offset,
  uint length
) pure returns (bytes32 hash) {
  /// @solidity memory-safe-assembly
  assembly {
    // The length of the bytes type `length` field is that of a word in memory
    let ptr := add(add(encoded, offset), WORD_SIZE)
    hash := keccak256(ptr, length)
  }
}

function keccak256Cd(
  bytes calldata encoded
) pure returns (bytes32 hash) {
  /// @solidity memory-safe-assembly
  assembly {
    let freeMemory := mload(FREE_MEMORY_PTR)
    calldatacopy(freeMemory, encoded.offset, encoded.length)
    hash := keccak256(freeMemory, encoded.length)
  }
}
