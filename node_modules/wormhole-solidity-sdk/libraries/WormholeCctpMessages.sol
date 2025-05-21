// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IWormhole} from "../interfaces/IWormhole.sol";
import {BytesParsing} from "./BytesParsing.sol";
import {toUniversalAddress} from "../Utils.sol";

//Message format emitted by WormholeCctpTokenMessenger
//  Looks similar to the CCTP message format but is its own distinct format that goes into
//    a VAA payload, and mirrors the information in the corresponding CCTP message.
library WormholeCctpMessages {
  using { toUniversalAddress } for address;
  using BytesParsing for bytes;

  // Payload IDs.
  //
  // NOTE: This library reserves payloads 1 through 10 for future use. When using this library,
  // please consider starting your own Wormhole message payloads at 11.
  uint8 private constant DEPOSIT     =  1;
  uint8 private constant RESERVED_2  =  2;
  uint8 private constant RESERVED_3  =  3;
  uint8 private constant RESERVED_4  =  4;
  uint8 private constant RESERVED_5  =  5;
  uint8 private constant RESERVED_6  =  6;
  uint8 private constant RESERVED_7  =  7;
  uint8 private constant RESERVED_8  =  8;
  uint8 private constant RESERVED_9  =  9;
  uint8 private constant RESERVED_10 = 10;

  error PayloadTooLarge(uint256);
  error InvalidMessage();

  function encodeDeposit(
    bytes32 universalTokenAddress,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) internal pure returns (bytes memory encoded) {
    uint payloadLen = payload.length;
    if (payloadLen > type(uint16).max)
      revert PayloadTooLarge(payloadLen);

    encoded = abi.encodePacked(
      DEPOSIT,
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
  
  function asDepositUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload,
    uint newOffset
  ) {
    uint8 payloadId;
    (payloadId,        offset) = encoded.asUint8Unchecked(offset);
    if (payloadId != DEPOSIT)
      revert InvalidMessage();

    (token,            offset) = encoded.asBytes32Unchecked(offset);
    (amount,           offset) = encoded.asUint256Unchecked(offset);
    (sourceCctpDomain, offset) = encoded.asUint32Unchecked(offset);
    (targetCctpDomain, offset) = encoded.asUint32Unchecked(offset);
    (cctpNonce,        offset) = encoded.asUint64Unchecked(offset);
    (burnSource,       offset) = encoded.asBytes32Unchecked(offset);
    (mintRecipient,    offset) = encoded.asBytes32Unchecked(offset);
    (payload,          offset) = encoded.sliceUint16PrefixedUnchecked(offset);
    newOffset = offset;
  }

  function asDepositCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload,
    uint newOffset
  ) {
    uint8 payloadId;
    (payloadId,        offset) = encoded.asUint8CdUnchecked(offset);
    if (payloadId != DEPOSIT)
      revert InvalidMessage();

    (token,            offset) = encoded.asBytes32CdUnchecked(offset);
    (amount,           offset) = encoded.asUint256CdUnchecked(offset);
    (sourceCctpDomain, offset) = encoded.asUint32CdUnchecked(offset);
    (targetCctpDomain, offset) = encoded.asUint32CdUnchecked(offset);
    (cctpNonce,        offset) = encoded.asUint64CdUnchecked(offset);
    (burnSource,       offset) = encoded.asBytes32CdUnchecked(offset);
    (mintRecipient,    offset) = encoded.asBytes32CdUnchecked(offset);
    (payload,          offset) = encoded.sliceUint16PrefixedCdUnchecked(offset);
    newOffset = offset;
  }

  function decodeDeposit(bytes memory encoded) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) {
    uint offset = 0;
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
    ) = asDepositUnchecked(encoded, offset);

    encoded.checkLength(offset);
  }
}
