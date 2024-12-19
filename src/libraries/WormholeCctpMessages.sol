// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";

//Message format emitted by WormholeCctpTokenMessenger
//  Looks similar to the CCTP message format but is its own distinct format that goes into
//    a VAA payload, and mirrors the information in the corresponding CCTP message.
library WormholeCctpMessages {
  using { toUniversalAddress } for address;
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  uint8 private constant _DEPOSIT_ID = 1;

  uint private constant _DEPOSIT_META_SIZE =
    32 /*universalTokenAddress*/ +
    32 /*amount*/ +
    4 /*sourceCctpDomain*/ +
    4 /*targetCctpDomain*/ +
    8 /*cctpNonce*/ +
    32 /*burnSource*/ +
    32 /*mintRecipient*/;

  error PayloadTooLarge(uint256);
  error InvalidPayloadId(uint8);

  function encodeDeposit(
    bytes32 universalTokenAddress,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) internal pure returns (bytes memory) {
    uint payloadLen = payload.length;
    if (payloadLen > type(uint16).max)
      revert PayloadTooLarge(payloadLen);

    return abi.encodePacked(
      _DEPOSIT_ID,
      universalTokenAddress,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      uint16(payloadLen),
      payload
    );
  }

  // calldata variant

  function decodeDepositMetaCd(bytes calldata vaaPayload) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient
  ) {
    return decodeDepositMetaCd(vaaPayload, 0);
  }

  function decodeDepositMetaCd(bytes calldata vaaPayload, uint offset) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient
  ) {
    (
      token,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      payload,
      offset
    ) = decodeDepositCdUnchecked(vaaPayload, offset);

    vaaPayload.length.checkLength(offset);
  }

  function decodeDepositMetaCdUnchecked(
    bytes calldata vaaPayload,
    uint offset
  ) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    uint newOffset
  ) {
    uint8 payloadId;
    (payloadId,        offset) = vaaPayload.asUint8CdUnchecked(offset);
    if (payloadId != _DEPOSIT_ID)
      revert InvalidPayloadId(payloadId);

    (token,            offset) = vaaPayload.asBytes32CdUnchecked(offset);
    (amount,           offset) = vaaPayload.asUint256CdUnchecked(offset);
    (sourceCctpDomain, offset) = vaaPayload.asUint32CdUnchecked(offset);
    (targetCctpDomain, offset) = vaaPayload.asUint32CdUnchecked(offset);
    (cctpNonce,        offset) = vaaPayload.asUint64CdUnchecked(offset);
    (burnSource,       offset) = vaaPayload.asBytes32CdUnchecked(offset);
    (mintRecipient,    offset) = vaaPayload.asBytes32CdUnchecked(offset);
    newOffset = offset;
  }

  function decodeDepositPayloadCd(bytes calldata vaaPayload) internal pure returns (bytes memory) {
    return decodeDepositPayloadCd(vaaPayload, _DEPOSIT_META_SIZE);
  }

  function decodeDepositPayloadCd(
    bytes calldata vaaPayload,
    uint offset
  ) internal pure returns (bytes memory payload) {
    (payload, offset) = decodeDepositPayloadCdUnchecked(vaaPayload, offset);
    vaaPayload.length.checkLength(offset);
  }

  function decodeDepositPayloadCdUnchecked(
    bytes calldata vaaPayload,
    uint offset
  ) internal pure returns (bytes memory payload, uint newOffset) {
    (payload, offset) = vaaPayload.sliceUint16PrefixedCdUnchecked(offset);
    newOffset = offset;
  }

  // memory variant

  function decodeDepositMeta(bytes memory vaaPayload) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient
  ) {
    return decodeDepositMeta(vaaPayload, 0);
  }

  function decodeDepositMeta(bytes memory vaaPayload, uint offset) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient
  ) {
    (
      token,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      payload,
      offset
    ) = decodeDepositUnchecked(vaaPayload, offset);

    vaaPayload.length.checkLength(offset);
  }

  function decodeDepositMetaUnchecked(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    uint newOffset
  ) {
    uint8 payloadId;
    (payloadId,        offset) = vaaPayload.asUint8Unchecked(offset);
    if (payloadId != _DEPOSIT_ID)
      revert InvalidPayloadId(payloadId);

    (token,            offset) = vaaPayload.asBytes32Unchecked(offset);
    (amount,           offset) = vaaPayload.asUint256Unchecked(offset);
    (sourceCctpDomain, offset) = vaaPayload.asUint32Unchecked(offset);
    (targetCctpDomain, offset) = vaaPayload.asUint32Unchecked(offset);
    (cctpNonce,        offset) = vaaPayload.asUint64Unchecked(offset);
    (burnSource,       offset) = vaaPayload.asBytes32Unchecked(offset);
    (mintRecipient,    offset) = vaaPayload.asBytes32Unchecked(offset);
    newOffset = offset;
  }

  function decodeDepositPayload(bytes memory vaaPayload) internal pure returns (bytes memory) {
    return decodeDepositPayload(vaaPayload, _DEPOSIT_META_SIZE);
  }

  function decodeDepositPayload(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (bytes memory payload) {
    (payload, offset) = decodeDepositPayloadUnchecked(vaaPayload, offset);
    vaaPayload.length.checkLength(offset);
  }

  function decodeDepositPayloadUnchecked(
    bytes memory vaaPayload,
    uint offset
  ) internal pure returns (bytes memory payload, uint newOffset) {
    (payload, offset) = vaaPayload.sliceUint16PrefixedUnchecked(offset);
    newOffset = offset;
  }
}
