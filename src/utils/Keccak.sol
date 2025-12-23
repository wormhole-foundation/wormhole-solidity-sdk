// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {WORD_SIZE, SCRATCH_SPACE_PTR, FREE_MEMORY_PTR} from "wormhole-sdk/constants/Common.sol";

function keccak256Word(bytes32 word) pure returns (bytes32 hash) {
  /// @solidity memory-safe-assembly
  assembly {
    mstore(SCRATCH_SPACE_PTR, word)
    hash := keccak256(SCRATCH_SPACE_PTR, WORD_SIZE)
  }
}

//WARNING: The same considerations for `Unchecked` apply as in BytesParsing.sol, namely:
// * does not use safe math, hence adding offset to encoded can overflow
// * does not check that [offset, offset + length) is within the bounds of encoded
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
