// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

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

  function encodeGasDropOffInstructions(
    uint128 dropOff,
    bytes32 recipient
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(RECV_INST_TYPE_DROP_OFF, dropOff, recipient);
  }
}
