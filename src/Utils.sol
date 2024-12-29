// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

import { WORD_SIZE, SCRATCH_SPACE_PTR, FREE_MEMORY_PTR } from "./constants/Common.sol";

error NotAnEvmAddress(bytes32);

function toUniversalAddress(address addr) pure returns (bytes32 universalAddr) {
  universalAddr = bytes32(uint256(uint160(addr)));
}

function fromUniversalAddress(bytes32 universalAddr) pure returns (address addr) {
  if (bytes12(universalAddr) != 0)
    revert NotAnEvmAddress(universalAddr);

  /// @solidity memory-safe-assembly
  assembly {
    addr := universalAddr
  }
}

/**
 * Reverts with a given buffer data.
 * Meant to be used to easily bubble up errors from low level calls when they fail.
 */
function reRevert(bytes memory err) pure {
  /// @solidity memory-safe-assembly
  assembly {
    revert(add(err, 32), mload(err))
  }
}

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

function keccak256SliceCdUnchecked(
  bytes calldata encoded,
  uint offset,
  uint length
) pure returns (bytes32 hash) {
  /// @solidity memory-safe-assembly
  assembly {
    let freeMemory := mload(FREE_MEMORY_PTR)

    let sliceStart := add(encoded.offset, offset)
    calldatacopy(freeMemory, sliceStart, length)

    hash := keccak256(freeMemory, length)
  }
}
