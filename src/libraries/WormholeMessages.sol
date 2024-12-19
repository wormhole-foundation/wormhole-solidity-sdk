// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";

//VAA encoding and decoding
//  see https://github.com/wormhole-foundation/wormhole/blob/c35940ae9689f6df9e983d51425763509b74a80f/ethereum/contracts/Messages.sol#L147
//only implements calldata variants, given that VAAs are likely always passed as calldata
library WormholeMessages {
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  // ------------ VAA / CoreBridge ------------

  error InvalidVersion(uint8 version);

  uint internal constant VAA_VERSION = 1;
  uint private constant _VAA_SIGNATURE_ARRAY_OFFSET = 1 /*version*/ + 4 /*guardianSet*/;
  uint private constant _VAA_SIGNATURE_SIZE = 1 /*guardianSetIndex*/ + 65 /*signaturesize*/;
  uint internal constant VAA_META_SIZE =
    4 /*timestamp*/ +
    4 /*nonce*/ +
    2 /*emitterChainId*/ +
    32 /*emitterAddress*/ +
    8 /*sequence*/ +
    1 /*consistencyLevel*/;

  //see https://github.com/wormhole-foundation/wormhole/blob/c35940ae9689f6df9e983d51425763509b74a80f/ethereum/contracts/Messages.sol#L174
  //origin: https://bitcoin.stackexchange.com/a/102382
  uint private constant _SIGNATURE_RECOVERY_MAGIC = 27;

  function decodeVaaHeaderCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (
    uint32 guardianSetIndex,
    IWormhole.Signature[] memory signatures,
    uint offset
  ) { unchecked {
    uint8 version;
    (version, offset) = encodedVaa.asUint8CdUnchecked(0);
    if (version != VAA_VERSION)
      revert InvalidVersion(version);

    (guardianSetIndex, offset) = encodedVaa.asUint32CdUnchecked(offset);

    uint signersLen;
    (signersLen, offset) = encodedVaa.asUint8CdUnchecked(offset);

    signatures = new IWormhole.Signature[](signersLen);
    for (uint i = 0; i < signersLen; ++i) {
      (signatures[i].guardianIndex, offset) = encodedVaa.asUint8CdUnchecked(offset);
      (signatures[i].r,             offset) = encodedVaa.asBytes32CdUnchecked(offset);
      (signatures[i].s,             offset) = encodedVaa.asBytes32CdUnchecked(offset);
      (signatures[i].v,             offset) = encodedVaa.asUint8CdUnchecked(offset);
      signatures[i].v += _SIGNATURE_RECOVERY_MAGIC;
    }
  }}

  //does not calculate/return the hash that's otherwise included in an IWormhole.VM
  function decodeVaaCd(
    bytes calldata encodedVaa
  ) internal pure returns (
    uint32 timestamp,
    uint32 nonce,
    uint16 emitterChainId,
    bytes32 emitterAddress,
    uint64 sequence,
    uint8 consistencyLevel,
    bytes memory payload
  ) { unchecked {
    return decodeVaaCd(encodedVaa, skipSignaturesCd(encodedVaa));
  }}

  function decodeVaaCd(
    bytes calldata encodedVaa,
    uint offset
  ) internal pure returns (
    uint32 timestamp,
    uint32 nonce,
    uint16 emitterChainId,
    bytes32 emitterAddress,
    uint64 sequence,
    uint8 consistencyLevel,
    bytes memory payload
  ) { unchecked {
    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, offset) =
      decodeMetaCd(encodedVaa, offset);
    payload = decodePayloadCd(encodedVaa, offset);
  }}

  function skipVaaSignaturesCd(bytes calldata encodedVaa) internal pure returns (uint) { unchecked {
    (uint sigCount, offset) = encodedVaa.asUint8CdUnchecked(_VAA_SIGNATURE_ARRAY_OFFSET);
    return offset + sigCount * _VAA_SIGNATURE_SIZE;
  }}

  function decodeVaaMetaCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (
    uint32 timestamp,
    uint32 nonce,
    uint16 emitterChainId,
    bytes32 emitterAddress,
    uint64 sequence,
    uint8 consistencyLevel,
    uint newOffset
  ) {
    return decodeMetaCd(encodedVaa, skipSignaturesCd(encodedVaa));
  }

  function decodeVaaMetaCdUnchecked(
    bytes calldata encodedVaa,
    uint offset
  ) internal pure returns (
    uint32 timestamp,
    uint32 nonce,
    uint16 emitterChainId,
    bytes32 emitterAddress,
    uint64 sequence,
    uint8 consistencyLevel,
    uint newOffset
  ) {
    (timestamp,        offset) = encodedVaa.asUint32CdUnchecked(offset);
    (nonce,            offset) = encodedVaa.asUint32CdUnchecked(offset);
    (emitterChainId,   offset) = encodedVaa.asUint16CdUnchecked(offset);
    (emitterAddress,   offset) = encodedVaa.asBytes32CdUnchecked(offset);
    (sequence,         offset) = encodedVaa.asUint64CdUnchecked(offset);
    (consistencyLevel, offset) = encodedVaa.asUint8CdUnchecked(offset);
    newOffset = offset;
  }

  function decodeVaaPayloadCd(
    bytes calldata encodedVaa
  ) internal pure returns (bytes memory payload) { unchecked {
    return decodePayloadCd(encodedVaa, skipSignaturesCd(encodedVaa) + VAA_META_SIZE);
  }}

  function decodeVaaPayloadCd(
    bytes calldata encodedVaa,
    uint offset
  ) internal pure returns (bytes memory payload) { unchecked {
    //check to avoid underflow in following subtraction
    BytesParsing.checkBound(offset, encodedVaa.length);
    (payload, ) = encodedVaa.sliceCdUnchecked(offset, encodedVaa.length - offset);
  }}

  //legacy decoder for IWormhole.VM
  function decodeVmCd(
    bytes calldata encodedVaa
  ) internal pure returns (IWormhole.VM memory vm) { unchecked {
    uint offset;
    (vm.guardianSetIndex, vm.signatures, offset) = decodeHeaderCdUnchecked(encodedVaa);
    vm.version = VAA_VERSION;

    BytesParsing.checkBound(offset, encodedVaa.length);
    (bytes memory body, ) = encodedVaa.sliceCdUnchecked(offset, encodedVaa.length - offset);
    vm.hash = keccak256(abi.encodePacked(keccak256(body)));

    ( vm.timestamp,
      vm.nonce,
      vm.emitterChainId,
      vm.emitterAddress,
      vm.sequence,
      vm.consistencyLevel,
      offset
    ) = decodeMetaCd(encodedVaa, offset);

    (vm.payload, ) = decodePayloadCd(encodedVaa, offset);
  }}

  //encode should only be relevant for testing
  function encode(IWormhole.VM memory vaa) internal pure returns (bytes memory) { unchecked {
    bytes memory sigs;
    for (uint i = 0; i < vaa.signatures.length; ++i) {
      IWormhole.Signature memory sig = vaa.signatures[i];
      uint8 v = sig.v - _SIGNATURE_RECOVERY_MAGIC;
      sigs = bytes.concat(sigs, abi.encodePacked(sig.guardianIndex, sig.r, sig.s, v));
    }

    return abi.encodePacked(
      vaa.version,
      vaa.guardianSetIndex,
      uint8(vaa.signatures.length),
      sigs,
      vaa.timestamp,
      vaa.nonce,
      vaa.emitterChainId,
      vaa.emitterAddress,
      vaa.sequence,
      vaa.consistencyLevel,
      vaa.payload
    );
  }}

  // ------------ TokenBridge ------------

  error InvalidPayloadId(uint8 encoded);

  uint8 internal constant PAYLOAD_ID_TRANSFER = 1;
  uint8 internal constant PAYLOAD_ID_ATTEST_META = 2;
  uint8 internal constant PAYLOAD_ID_TRANSFER_WITH_PAYLOAD = 3;

  function checkPayloadId(uint8 encoded, uint8 expected) internal pure {
    if (encoded != expected)
      revert InvalidPayloadId(encoded);
  }

  // Transfer payloads

  uint private constant _TRANSFER_COMMON_SIZE =
    32 /*tbNormalizedAmount*/ +
    32 /*tokenOriginAddress*/ +
    2  /*tokenOriginChain*/ +
    32 /*toAddress*/ +
    2  /*toChain*/;

  uint internal constant TRANSFER_WITH_PAYLOAD_META_SIZE =
    _TRANSFER_COMMON_SIZE +
    32 /*fromAddress*/;

  function encodeTransfer(
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      PAYLOAD_ID_TRANSFER,
      tbNormalizedAmount,
      tokenOriginAddress,
      tokenOriginChain,
      toAddress,
      toChain,
      uint256(0) //fees are not supported
    );
  }

  function encodeTransferWithPayload(
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain,
    bytes memory payload
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      PAYLOAD_ID_TRANSFER_WITH_PAYLOAD,
      tbNormalizedAmount,
      tokenOriginAddress,
      tokenOriginChain,
      toAddress,
      toChain,
      payload
    );
  }

  // calldata variants

  function decodeTransferCd(bytes calldata vaaPayload) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain
  ) {
    return decodeTransferCd(vaaPayload, 0);
  }

  function decodeTransferCd(bytes calldata vaaPayload, uint offset) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain
  ) {
    (tbNormalizedAmount, tokenOriginAddress, tokenOriginChain, toAddress, toChain, offset) =
      decodeTransferCdUnchecked(vaaPayload, offset);
    
    vaaPayload.length.checkLength(offset);
  }

  function decodeTransferCdUnchecked(bytes calldata vaaPayload, uint offset) internal pure returns(
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain,
    uint newOffset
  ) {
    (uint8 payloadId, offset) = vaaPayload.asUint8CdUnchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_TRANSFER);

    (
      tbNormalizedAmount,
      tokenOriginAddress,
      tokenOriginChain,
      toAddress,
      toChain,
      offset
    ) = decodeTransferCommonCdUnchecked(vaaPayload, offset);

    offset += 32; //skip fee - not supported and always 0
    newOffset = offset;
  }

  function decodeTransferWithPayloadMetaCdUnchecked(
    bytes calldata vaaPayload,
    uint offset
  ) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain,
    bytes32 fromAddress,
    uint newOffset
  ) {
    (uint8 payloadId, offset) = vaaPayload.asUint8CdUnchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_TRANSFER_WITH_PAYLOAD);

    (
      tbNormalizedAmount,
      tokenOriginAddress,
      tokenOriginChain,
      toAddress,
      toChain,
      offset
    ) = decodeTransferCommonCdUnchecked(vaaPayload, offset);

    (fromAddress, offset) = vaaPayload.asBytes32CdUnchecked(offset);
    newOffset = offset;
  }

  //only a mother can love this function name
  function decodeTransferWithPayloadPayloadCd(
    bytes calldata vaaPayload
  ) internal pure returns (bytes memory payload) {
    return decodeTransferWithPayloadPayloadCd(vaaPayload, _TRANSFER_WITH_PAYLOAD_META_SIZE);
  }

  function decodeTransferWithPayloadPayloadCd(
    bytes calldata vaaPayload,
    uint offset
  ) internal pure returns (bytes memory payload) {
    BytesParsing.checkBound(offset, vaaPayload.length);
    (payload, ) = vaaPayload.sliceCdUnchecked(offset, vaaPayload.length - offset);
  }

  function decodeTransferCommonCdUnchecked(
    bytes calldata vaaPayload,
    uint offset
  ) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain,
    uint newOffset
  ) {
    (tbNormalizedAmount, offset) = vaaPayload.asUint256CdUnchecked(offset);
    (tokenOriginAddress, offset) = vaaPayload.asBytes32CdUnchecked(offset);
    (tokenOriginChain,   offset) = vaaPayload.asUint16CdUnchecked(offset);
    (toAddress,          offset) = vaaPayload.asBytes32CdUnchecked(offset);
    (toChain,            offset) = vaaPayload.asUint16CdUnchecked(offset);
    newOffset = offset;
  }

  // memory variants

  function decodeTransfer(bytes memory vaaPayload) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain
  ) {
    return decodeTransfer(vaaPayload, 0);
  }

  function decodeTransfer(bytes memory vaaPayload, uint offset) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain
  ) {
    (tbNormalizedAmount, tokenOriginAddress, tokenOriginChain, toAddress, toChain, offset) =
      decodeTransferUnchecked(vaaPayload, offset);

    vaaPayload.checkLength(offset);
  }

  function decodeTransferUnchecked(bytes memory vaaPayload, uint offset) internal pure returns(
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain,
    uint newOffset
  ) {
    (uint8 payloadId, offset) = vaaPayload.asUint8Unchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_TRANSFER);

    (
      tbNormalizedAmount,
      tokenOriginAddress,
      tokenOriginChain,
      toAddress,
      toChain,
      offset
    ) = decodeTransferCommonUnchecked(vaaPayload, offset);

    offset += 32; //skip fee - not supported and always 0
    newOffset = offset;
  }

  function decodeTransferWithPayloadMetaUnchecked(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain,
    bytes32 fromAddress,
    uint newOffset
  ) {
    (uint8 payloadId, offset) = vaaPayload.asUint8Unchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_TRANSFER_WITH_PAYLOAD);

    (
      tbNormalizedAmount,
      tokenOriginAddress,
      tokenOriginChain,
      toAddress,
      toChain,
      offset
    ) = decodeTransferCommonUnchecked(vaaPayload, offset);

    (fromAddress, offset) = vaaPayload.asBytes32Unchecked(offset);
    newOffset = offset;
  }

  //only a mother can love this function name
  function decodeTransferWithPayloadPayload(
    bytes memory vaaPayload
  ) internal pure returns (bytes memory payload) {
    return decodeTransferWithPayloadPayload(vaaPayload, _TRANSFER_WITH_PAYLOAD_META_SIZE);
  }

  function decodeTransferWithPayloadPayload(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (bytes memory payload) {
    BytesParsing.checkBound(offset, vaaPayload.length);
    (payload, ) = vaaPayload.sliceUnchecked(offset, vaaPayload.length - offset);
  }

  function decodeTransferWithPayloadPayload(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (bytes memory payload) {
    BytesParsing.checkBound(offset, vaaPayload.length);
    (payload, ) = vaaPayload.sliceUnchecked(offset, vaaPayload.length - offset);
  }

  function decodeTransferCommonUnchecked(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (
    uint256 tbNormalizedAmount,
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    bytes32 toAddress,
    uint16 toChain,
    uint newOffset
  ) {
    (tbNormalizedAmount, offset) = vaaPayload.asUint256Unchecked(offset);
    (tokenOriginAddress, offset) = vaaPayload.asBytes32Unchecked(offset);
    (tokenOriginChain,   offset) = vaaPayload.asUint16Unchecked(offset);
    (toAddress,          offset) = vaaPayload.asBytes32Unchecked(offset);
    (toChain,            offset) = vaaPayload.asUint16Unchecked(offset);
    newOffset = offset;
  }

  // Attest meta payloads

  function encodeAttestMeta(
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    uint8 decimals,
    bytes32 symbol,
    bytes32 name
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      PAYLOAD_ID_ATTEST_META,
      tokenOriginAddress,
      tokenOriginChain,
      decimals,
      symbol,
      name
    );
  }

  //calldata variants

  function decodeAttestMetaCd(bytes calldata vaaPayload) internal pure returns (
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    uint8 decimals,
    bytes32 symbol,
    bytes32 name
  ) {
    return decodeAttestMetaCd(vaaPayload, 0);
  }

  function decodeAttestMetaCd(bytes calldata vaaPayload, uint offset) internal pure returns (
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    uint8 decimals,
    bytes32 symbol,
    bytes32 name
  ) {
    (tokenOriginAddress, tokenOriginChain, decimals, symbol, name, offset) =
      decodeAttestMetaCdUnchecked(vaaPayload, offset);
    
    vaaPayload.length.checkLength(offset);
  }

  function decodeAttestMetaCdUnchecked(
    bytes calldata vaaPayload,
    uint offset
  ) internal pure returns (
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    uint8 decimals,
    bytes32 symbol,
    bytes32 name,
    uint newOffset
  ) {
    (uint8 payloadId,    offset) = vaaPayload.asUint8CdUnchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_ATTEST_META);

    (tokenOriginAddress, offset) = vaaPayload.asBytes32CdUnchecked(offset);
    (tokenOriginChain,   offset) = vaaPayload.asUint16CdUnchecked(offset);
    (decimals,           offset) = vaaPayload.asUint8CdUnchecked(offset);
    (symbol,             offset) = vaaPayload.asBytes32CdUnchecked(offset);
    (name,               offset) = vaaPayload.asBytes32CdUnchecked(offset);
    newOffset = offset;
  }

  //memory variants

  function decodeAttestMeta(bytes memory vaaPayload) internal pure returns (
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    uint8 decimals,
    bytes32 symbol,
    bytes32 name
  ) {
    return decodeAttestMetaUnchecked(vaaPayload, 0);
  }

  function decodeAttestMeta(bytes memory vaaPayload, uint offset) internal pure returns (
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    uint8 decimals,
    bytes32 symbol,
    bytes32 name
  ) {
    (tokenOriginAddress, tokenOriginChain, decimals, symbol, name, offset) =
      decodeAttestMetaUnchecked(vaaPayload, offset);

    vaaPayload.checkLength(offset);
  }

  function decodeAttestMetaUnchecked(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (
    bytes32 tokenOriginAddress,
    uint16 tokenOriginChain,
    uint8 decimals,
    bytes32 symbol,
    bytes32 name,
    uint newOffset
  ) {
    (uint8 payloadId,    offset) = vaaPayload.asUint8Unchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_ATTEST_META);

    (tokenOriginAddress, offset) = vaaPayload.asBytes32Unchecked(offset);
    (tokenOriginChain,   offset) = vaaPayload.asUint16Unchecked(offset);
    (decimals,           offset) = vaaPayload.asUint8Unchecked(offset);
    (symbol,             offset) = vaaPayload.asBytes32Unchecked(offset);
    (name,               offset) = vaaPayload.asBytes32Unchecked(offset);
    newOffset = offset;
  }
}
