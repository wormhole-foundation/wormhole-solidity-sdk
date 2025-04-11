// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "wormhole-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-sdk/libraries/BytesParsing.sol";
import {WormholeRelayerKeysLib} from "wormhole-sdk/WormholeRelayer/Keys.sol";

//unlike other parsing libraries, this one is only relevant for testing and hence does not
//  follow the usual optimization pattern of having different flavors for all functions

struct DeliveryInstruction {
  uint16 targetChain;
  bytes32 targetAddress;
  bytes payload;
  uint256 requestedReceiverValue;
  uint256 extraReceiverValue;
  bytes encodedExecutionInfo;
  uint16 refundChain;
  bytes32 refundAddress;
  bytes32 refundDeliveryProvider;
  bytes32 sourceDeliveryProvider;
  bytes32 senderAddress;
  MessageKey[] messageKeys;
}

struct RedeliveryInstruction {
  VaaKey deliveryVaaKey;
  uint16 targetChain;
  uint256 newRequestedReceiverValue;
  bytes newEncodedExecutionInfo;
  //these are only informational off-chain and required for the redelivery itself:
  bytes32 newSourceDeliveryProvider;
  bytes32 newSenderAddress;
}

struct DeliveryOverride {
  uint256 newReceiverValue;
  bytes newExecutionInfo;
  bytes32 redeliveryHash;
}

struct EvmExecutionParamsV1 {
  uint256 gasLimit;
}

struct EvmExecutionInfoV1 {
  uint256 gasLimit;
  uint256 targetChainRefundPerGasUnused;
}

library WormholeRelayerStructsLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  error UnexpectedId(uint8 id, uint8 expectedId);

  uint8 constant VERSION_DELIVERY_OVERRIDE = 1;
  uint8 constant PAYLOAD_ID_DELIVERY_INSTRUCTION = 1;
  uint8 constant PAYLOAD_ID_REDELIVERY_INSTRUCTION = 2;

  uint8 constant EXECUTION_PARAMS_VERSION_EVM_V1 = 0;
  uint8 constant EXECUTION_INFO_VERSION_EVM_V1 = 0;

  uint256 constant KEY_TYPE_VAA_LENGTH = 2 + 32 + 8;

  // ---- encoding ----

  function encode(DeliveryInstruction memory strct) internal pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(
      PAYLOAD_ID_DELIVERY_INSTRUCTION,
      strct.targetChain,
      strct.targetAddress,
      encodeBytes(strct.payload),
      strct.requestedReceiverValue,
      strct.extraReceiverValue
    );
    encoded = abi.encodePacked(
      encoded,
      encodeBytes(strct.encodedExecutionInfo),
      strct.refundChain,
      strct.refundAddress,
      strct.refundDeliveryProvider,
      strct.sourceDeliveryProvider,
      strct.senderAddress,
      encode(strct.messageKeys)
    );
  }

  function encode(RedeliveryInstruction memory strct) internal pure returns (bytes memory encoded) {
    bytes memory vaaKey = abi.encodePacked(
      WormholeRelayerKeysLib.KEY_TYPE_VAA,
      encode(strct.deliveryVaaKey)
    );

    encoded = abi.encodePacked(
      PAYLOAD_ID_REDELIVERY_INSTRUCTION,
      vaaKey,
      strct.targetChain,
      strct.newRequestedReceiverValue,
      encodeBytes(strct.newEncodedExecutionInfo),
      strct.newSourceDeliveryProvider,
      strct.newSenderAddress
    );
  }

  function encode(DeliveryOverride memory strct) internal pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(
      VERSION_DELIVERY_OVERRIDE,
      strct.newReceiverValue,
      encodeBytes(strct.newExecutionInfo),
      strct.redeliveryHash
    );
  }

  function encode(MessageKey memory msgKey) internal pure returns (bytes memory encoded) {
    encoded = (msgKey.keyType == WormholeRelayerKeysLib.KEY_TYPE_VAA)
      ? abi.encodePacked(msgKey.keyType, msgKey.encodedKey) // known length
      : abi.encodePacked(msgKey.keyType, encodeBytes(msgKey.encodedKey));
  }

  function encode(VaaKey memory vaaKey) internal pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(vaaKey.emitterChainId, vaaKey.emitterAddress, vaaKey.sequence);
  }

  function encode(CctpKey memory cctpKey) internal pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(cctpKey.domain, cctpKey.nonce);
  }

  function encode(MessageKey[] memory msgKeys) internal pure returns (bytes memory encoded) {
    uint256 len = msgKeys.length;
    if (len > type(uint8).max)
      revert WormholeRelayerKeysLib.TooManyMessageKeys(len);

    encoded = abi.encodePacked(uint8(msgKeys.length));
    for (uint256 i = 0; i < len; ) {
      encoded = abi.encodePacked(encoded, encode(msgKeys[i]));
      unchecked { ++i; }
    }
  }

  function encode(EvmExecutionParamsV1 memory params) internal pure returns (bytes memory) {
    return abi.encode(uint8(EXECUTION_PARAMS_VERSION_EVM_V1), params.gasLimit);
  }

  function encode(EvmExecutionInfoV1 memory info) internal pure returns (bytes memory) {
    return abi.encode(
      uint8(EXECUTION_INFO_VERSION_EVM_V1),
      info.gasLimit,
      info.targetChainRefundPerGasUnused
    );
  }

  // ---- decoding ----

  function decodeDeliveryTarget(
    bytes memory encoded
  ) internal pure returns (uint16 targetChain, bytes32 targetAddress) {
    uint offset = checkUint8(encoded, 0, PAYLOAD_ID_DELIVERY_INSTRUCTION);
    (targetChain, offset) = encoded.asUint16MemUnchecked(offset);
    (targetAddress,     ) = encoded.asBytes32Mem(offset);
  }

  function decodeDeliveryInstruction(
    bytes memory encoded
  ) internal pure returns (DeliveryInstruction memory ret) {
    uint offset = checkUint8(encoded, 0, PAYLOAD_ID_DELIVERY_INSTRUCTION);

    (ret.targetChain,            offset) = encoded.asUint16MemUnchecked(offset);
    (ret.targetAddress,          offset) = encoded.asBytes32MemUnchecked(offset);
    (ret.payload,                offset) = encoded.sliceUint32PrefixedMemUnchecked(offset);
    (ret.requestedReceiverValue, offset) = encoded.asUint256MemUnchecked(offset);
    (ret.extraReceiverValue,     offset) = encoded.asUint256MemUnchecked(offset);
    (ret.encodedExecutionInfo,   offset) = encoded.sliceUint32PrefixedMemUnchecked(offset);
    (ret.refundChain,            offset) = encoded.asUint16MemUnchecked(offset);
    (ret.refundAddress,          offset) = encoded.asBytes32MemUnchecked(offset);
    (ret.refundDeliveryProvider, offset) = encoded.asBytes32MemUnchecked(offset);
    (ret.sourceDeliveryProvider, offset) = encoded.asBytes32MemUnchecked(offset);
    (ret.senderAddress,          offset) = encoded.asBytes32MemUnchecked(offset);
    (ret.messageKeys,            offset) = decodeMessageKeyArray(encoded, offset);

    encoded.length.checkLength(offset);
  }

  function decodeRedeliveryInstruction(
    bytes memory encoded
  ) internal pure returns (RedeliveryInstruction memory ret) {
    uint offset = checkUint8(encoded, 0, PAYLOAD_ID_REDELIVERY_INSTRUCTION);
    offset = checkUint8(encoded, offset, WormholeRelayerKeysLib.KEY_TYPE_VAA);

    (ret.deliveryVaaKey,            offset) = decodeVaaKey(encoded, offset);
    (ret.targetChain,               offset) = encoded.asUint16MemUnchecked(offset);
    (ret.newRequestedReceiverValue, offset) = encoded.asUint256MemUnchecked(offset);
    (ret.newEncodedExecutionInfo,   offset) = encoded.sliceUint32PrefixedMemUnchecked(offset);
    (ret.newSourceDeliveryProvider, offset) = encoded.asBytes32MemUnchecked(offset);
    (ret.newSenderAddress,          offset) = encoded.asBytes32MemUnchecked(offset);

    encoded.length.checkLength(offset);
  }

  function decodeDeliveryOverride(
    bytes memory encoded
  ) internal pure returns (DeliveryOverride memory ret) {
    uint256 offset = checkUint8(encoded, 0, VERSION_DELIVERY_OVERRIDE);

    (ret.newReceiverValue, offset) = encoded.asUint256MemUnchecked(offset);
    (ret.newExecutionInfo, offset) = encoded.sliceUint32PrefixedMemUnchecked(offset);
    (ret.redeliveryHash,   offset) = encoded.asBytes32MemUnchecked(offset);

    encoded.length.checkLength(offset);
  }

  function vaaKeyArrayToMessageKeyArray(
    VaaKey[] memory vaaKeys
  ) internal pure returns (MessageKey[] memory msgKeys) {
    msgKeys = new MessageKey[](vaaKeys.length);
    uint len = vaaKeys.length;
    for (uint i = 0; i < len; ++i)
      msgKeys[i] = MessageKey(WormholeRelayerKeysLib.KEY_TYPE_VAA, encode(vaaKeys[i]));
  }

  function decodeMessageKey(
    bytes memory encoded,
    uint offset
  ) internal pure returns (MessageKey memory msgKey, uint newOffset) {
    (msgKey.keyType, offset) = encoded.asUint8MemUnchecked(offset);
    (msgKey.encodedKey, offset) = msgKey.keyType == WormholeRelayerKeysLib.KEY_TYPE_VAA
      ? encoded.sliceMemUnchecked(offset, KEY_TYPE_VAA_LENGTH)
      : encoded.sliceUint32PrefixedMemUnchecked(offset);
    newOffset = offset;
  }

  function decodeVaaKey(bytes memory encoded) internal pure returns (VaaKey memory vaaKey) {
    (vaaKey, ) = decodeVaaKey(encoded, 0);
  }

  function decodeVaaKey(
    bytes memory encoded,
    uint offset
  ) internal pure returns (VaaKey memory vaaKey, uint newOffset) {
    (vaaKey.emitterChainId, offset) = encoded.asUint16MemUnchecked(offset);
    (vaaKey.emitterAddress, offset) = encoded.asBytes32MemUnchecked(offset);
    (vaaKey.sequence,       offset) = encoded.asUint64MemUnchecked(offset);
    newOffset = offset;
  }

  function decodeMessageKeyArray(
    bytes memory encoded,
    uint offset
  ) internal pure returns (MessageKey[] memory msgKeys, uint newOffset) {
    uint8 msgKeysLength;
    (msgKeysLength, offset) = encoded.asUint8MemUnchecked(offset);
    msgKeys = new MessageKey[](msgKeysLength);
    for (uint i = 0; i < msgKeysLength; ++i)
      (msgKeys[i], offset) = decodeMessageKey(encoded, offset);

    newOffset = offset;
  }

  function decodeCctpKey(bytes memory encoded) internal pure returns (CctpKey memory cctpKey) {
    (cctpKey, ) = decodeCctpKey(encoded, 0);
  }

  function decodeCctpKey(
    bytes memory encoded,
    uint offset
  ) internal pure returns (CctpKey memory cctpKey, uint newOffset) {
    (cctpKey.domain, offset) = encoded.asUint32MemUnchecked(offset);
    (cctpKey.nonce,  offset) = encoded.asUint64MemUnchecked(offset);
    newOffset = offset;
  }

  function decodeEvmExecutionParamsV1(
    bytes memory data
  ) internal pure returns (EvmExecutionParamsV1 memory ret) {
    uint8 version;
    (version, ret.gasLimit) = abi.decode(data, (uint8, uint256));
    checkId(version, uint8(EXECUTION_PARAMS_VERSION_EVM_V1));
  }

  function decodeEvmExecutionInfoV1(
    bytes memory data
  ) internal pure returns (EvmExecutionInfoV1 memory ret) {
    uint8 version;
    (version, ret.gasLimit, ret.targetChainRefundPerGasUnused) =
      abi.decode(data, (uint8, uint256, uint256));
    checkId(version, uint8(EXECUTION_INFO_VERSION_EVM_V1));
  }

  // ---- private ----

  function encodeBytes(bytes memory payload) private pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(uint32(payload.length), payload);
  }

  function checkUint8(
    bytes memory encoded,
    uint offset,
    uint8 expectedId
  ) private pure returns (uint newOffset) {
    uint8 id;
    (id, newOffset) = encoded.asUint8MemUnchecked(offset);
    checkId(id, expectedId);
  }

  function checkId(uint8 id, uint8 expectedId) private pure {
    if (id != expectedId)
      revert UnexpectedId(id, expectedId);
  }
}
using WormholeRelayerStructsLib for DeliveryInstruction global;
using WormholeRelayerStructsLib for RedeliveryInstruction global;
using WormholeRelayerStructsLib for DeliveryOverride global;
using WormholeRelayerStructsLib for EvmExecutionParamsV1 global;
using WormholeRelayerStructsLib for EvmExecutionInfoV1 global;
