// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {BytesParsing} from "../libraries/BytesParsing.sol";

// ╭───────────────────────────────────────────────────────────────────────╮
// │ Library for encoding and decoding WormholeCctpTokenMessenger messages │
// ╰───────────────────────────────────────────────────────────────────────╯

library WormholeCctpMessageLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  uint8 internal constant PAYLOAD_ID_DEPOSIT = 1;

  // uint private constant _DEPOSIT_META_SIZE =
  //   32 /*universalTokenAddress*/ +
  //   32 /*amount*/ +
  //   4 /*sourceCctpDomain*/ +
  //   4 /*targetCctpDomain*/ +
  //   8 /*cctpNonce*/ +
  //   32 /*burnSource*/ +
  //   32 /*mintRecipient*/;

  error PayloadTooLarge(uint256);
  error InvalidPayloadId(uint8);

  function encodeDeposit(
    bytes32 universalTokenAddress,
    uint256 amount,
    uint32  sourceCctpDomain,
    uint32  targetCctpDomain,
    uint64  cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) internal pure returns (bytes memory) {
    uint payloadLen = payload.length;
    if (payloadLen > type(uint16).max)
      revert PayloadTooLarge(payloadLen);

    return abi.encodePacked(
      PAYLOAD_ID_DEPOSIT,
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

  function decodeDepositCd(bytes calldata vaaPayload) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32  sourceCctpDomain,
    uint32  targetCctpDomain,
    uint64  cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes calldata payload
  ) {
    uint offset = 0;
    ( token,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      offset
    ) = decodeDepositHeaderCdUnchecked(vaaPayload, offset);

    (payload, offset) = decodeDepositPayloadCdUnchecked(vaaPayload, offset);
    vaaPayload.length.checkLength(offset);
  }

  function decodeDepositHeaderCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32  sourceCctpDomain,
    uint32  targetCctpDomain,
    uint64  cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    uint payloadOffset
  ) {
    uint8 payloadId;
    (payloadId,        offset) = encoded.asUint8CdUnchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_DEPOSIT);
    (token,            offset) = encoded.asBytes32CdUnchecked(offset);
    (amount,           offset) = encoded.asUint256CdUnchecked(offset);
    (sourceCctpDomain, offset) = encoded.asUint32CdUnchecked(offset);
    (targetCctpDomain, offset) = encoded.asUint32CdUnchecked(offset);
    (cctpNonce,        offset) = encoded.asUint64CdUnchecked(offset);
    (burnSource,       offset) = encoded.asBytes32CdUnchecked(offset);
    (mintRecipient,    offset) = encoded.asBytes32CdUnchecked(offset);
    payloadOffset = offset;
  }

  function decodeDepositPayloadCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes calldata payload, uint newOffset) {
    (payload, newOffset) = encoded.sliceUint16PrefixedCdUnchecked(offset);
  }

  function decodeDepositMem(bytes memory vaaPayload) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32  sourceCctpDomain,
    uint32  targetCctpDomain,
    uint64  cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) {
    uint offset = 0;
    ( token,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      offset
    ) = decodeDepositHeaderMemUnchecked(vaaPayload, 0);

    (payload, offset) = decodeDepositPayloadMemUnchecked(vaaPayload, offset);
    vaaPayload.length.checkLength(offset);
  }

  function decodeDepositHeaderMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32  sourceCctpDomain,
    uint32  targetCctpDomain,
    uint64  cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    uint payloadOffset
  ) {
    uint8 payloadId;
    (payloadId,        offset) = encoded.asUint8MemUnchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_DEPOSIT);
    (token,            offset) = encoded.asBytes32MemUnchecked(offset);
    (amount,           offset) = encoded.asUint256MemUnchecked(offset);
    (sourceCctpDomain, offset) = encoded.asUint32MemUnchecked(offset);
    (targetCctpDomain, offset) = encoded.asUint32MemUnchecked(offset);
    (cctpNonce,        offset) = encoded.asUint64MemUnchecked(offset);
    (burnSource,       offset) = encoded.asBytes32MemUnchecked(offset);
    (mintRecipient,    offset) = encoded.asBytes32MemUnchecked(offset);
    payloadOffset = offset;
  }

  function decodeDepositPayloadMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory payload, uint newOffset) {
    (payload, newOffset) = encoded.sliceUint16PrefixedMemUnchecked(offset);
  }

  function checkPayloadId(uint8 encoded, uint8 expected) internal pure {
    if (encoded != expected)
      revert InvalidPayloadId(encoded);
  }
}
