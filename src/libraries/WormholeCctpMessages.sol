// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";

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

  error MissingPayload();
  error PayloadTooLarge(uint256);
  error InvalidMessage();

  /**
   * @dev NOTE: This method encodes the Wormhole message payload assuming the payload ID == 1.
   */
  function encodeDeposit(
    address token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) internal pure returns (bytes memory encoded) {
    encoded = encodeDeposit(
      token.toUniversalAddress(),
      DEPOSIT,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      payload
    );
  }

  /**
   * @dev NOTE: This method encodes the Wormhole message payload assuming the payload ID == 1.
   */
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
    encoded = encodeDeposit(
      universalTokenAddress,
      DEPOSIT,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      payload
    );
  }

  function encodeDeposit(
    address token,
    uint8 payloadId,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) internal pure returns (bytes memory encoded) {
    encoded = encodeDeposit(
      token.toUniversalAddress(),
      payloadId,
      amount,
      sourceCctpDomain,
      targetCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      payload
    );
  }

  function encodeDeposit(
    bytes32 universalTokenAddress,
    uint8 payloadId,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) internal pure returns (bytes memory encoded) {
    uint256 payloadLen = payload.length;
    if (payloadLen == 0)
      revert MissingPayload();
    else if (payloadLen > type(uint16).max)
      revert PayloadTooLarge(payloadLen);

    encoded = abi.encodePacked(
      payloadId,
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

  // left in for backwards compatibility
  function decodeDeposit(IWormhole.VM memory vaa) internal pure returns (
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 targetCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) {
    return decodeDeposit(vaa.payload);
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
    uint256 offset = _checkPayloadId(encoded, 0, DEPOSIT);

    (token,            offset) = encoded.asBytes32Unchecked(offset);
    (amount,           offset) = encoded.asUint256Unchecked(offset);
    (sourceCctpDomain, offset) = encoded.asUint32Unchecked(offset);
    (targetCctpDomain, offset) = encoded.asUint32Unchecked(offset);
    (cctpNonce,        offset) = encoded.asUint64Unchecked(offset);
    (burnSource,       offset) = encoded.asBytes32Unchecked(offset);
    (mintRecipient,    offset) = encoded.asBytes32Unchecked(offset);
    (payload,          offset) = encoded.sliceUint16PrefixedUnchecked(offset);

    encoded.checkLength(offset);
  }

  // ---------------------------------------- private -------------------------------------------

  function _checkPayloadId(
    bytes memory encoded,
    uint256 startOffset,
    uint8 expectedPayloadId
  ) private pure returns (uint256 offset) {
    uint8 parsedPayloadId;
    (parsedPayloadId, offset) = encoded.asUint8Unchecked(startOffset);

    if (parsedPayloadId != expectedPayloadId)
      revert InvalidMessage();
  }
}
