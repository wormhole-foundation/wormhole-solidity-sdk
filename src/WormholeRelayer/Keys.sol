// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {MessageKey, VaaKey, CctpKey} from "wormhole-sdk/interfaces/IWormholeRelayer.sol";

library WormholeRelayerKeysLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  error TooManyMessageKeys(uint256 len);

  // 0-127 are reserved for standardized KeyTypes, 128-255 are for custom use
  uint8 internal constant KEY_TYPE_VAA = 1;
  uint8 internal constant KEY_TYPE_CCTP = 2;

  uint internal constant VAA_KEY_SIZE =
    2 /*emitterChainId*/ + 32 /*emitterAddress*/ + 8 /*sequence*/;

  // ---- Encoding ----

  function encode(VaaKey memory vaaKey) internal pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(vaaKey.emitterChainId, vaaKey.emitterAddress, vaaKey.sequence);
  }

  function encode(CctpKey memory cctpKey) internal pure returns (bytes memory encoded) {
    encoded = abi.encodePacked(cctpKey.domain, cctpKey.nonce);
  }

  // ---- only relevant for testing ----

  // -- VaaKey --

  function decodeVaaKeyStructCd(
    bytes calldata encoded
  ) internal pure returns (VaaKey memory vaaKey) {
    (vaaKey.emitterChainId, vaaKey.emitterAddress, vaaKey.sequence) = decodeVaaKeyCd(encoded);
  }

  function decodeVaaKeyCd(bytes calldata encoded) internal pure returns (
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence
  ) {
    uint offset = 0;
    (emitterChainId, offset) = encoded.asUint16MemUnchecked(offset);
    (emitterAddress, offset) = encoded.asBytes32MemUnchecked(offset);
    (sequence,       offset) = encoded.asUint64MemUnchecked(offset);
    encoded.length.checkLength(offset);
  }

  function decodeVaaKeyStructMem(
    bytes memory encoded
  ) internal pure returns (VaaKey memory vaaKey) {
    uint offset = 0;
    (vaaKey.emitterChainId, vaaKey.emitterAddress, vaaKey.sequence, offset) =
      decodeVaaKeyMemUnchecked(encoded, offset);
    encoded.length.checkLength(offset);
  }

  function decodeVaaKeyStructMem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (VaaKey memory vaaKey, uint newOffset) {
    (vaaKey.emitterChainId, vaaKey.emitterAddress, vaaKey.sequence, newOffset) =
      decodeVaaKeyMemUnchecked(encoded, offset);
  }

  function decodeVaaKeyMemUnchecked(bytes memory encoded) internal pure returns (
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence
  ) {
    uint offset = 0;
    (emitterChainId, emitterAddress, sequence, offset) = decodeVaaKeyMemUnchecked(encoded, offset);
    encoded.length.checkLength(offset);
  }

  function decodeVaaKeyMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint    newOffset
  ) {
    (emitterChainId, offset) = encoded.asUint16MemUnchecked(offset);
    (emitterAddress, offset) = encoded.asBytes32MemUnchecked(offset);
    (sequence,       offset) = encoded.asUint64MemUnchecked(offset);
    newOffset = offset;
  }

  // -- CctpKey --

  function decodeCctpKeyStructCd(
    bytes calldata encoded
  ) internal pure returns (CctpKey memory cctpKey) {
    (cctpKey.domain, cctpKey.nonce) = decodeCctpKeyCd(encoded);
  }

  function decodeCctpKeyCd(bytes calldata encoded) internal pure returns (
    uint32 domain,
    uint64 nonce
  ) {
    uint offset = 0;
    (domain, offset) = encoded.asUint32MemUnchecked(offset);
    (nonce,  offset) = encoded.asUint64MemUnchecked(offset);
    encoded.length.checkLength(offset);
  }

  function decodeCctpKeyStructMem(
    bytes memory encoded
  ) internal pure returns (CctpKey memory cctpKey) {
    uint offset = 0;
    (cctpKey.domain, cctpKey.nonce, offset) = decodeCctpKeyMemUnchecked(encoded, offset);
    encoded.length.checkLength(offset);
  }

  function decodeCctpKeyStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (CctpKey memory cctpKey, uint newOffset) {
    (cctpKey.domain, cctpKey.nonce, newOffset) = decodeCctpKeyMemUnchecked(encoded, offset);
  }

  function decodeCctpKeyMemUnchecked(bytes memory encoded) internal pure returns (
    uint32 domain,
    uint64 nonce
  ) {
    uint offset = 0;
    (domain, nonce, offset) = decodeCctpKeyMemUnchecked(encoded, offset);
    encoded.length.checkLength(offset);
  }

  function decodeCctpKeyMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint32 domain,
    uint64 nonce,
    uint   newOffset
  ) {
    (domain, offset) = encoded.asUint32MemUnchecked(offset);
    (nonce,  offset) = encoded.asUint64MemUnchecked(offset);
    newOffset = offset;
  }

  // -- MessageKey --

  function decodeMessageKeyMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (MessageKey memory msgKey, uint newOffset) {
    (msgKey.keyType, offset) = encoded.asUint8MemUnchecked(offset);
    (msgKey.encodedKey, offset) = msgKey.keyType == KEY_TYPE_VAA
      ? encoded.sliceMemUnchecked(offset, VAA_KEY_SIZE)
      : encoded.sliceUint32PrefixedMemUnchecked(offset);
    newOffset = offset;
  }

  function decodeMessageKeyArrayMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (MessageKey[] memory msgKeys, uint newOffset) {
    uint8 msgKeysLength;
    (msgKeysLength, offset) = encoded.asUint8MemUnchecked(offset);
    msgKeys = new MessageKey[](msgKeysLength);
    for (uint256 i = 0; i < msgKeysLength; ++i)
      (msgKeys[i], offset) = decodeMessageKeyMemUnchecked(encoded, offset);

    newOffset = offset;
  }

  function encode(MessageKey memory msgKey) internal pure returns (bytes memory encoded) {
    encoded = (msgKey.keyType == KEY_TYPE_VAA)
      ? abi.encodePacked(msgKey.keyType, msgKey.encodedKey) // known length
      : abi.encodePacked(msgKey.keyType, _addLengthPrefix(msgKey.encodedKey));
  }

  function encode(MessageKey[] memory msgKeys) internal pure returns (bytes memory encoded) {
    uint len = msgKeys.length;
    if (len > type(uint8).max)
      revert TooManyMessageKeys(len);

    encoded = abi.encodePacked(uint8(msgKeys.length));
    for (uint i = 0; i < len; ++i)
      encoded = abi.encodePacked(encoded, encode(msgKeys[i]));
  }

  // -- Private --

  function _addLengthPrefix(bytes memory payload) private pure returns (bytes memory encoded) {
    //casting payload.length to uint32 is safe because you'll be hard-pressed to allocate 4 GB of
    //  EVM memory in a single transaction
    encoded = abi.encodePacked(uint32(payload.length), payload);
  }
}
