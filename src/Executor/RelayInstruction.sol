// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

//RelayInstructions are concatenated as tightly packed bytes.
//If the same type of instruction exists multiple times, its values are summed.
//see https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/definitions/src/protocols/executor/relayInstruction.ts
//and also: https://github.com/wormholelabs-xyz/example-executor-ci-test/blob/6bf0e7156bf81d54f3ded707e53815a2ff62555e/src/utils.ts#L37-L71

library RelayInstructionLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  uint8 private constant RECV_INST_TYPE_GAS      = 1;
  uint8 private constant RECV_INST_TYPE_DROP_OFF = 2;

  function encodeGas(uint128 gasLimit, uint128 msgVal) internal pure returns (bytes memory) {
    return abi.encodePacked(RECV_INST_TYPE_GAS, gasLimit, msgVal);
  }

  function encodeGasDropOffInstructions(
    uint128 dropOff,
    bytes32 recipient
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(RECV_INST_TYPE_DROP_OFF, dropOff, recipient);
  }

  // ---- only testing functionality below ----

  error InvalidInstructionType(uint8 instructionType);

  struct GasDropOff {
    uint256 dropOff;
    bytes32 recipient;
  }

  function decodeRelayInstructions(
    bytes memory encoded
  ) internal pure returns (
    uint totalGasLimit,
    uint totalMsgVal, //only from gas instructions, does not include gas drop offs
    GasDropOff[] memory gasDropOffs
  ) { unchecked {
    uint dropoffRequests = 0;
    uint offset = 0;
    while (offset < encoded.length) {
      uint8 instructionType;
      (instructionType, offset) = encoded.asUint8MemUnchecked(offset);
      if (instructionType == RECV_INST_TYPE_GAS) {
        uint gasLimit; uint msgVal;
        (gasLimit, offset) = encoded.asUint128MemUnchecked(offset);
        (msgVal,   offset) = encoded.asUint128MemUnchecked(offset);
        totalGasLimit += gasLimit;
        totalMsgVal   += msgVal;
      } else if (instructionType == RECV_INST_TYPE_DROP_OFF) {
        offset += 48; // 16 dropOff amount + 32 universal recipient
        ++dropoffRequests;
      }
      else
        revert InvalidInstructionType(instructionType);
    }
    encoded.length.checkLength(offset);

    if (dropoffRequests > 0) {
      gasDropOffs = new GasDropOff[](dropoffRequests);
      offset = 0;
      uint requestIndex = 0;
      uint uniqueRecipientCount = 0;
      while (true) {
        uint8 instructionType;
        (instructionType, offset) = encoded.asUint8MemUnchecked(offset);
        if (instructionType == RECV_INST_TYPE_GAS)
          offset += 32; // 16 gas limit + 16 msg val
        else {
          //must be RECV_INST_TYPE_DROP_OFF
          uint dropOff; bytes32 recipient;
          (dropOff,   offset) = encoded.asUint256MemUnchecked(offset);
          (recipient, offset) = encoded.asBytes32MemUnchecked(offset);
          uint i = 0;
          for (; i < uniqueRecipientCount; ++i)
            if (gasDropOffs[i].recipient == recipient) {
              gasDropOffs[i].dropOff += dropOff;
              break;
            }
          if (i == uniqueRecipientCount) {
            gasDropOffs[i] = GasDropOff(dropOff, recipient);
            ++uniqueRecipientCount;
          }

          ++requestIndex;
          if (requestIndex == dropoffRequests)
            break;
        }
      }
      assembly ("memory-safe") {
        mstore(gasDropOffs, uniqueRecipientCount)
      }
    }
  }}
}
