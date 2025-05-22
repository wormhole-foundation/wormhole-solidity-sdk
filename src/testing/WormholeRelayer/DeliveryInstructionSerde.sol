
pragma solidity ^0.8.19;

import "../../interfaces/IWormholeRelayer.sol";
import "../../libraries/BytesParsing.sol";
import {CCTPMessageLib} from "../../WormholeRelayer/CCTPBase.sol";

uint8 constant VERSION_VAAKEY = 1;
uint8 constant VERSION_DELIVERY_OVERRIDE = 1;
uint8 constant PAYLOAD_ID_DELIVERY_INSTRUCTION = 1;
uint8 constant PAYLOAD_ID_REDELIVERY_INSTRUCTION = 2;

using BytesParsing for bytes;
using {BytesParsing.checkLength} for uint;

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
  bytes32 newSourceDeliveryProvider;
  bytes32 newSenderAddress;
}

struct DeliveryOverride {
  uint256 newReceiverValue;
  bytes newExecutionInfo;
  bytes32 redeliveryHash;
}

function encode(DeliveryInstruction memory strct)
  pure
  returns (bytes memory encoded)
{
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
    encodeMessageKeyArray(strct.messageKeys)
  );
}

function decodeDeliveryInstruction(
  bytes memory encoded
) pure returns (DeliveryInstruction memory strct) {
  uint256 offset = checkUint8(encoded, 0, PAYLOAD_ID_DELIVERY_INSTRUCTION);

  (strct.targetChain,            offset) = encoded.asUint16MemUnchecked(offset);
  (strct.targetAddress,          offset) = encoded.asBytes32MemUnchecked(offset);
  (strct.payload,                offset) = decodeBytes(encoded, offset);
  (strct.requestedReceiverValue, offset) = encoded.asUint256MemUnchecked(offset);
  (strct.extraReceiverValue,     offset) = encoded.asUint256MemUnchecked(offset);
  (strct.encodedExecutionInfo,   offset) = decodeBytes(encoded, offset);
  (strct.refundChain,            offset) = encoded.asUint16MemUnchecked(offset);
  (strct.refundAddress,          offset) = encoded.asBytes32MemUnchecked(offset);
  (strct.refundDeliveryProvider, offset) = encoded.asBytes32MemUnchecked(offset);
  (strct.sourceDeliveryProvider, offset) = encoded.asBytes32MemUnchecked(offset);
  (strct.senderAddress,          offset) = encoded.asBytes32MemUnchecked(offset);
  (strct.messageKeys,            offset) = decodeMessageKeyArray(encoded, offset);

  encoded.length.checkLength(offset);
}

function encode(RedeliveryInstruction memory strct)
  pure
  returns (bytes memory encoded)
{
  bytes memory vaaKey = abi.encodePacked(VAA_KEY_TYPE, encodeVaaKey(strct.deliveryVaaKey));
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

function decodeRedeliveryInstruction(
  bytes memory encoded
) pure returns (RedeliveryInstruction memory strct) {
  uint256 offset = checkUint8(encoded, 0, PAYLOAD_ID_REDELIVERY_INSTRUCTION);
  offset = checkUint8(encoded, offset, VAA_KEY_TYPE);

  (strct.deliveryVaaKey,            offset) = decodeVaaKey(encoded, offset);
  (strct.targetChain,               offset) = encoded.asUint16MemUnchecked(offset);
  (strct.newRequestedReceiverValue, offset) = encoded.asUint256MemUnchecked(offset);
  (strct.newEncodedExecutionInfo,   offset) = decodeBytes(encoded, offset);
  (strct.newSourceDeliveryProvider, offset) = encoded.asBytes32MemUnchecked(offset);
  (strct.newSenderAddress,          offset) = encoded.asBytes32MemUnchecked(offset);

  encoded.length.checkLength(offset);
}

function vaaKeyArrayToMessageKeyArray(
  VaaKey[] memory vaaKeys
) pure returns (MessageKey[] memory msgKeys) {
  msgKeys = new MessageKey[](vaaKeys.length);
  uint256 len = vaaKeys.length;
  for (uint256 i = 0; i < len; ) {
    msgKeys[i] = MessageKey(VAA_KEY_TYPE, encodeVaaKey(vaaKeys[i]));
    unchecked { ++i; }
  }
}

function encodeMessageKey(
  MessageKey memory msgKey
) pure returns (bytes memory encoded) {
  encoded = (msgKey.keyType == VAA_KEY_TYPE)
    ? abi.encodePacked(msgKey.keyType, msgKey.encodedKey) // known length
    : abi.encodePacked(msgKey.keyType, encodeBytes(msgKey.encodedKey));
}

uint256 constant VAA_KEY_TYPE_LENGTH = 2 + 32 + 8;

function decodeMessageKey(
  bytes memory encoded,
  uint256 startOffset
) pure returns (MessageKey memory msgKey, uint256 offset) {
  (msgKey.keyType, offset) = encoded.asUint8MemUnchecked(startOffset);
  (msgKey.encodedKey, offset) = msgKey.keyType == VAA_KEY_TYPE
    ? encoded.sliceMemUnchecked(offset, VAA_KEY_TYPE_LENGTH)
    : decodeBytes(encoded, offset);
}

function encodeVaaKey(
  VaaKey memory vaaKey
) pure returns (bytes memory encoded) {
  encoded = abi.encodePacked(vaaKey.chainId, vaaKey.emitterAddress, vaaKey.sequence);
}

function decodeVaaKey(
  bytes memory encoded,
  uint256 startOffset
) pure returns (VaaKey memory vaaKey, uint256 offset) {
  offset = startOffset;
  (vaaKey.chainId,        offset) = encoded.asUint16MemUnchecked(offset);
  (vaaKey.emitterAddress, offset) = encoded.asBytes32MemUnchecked(offset);
  (vaaKey.sequence,       offset) = encoded.asUint64MemUnchecked(offset);
}

function encodeMessageKeyArray(
  MessageKey[] memory msgKeys
) pure returns (bytes memory encoded) {
  uint256 len = msgKeys.length;
  if (len > type(uint8).max)
    revert TooManyMessageKeys(len);

  encoded = abi.encodePacked(uint8(msgKeys.length));
  for (uint256 i = 0; i < len; ) {
    encoded = abi.encodePacked(encoded, encodeMessageKey(msgKeys[i]));
    unchecked { ++i; }
  }
}

function decodeMessageKeyArray(
  bytes memory encoded,
  uint256 startOffset
) pure returns (MessageKey[] memory msgKeys, uint256 offset) {
  uint8 msgKeysLength;
  (msgKeysLength, offset) = encoded.asUint8MemUnchecked(startOffset);
  msgKeys = new MessageKey[](msgKeysLength);
  for (uint256 i = 0; i < msgKeysLength; ) {
    (msgKeys[i], offset) = decodeMessageKey(encoded, offset);
    unchecked { ++i; }
  }
}

function decodeCCTPKey(
  bytes memory encoded,
  uint256 startOffset
) pure returns (CCTPMessageLib.CCTPKey memory cctpKey, uint256 offset) {
  offset = startOffset;
  (cctpKey.domain, offset) = encoded.asUint32MemUnchecked(offset);
  (cctpKey.nonce,  offset) = encoded.asUint64MemUnchecked(offset);
}

// ------------------------------------------ private  --------------------------------------------

function encodeBytes(bytes memory payload) pure returns (bytes memory encoded) {
  //casting payload.length to uint32 is safe because you'll be hard-pressed to allocate 4 GB of
  //  EVM memory in a single transaction
  encoded = abi.encodePacked(uint32(payload.length), payload);
}

function decodeBytes(
  bytes memory encoded,
  uint256 startOffset
) pure returns (bytes memory payload, uint256 offset) {
  uint32 payloadLength;
  (payloadLength, offset) = encoded.asUint32MemUnchecked(startOffset);
  (payload,       offset) = encoded.sliceMemUnchecked(offset, payloadLength);
}

function checkUint8(
  bytes memory encoded,
  uint256 startOffset,
  uint8 expectedPayloadId
) pure returns (uint256 offset) {
  uint8 parsedPayloadId;
  (parsedPayloadId, offset) = encoded.asUint8MemUnchecked(startOffset);
  if (parsedPayloadId != expectedPayloadId)
    revert InvalidPayloadId(parsedPayloadId, expectedPayloadId);
}

function encode(
  DeliveryOverride memory strct
) pure returns (bytes memory encoded) {
  encoded = abi.encodePacked(
    VERSION_DELIVERY_OVERRIDE,
    strct.newReceiverValue,
    encodeBytes(strct.newExecutionInfo),
    strct.redeliveryHash
  );
}

function decodeDeliveryOverride(
  bytes memory encoded
) pure returns (DeliveryOverride memory strct) {
  uint256 offset = checkUint8(encoded, 0, VERSION_DELIVERY_OVERRIDE);

  (strct.newReceiverValue, offset) = encoded.asUint256MemUnchecked(offset);
  (strct.newExecutionInfo, offset) = decodeBytes(encoded, offset);
  (strct.redeliveryHash,   offset) = encoded.asBytes32MemUnchecked(offset);

  encoded.length.checkLength(offset);
}
