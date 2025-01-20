// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.14; //for (bugfixed) support of `using ... global;` syntax for libraries

import {WORD_SIZE} from "wormhole-sdk/constants/Common.sol";

// ╭──────────────────────────────────────────────────────────────────────╮
// │ Library for [reading from/writing to] memory without bounds checking │
// ╰──────────────────────────────────────────────────────────────────────╯

library UncheckedIndexing {
  function readUnchecked(bytes memory arr, uint index) internal pure returns (uint256 ret) {
    /// @solidity memory-safe-assembly
    assembly { ret := mload(add(add(arr, WORD_SIZE), index)) }
  }

  function writeUnchecked(bytes memory arr, uint index, uint256 value) internal pure {
    /// @solidity memory-safe-assembly
    assembly { mstore(add(add(arr, WORD_SIZE), index), value) }
  }

  function readUnchecked(address[] memory arr, uint index) internal pure returns (address ret) {
    bytes memory arrBytes;
    /// @solidity memory-safe-assembly
    assembly { arrBytes := arr }
    uint256 raw = readUnchecked(arrBytes, _mulWordSize(index));
    /// @solidity memory-safe-assembly
    assembly { ret := raw }
  }

  //it is assumed that value is never dirty here (it's hard to create a dirty address)
  //  see https://docs.soliditylang.org/en/latest/internals/variable_cleanup.html
  function writeUnchecked(address[] memory arr, uint index, address value) internal pure {
    bytes memory arrBytes;
    /// @solidity memory-safe-assembly
    assembly { arrBytes := arr }
    writeUnchecked(arrBytes, _mulWordSize(index), uint256(uint160(value)));
  }

  function readUnchecked(uint256[] memory arr, uint index) internal pure returns (uint256 ret) {
    bytes memory arrBytes;
    /// @solidity memory-safe-assembly
    assembly { arrBytes := arr }
    return readUnchecked(arrBytes, _mulWordSize(index));
  }

  function writeUnchecked(uint256[] memory arr, uint index, uint256 value) internal pure {
    bytes memory arrBytes;
    /// @solidity memory-safe-assembly
    assembly { arrBytes := arr }
    writeUnchecked(arrBytes, _mulWordSize(index), value);
  }

  function _mulWordSize(uint index) private pure returns (uint) { unchecked {
    return index * WORD_SIZE;
  }}
}
