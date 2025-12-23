// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {UncheckedIndexing} from "../libraries/UncheckedIndexing.sol";

//RelayInstructions are concatenated as tightly packed bytes.
//If the same type of instruction exists multiple times, its values are summed.
//see https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/definitions/src/protocols/executor/relayInstruction.ts
//and also: https://github.com/wormholelabs-xyz/example-executor-ci-test/blob/6bf0e7156bf81d54f3ded707e53815a2ff62555e/src/utils.ts#L37-L71

library RelayInstructionLib {
  uint8 internal constant RECV_INST_TYPE_GAS      = 1;
  uint8 internal constant RECV_INST_TYPE_DROP_OFF = 2;

  function encodeGas(uint128 gasLimit, uint128 msgVal) internal pure returns (bytes memory) {
    return abi.encodePacked(RECV_INST_TYPE_GAS, gasLimit, msgVal);
  }

  function encodeGasDropOffInstruction(
    uint128 dropOff,
    bytes32 recipient
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(RECV_INST_TYPE_DROP_OFF, dropOff, recipient);
  }

  function encodeGasDropOffInstructions(
    uint128[] memory dropOffs,
    bytes32[] memory recipients
  ) internal pure returns (bytes memory instructions) { unchecked {
    uint instructionCount = dropOffs.length;
    assert(instructionCount == recipients.length);

    instructions = new bytes(instructionCount * GAS_DROP_OFF_INSTRUCTION_SIZE);
    encodeGasDropOffInstructionsUnchecked(dropOffs, recipients, instructions, 0);
  }}

  //more complex implementations for higher gas efficiency below:
  using UncheckedIndexing for uint128[];
  using UncheckedIndexing for bytes32[];

  uint256 internal constant GAS_INSTRUCTION_SIZE          = 33;
  uint256 internal constant GAS_DROP_OFF_INSTRUCTION_SIZE = 49;

  function calcBytesSize(
    uint gasInstructionCount,
    uint gasDropOffInstructionCount
  ) internal pure returns (uint) { unchecked {
    return gasInstructionCount        * GAS_INSTRUCTION_SIZE +
           gasDropOffInstructionCount * GAS_DROP_OFF_INSTRUCTION_SIZE;
  }}

  function encodeGasDropOffInstructionUnchecked(
    uint128 gasLimit,
    uint128 msgVal,
    bytes memory buffer,
    uint offset
  ) internal pure returns (uint newOffset) {
    assembly ("memory-safe") {
      let ptr := add(buffer, offset)
      let word := mload(ptr)
      //store type while keeping higher order bits intact
      word := or(shl(8, word), RECV_INST_TYPE_GAS)
      mstore(add(ptr, 1), word)

      //store gas limit and msg val
      word := or(shl(128, gasLimit), msgVal)
      newOffset := add(offset, GAS_INSTRUCTION_SIZE) //equal to add(ptr, 32)
      mstore(add(buffer, newOffset), word)
    }
  }

  function encodeGasDropOffInstructionUnchecked(
    uint128 dropOff,
    bytes32 recipient,
    bytes memory buffer,
    uint offset
  ) internal pure returns (uint newOffset) {
    assembly ("memory-safe") {
      //store type and amount while keeping higher order bits intact
      let ptr := add(buffer, offset)
      let word := mload(ptr)
      word := or(shl(8, word), RECV_INST_TYPE_DROP_OFF)
      word := or(shl(128, word), dropOff)
      mstore(add(ptr, 17), word)

      //store recipient
      newOffset := add(offset, GAS_DROP_OFF_INSTRUCTION_SIZE) //equal to add(ptr, 32)
      mstore(add(buffer, newOffset), recipient)
    }
  }

  function encodeGasDropOffInstructionsUnchecked(
    uint128[] memory dropOffs,
    bytes32[] memory recipients,
    bytes memory buffer,
    uint offset
  ) internal pure returns (uint newOffset) { unchecked {
    uint instructionCount = dropOffs.length;
    newOffset = offset;
    for (uint i = 0; i < instructionCount; ++i)
      newOffset = encodeGasDropOffInstructionUnchecked(
        dropOffs.readUnchecked(i),
        recipients.readUnchecked(i),
        buffer,
        newOffset
      );
  }}
}
