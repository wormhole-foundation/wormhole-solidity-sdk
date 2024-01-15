
pragma solidity ^0.8.13;

import "../../../src/interfaces/IWormholeRelayer.sol";
import "../../../src/libraries/BytesParsing.sol";
import {CCTPMessageLib} from "../../CCTPBase.sol";

uint8 constant VERSION_VAAKEY = 1;
uint8 constant VERSION_DELIVERY_OVERRIDE = 1;
uint8 constant PAYLOAD_ID_DELIVERY_INSTRUCTION = 1;
uint8 constant PAYLOAD_ID_REDELIVERY_INSTRUCTION = 2;

using BytesParsing for bytes;

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

function decodeDeliveryInstruction(
    bytes memory encoded
) pure returns (DeliveryInstruction memory strct) {
    uint256 offset = checkUint8(encoded, 0, PAYLOAD_ID_DELIVERY_INSTRUCTION);

    uint256 requestedReceiverValue;
    uint256 extraReceiverValue;

    (strct.targetChain, offset) = encoded.asUint16Unchecked(offset);
    (strct.targetAddress, offset) = encoded.asBytes32Unchecked(offset);
    (strct.payload, offset) = decodeBytes(encoded, offset);
    (requestedReceiverValue, offset) = encoded.asUint256Unchecked(offset);
    (extraReceiverValue, offset) = encoded.asUint256Unchecked(offset);
    (strct.encodedExecutionInfo, offset) = decodeBytes(encoded, offset);
    (strct.refundChain, offset) = encoded.asUint16Unchecked(offset);
    (strct.refundAddress, offset) = encoded.asBytes32Unchecked(offset);
    (strct.refundDeliveryProvider, offset) = encoded.asBytes32Unchecked(offset);
    (strct.sourceDeliveryProvider, offset) = encoded.asBytes32Unchecked(offset);
    (strct.senderAddress, offset) = encoded.asBytes32Unchecked(offset);
    (strct.messageKeys, offset) = decodeMessageKeyArray(encoded, offset);

    strct.requestedReceiverValue = requestedReceiverValue;
    strct.extraReceiverValue = extraReceiverValue;

    checkLength(encoded, offset);
}

function decodeRedeliveryInstruction(
    bytes memory encoded
) pure returns (RedeliveryInstruction memory strct) {
    uint256 offset = checkUint8(encoded, 0, PAYLOAD_ID_REDELIVERY_INSTRUCTION);

    uint256 newRequestedReceiverValue;
    offset = checkUint8(encoded, offset, VAA_KEY_TYPE);
    (strct.deliveryVaaKey, offset) = decodeVaaKey(encoded, offset);
    (strct.targetChain, offset) = encoded.asUint16Unchecked(offset);
    (newRequestedReceiverValue, offset) = encoded.asUint256Unchecked(offset);
    (strct.newEncodedExecutionInfo, offset) = decodeBytes(encoded, offset);
    (strct.newSourceDeliveryProvider, offset) = encoded.asBytes32Unchecked(
        offset
    );
    (strct.newSenderAddress, offset) = encoded.asBytes32Unchecked(offset);

    strct.newRequestedReceiverValue = newRequestedReceiverValue;

    checkLength(encoded, offset);
}

function vaaKeyArrayToMessageKeyArray(
    VaaKey[] memory vaaKeys
) pure returns (MessageKey[] memory msgKeys) {
    msgKeys = new MessageKey[](vaaKeys.length);
    uint256 len = vaaKeys.length;
    for (uint256 i = 0; i < len; ) {
        msgKeys[i] = MessageKey(VAA_KEY_TYPE, encodeVaaKey(vaaKeys[i]));
        unchecked {
            ++i;
        }
    }
}

function encodeMessageKey(
    MessageKey memory msgKey
) pure returns (bytes memory encoded) {
    if (msgKey.keyType == VAA_KEY_TYPE) {
        // known length
        encoded = abi.encodePacked(msgKey.keyType, msgKey.encodedKey);
    } else {
        encoded = abi.encodePacked(
            msgKey.keyType,
            encodeBytes(msgKey.encodedKey)
        );
    }
}

uint256 constant VAA_KEY_TYPE_LENGTH = 2 + 32 + 8;

function decodeMessageKey(
    bytes memory encoded,
    uint256 startOffset
) pure returns (MessageKey memory msgKey, uint256 offset) {
    (msgKey.keyType, offset) = encoded.asUint8Unchecked(startOffset);
    if (msgKey.keyType == VAA_KEY_TYPE) {
        (msgKey.encodedKey, offset) = encoded.sliceUnchecked(
            offset,
            VAA_KEY_TYPE_LENGTH
        );
    } else {
        (msgKey.encodedKey, offset) = decodeBytes(encoded, offset);
    }
}

function encodeVaaKey(
    VaaKey memory vaaKey
) pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(
        vaaKey.chainId,
        vaaKey.emitterAddress,
        vaaKey.sequence
    );
}

function decodeVaaKey(
    bytes memory encoded,
    uint256 startOffset
) pure returns (VaaKey memory vaaKey, uint256 offset) {
    offset = startOffset;
    (vaaKey.chainId, offset) = encoded.asUint16Unchecked(offset);
    (vaaKey.emitterAddress, offset) = encoded.asBytes32Unchecked(offset);
    (vaaKey.sequence, offset) = encoded.asUint64Unchecked(offset);
}

function encodeMessageKeyArray(
    MessageKey[] memory msgKeys
) pure returns (bytes memory encoded) {
    uint256 len = msgKeys.length;
    if (len > type(uint8).max) {
        revert TooManyMessageKeys(len);
    }
    encoded = abi.encodePacked(uint8(msgKeys.length));
    for (uint256 i = 0; i < len; ) {
        encoded = abi.encodePacked(encoded, encodeMessageKey(msgKeys[i]));
        unchecked {
            ++i;
        }
    }
}

function decodeMessageKeyArray(
    bytes memory encoded,
    uint256 startOffset
) pure returns (MessageKey[] memory msgKeys, uint256 offset) {
    uint8 msgKeysLength;
    (msgKeysLength, offset) = encoded.asUint8Unchecked(startOffset);
    msgKeys = new MessageKey[](msgKeysLength);
    for (uint256 i = 0; i < msgKeysLength; ) {
        (msgKeys[i], offset) = decodeMessageKey(encoded, offset);
        unchecked {
            ++i;
        }
    }
}

function decodeCCTPKey(
    bytes memory encoded,
    uint256 startOffset
) pure returns (CCTPMessageLib.CCTPKey memory cctpKey, uint256 offset) {
    offset = startOffset;
    (cctpKey.domain, offset) = encoded.asUint32Unchecked(offset);
    (cctpKey.nonce, offset) = encoded.asUint64Unchecked(offset);
}

// ------------------------------------------  --------------------------------------------

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
    (payloadLength, offset) = encoded.asUint32Unchecked(startOffset);
    (payload, offset) = encoded.sliceUnchecked(offset, payloadLength);
}

function checkUint8(
    bytes memory encoded,
    uint256 startOffset,
    uint8 expectedPayloadId
) pure returns (uint256 offset) {
    uint8 parsedPayloadId;
    (parsedPayloadId, offset) = encoded.asUint8Unchecked(startOffset);
    if (parsedPayloadId != expectedPayloadId) {
        revert InvalidPayloadId(parsedPayloadId, expectedPayloadId);
    }
}

function checkLength(bytes memory encoded, uint256 expected) pure {
    if (encoded.length != expected) {
        revert InvalidPayloadLength(encoded.length, expected);
    }
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

    uint256 receiverValue;

    (receiverValue, offset) = encoded.asUint256Unchecked(offset);
    (strct.newExecutionInfo, offset) = decodeBytes(encoded, offset);
    (strct.redeliveryHash, offset) = encoded.asBytes32Unchecked(offset);

    strct.newReceiverValue = receiverValue;

    checkLength(encoded, offset);
}
