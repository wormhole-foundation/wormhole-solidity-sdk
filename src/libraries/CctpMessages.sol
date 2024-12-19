// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {eagerAnd, eagerOr} from "wormhole-sdk/Utils.sol";

// ┌─────────────────────────────────────────────────────────────────────────────────────┐
// │ Library for encoding and decoding CCTP MessageTransmitter & TokenMessenger messages │
// └─────────────────────────────────────────────────────────────────────────────────────┘

//#Basic Analogy
//
//  Circle's MessageTransmitter <> Wormhole CoreBridge
//  Circle's TokenMessenger     <> Wormhole TokenBridge
//
//Unlike the Wormhole CoreBridge which broadcasts, Circle Messages always have an intended
//  destination and recipient.
//Another difference is that Cctp messages are "redeemed" by calling receiveMessage() on the
//  Circle Message Transmitter which in turn invokes handleReceiveMessage() on the recipient of
//  the message, see https://github.com/circlefin/evm-cctp-contracts/blob/adb2a382b09ea574f4d18d8af5b6706e8ed9b8f2/src/MessageTransmitter.sol#L294-L295
//So even messages that originate from the TokenMessenger are first sent to the MessageTransmitter
//  whereas Wormhole TokenBridge messages must be redeemed with the TokenBridge, which internally
//  verifies the veracity of the VAA with the CoreBridge.
//To provide a similar restriction like the TokenBridge's redeemWithPayload() function, which can
//  only be called by the recipient of the TokenBridge transferWithPayload message, Circle provides
//  an additional, optional field named destinationCaller which must be the caller of
//  receiveMessage() when it has been specified (i.e. the field is != 0).

//#Message Formats
//
//Header - https://github.com/circlefin/evm-cctp-contracts/blob/master/src/messages/Message.sol
//
//    Type  │       Name        │     Description
// ─────────┼───────────────────┼──────────────────────────────────────────────────────────────────
//   uint32 │ headerVersion     │ fixed value: see MESSAGE_TRANSMITTER_HEADER_VERSION below
//   uint32 │ sourceDomain      │
//   uint32 │ destinationDomain │
//   uint64 │ nonce             │
//  bytes32 │ sender            │ for TokenMessenger messages this is the source TokenMessenger
//  bytes32 │ recipient         │ for TokenMessenger messages this is the destination TokenMessenger
//  bytes32 │ destinationCaller │ zero means anyone can redeem the message
//
//All Messages
// Always a header, followed by a message body (akin to a VAA's payload).
// Just like a VAA the body has no length prefix but simply consumes the remainder of the message.
//
//TokenBurn body (~= TokenBridge Transfer (with optional destinationCaller restriction))
//
//    Type  │       Name    │     Description
// ─────────┼───────────────┼──────────────────────────────────────────────────────────────────
//   uint32 │ bodyVersion   │ fixed value: see TOKEN_MESSENGER_BODY_VERSION below
//  bytes32 │ burnToken     │ source token contract address whose tokens were burned (e.g. USDC)
//  bytes32 │ mintRecipient │ address on the destination domain to mint the new tokens to
//  uint256 │ amount        │ the number of tokens burned/minted
//  bytes32 │ messageSender │ address of caller of depositAndBurn on the source chain

error InvalidCctpMessageHeaderVersion();
error InvalidCctpMessageBodyVersion();

//Function Families:
//1. Message Encoding
//   - encode(CctpHeader)
//   - encode(CctpMessage) 
//   - encode(CctpTokenBurnMessage)
//
//2. Message Type Checking
//   - isCctpTokenBurnMessageCd(encoded)
//   - isCctpTokenBurnMessage(encoded)
//
//3. Decoding Functions
// TODO
library CctpMessages {
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  uint private constant _CCTP_HEADER_SIZE = 3*4 + 8 + 3*32;
  uint private constant _CCTP_TOKEN_BURN_MESSAGE_SIZE = _CCTP_HEADER_SIZE + 4 + 4*32;

  //returned by MessageTransmitter.version() - see here:
  //https://github.com/circlefin/evm-cctp-contracts/blob/1662356f9e60bb3f18cb6d09f95f628f0cc3637f/src/MessageTransmitter.sol#L238
  uint32 constant MESSAGE_TRANSMITTER_HEADER_VERSION = 0;

  //returned by TokenMessenger.messageBodyVersion() - see here:
  //https://github.com/circlefin/evm-cctp-contracts/blob/1662356f9e60bb3f18cb6d09f95f628f0cc3637f/src/TokenMessenger.sol#L107
  uint32 constant TOKEN_MESSENGER_BODY_VERSION = 0;

  // ------------ Message Encoding Functions ------------
  function encode(CctpHeader memory header) internal pure returns (bytes memory) {
    return abi.encodePacked(
      MESSAGE_TRANSMITTER_HEADER_VERSION,
      header.sourceDomain,
      header.destinationDomain,
      header.nonce,
      header.sender,
      header.recipient,
      header.destinationCaller
    );
  }

  function encode(CctpMessage memory message) internal pure returns (bytes memory) {
    return abi.encodePacked(
      encode(message.header),
      message.messageBody
    );
  }

  function encode(CctpTokenBurnMessage memory burnMsg) internal pure returns (bytes memory) {
    return abi.encodePacked(
      encode(burnMsg.header),
      TOKEN_MESSENGER_BODY_VERSION,
      burnMsg.burnToken,
      burnMsg.mintRecipient,
      burnMsg.amount,
      burnMsg.messageSender
    );
  }

  // ------------ Message Type Checking Functions ------------

  function isCctpTokenBurnMessageCd(bytes calldata encoded) internal pure returns (bool) {
    (uint headerVersion,) = encoded.asUint32CdUnchecked(0);
    (uint bodyVersion,  ) = encoded.asUint32CdUnchecked(_CCTP_HEADER_SIZE);
    //avoid short-circuiting to save gas and code size
    return eagerAnd(eagerAnd(
      encoded.length == _CCTP_TOKEN_BURN_MESSAGE_SIZE,
       headerVersion == MESSAGE_TRANSMITTER_HEADER_VERSION,
         bodyVersion == TOKEN_MESSENGER_BODY_VERSION
    ));
  }

  function isCctpTokenBurnMessage(bytes memory encoded) internal pure returns (bool) {
    (uint headerVersion,) = encoded.asUint32Unchecked(0);
    (uint bodyVersion,  ) = encoded.asUint32Unchecked(_CCTP_HEADER_SIZE);
    return eagerAnd(eagerAnd(
      encoded.length == _CCTP_TOKEN_BURN_MESSAGE_SIZE,
       headerVersion == MESSAGE_TRANSMITTER_HEADER_VERSION,
         bodyVersion == TOKEN_MESSENGER_BODY_VERSION
    ));
  }

  // ------------ Header Decoding Functions ------------

  function decodeCctpHeaderCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns  (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    uint newOffset
  ) {
    uint32 version;
    (version,           offset) = encoded.asUint32CdUnchecked(offset);
    if (version != MESSAGE_TRANSMITTER_HEADER_VERSION)
      revert InvalidCctpMessageHeaderVersion();

    (sourceDomain,      offset) = encoded.asUint32CdUnchecked(offset);
    (destinationDomain, offset) = encoded.asUint32CdUnchecked(offset);
    (nonce,             offset) = encoded.asUint64CdUnchecked(offset);
    (sender,            offset) = encoded.asBytes32CdUnchecked(offset);
    (recipient,         offset) = encoded.asBytes32CdUnchecked(offset);
    (destinationCaller, offset) = encoded.asBytes32CdUnchecked(offset);
    newOffset = offset;
  }

  function decodeCctpHeaderUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    uint newOffset
  ) {
    uint32 version;
    (version,           offset) = encoded.asUint32Unchecked(offset);
    if (version != MESSAGE_TRANSMITTER_HEADER_VERSION)
      revert InvalidCctpMessageHeaderVersion();

    (sourceDomain,      offset) = encoded.asUint32Unchecked(offset);
    (destinationDomain, offset) = encoded.asUint32Unchecked(offset);
    (nonce,             offset) = encoded.asUint64Unchecked(offset);
    (sender,            offset) = encoded.asBytes32Unchecked(offset);
    (recipient,         offset) = encoded.asBytes32Unchecked(offset);
    (destinationCaller, offset) = encoded.asBytes32Unchecked(offset);
    newOffset = offset;
  }

  // ------------ Message Decoding Functions ------------

  function decodeCctpMessageCd(bytes calldata encoded) internal pure returns (CctpMessage memory) {
    return decodeCctpMessageCd(encoded, 0);
  }

  function decodeCctpMessageCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (CctpMessage memory ret) { unchecked {
    (ret.header, offset) = decodeCctpHeaderCdUnchecked(encoded, offset);

    BytesParsing.checkBound(offset, encoded.length);
    ret.messageBody = encoded.sliceCdUnchecked(offset, encoded.length - offset);
  }}

  function decodeCctpMessage(bytes memory encoded) internal pure returns (CctpMessage memory) {
    return decodeCctpMessageCd(encoded, 0);
  }

  function decodeCctpMessage(
    bytes memory encoded,
    uint offset
  ) internal pure returns (CctpMessage memory ret) { unchecked {
    (ret.header, offset) = decodeCctpHeaderUnchecked(encoded, offset);
    BytesParsing.checkBound(offset, encoded.length);
    ret.messageBody = encoded.sliceUnchecked(offset, encoded.length - offset);
  }}

  // ------------ Token Burn Message Decoding Functions ------------

  function decodeCctpTokenBurnMessageCd(
    bytes calldata encoded
  ) internal pure returns (CctpTokenBurnMessage memory) {
    return decodeCctpTokenBurnMessageCd(encoded, 0);
  }

  function decodeCctpTokenBurnMessageCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (CctpTokenBurnMessage memory ret) {
    (ret, offset) = decodeCctpTokenBurnMessageCdUnchecked(encoded, offset);
    encoded.length.checkLength(offset);
  }

  function decodeCctpTokenBurnMessageCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (CctpTokenBurnMessage memory ret, uint newOffset) {
    (ret.header, offset) = decodeCctpHeaderCdUnchecked(encoded, offset);
    uint32 version;
    (version,           offset) = encoded.asUint32CdUnchecked(offset);
    if (version != TOKEN_MESSENGER_BODY_VERSION)
      revert InvalidCctpMessageBodyVersion();

    (ret.burnToken,     offset) = encoded.asBytes32CdUnchecked(offset);
    (ret.mintRecipient, offset) = encoded.asBytes32CdUnchecked(offset);
    (ret.amount,        offset) = encoded.asUint256CdUnchecked(offset);
    (ret.messageSender, offset) = encoded.asBytes32CdUnchecked(offset);
    newOffset = offset;
  }

  function decodeCctpTokenBurnMessage(
    bytes memory encoded
  ) internal pure returns (CctpTokenBurnMessage memory) {
    return decodeCctpTokenBurnMessage(encoded, 0);
  }

  function decodeCctpTokenBurnMessage(
    bytes memory encoded,
    uint offset
  ) internal pure returns (CctpTokenBurnMessage memory ret) {
    (ret, offset) = decodeCctpTokenBurnMessageUnchecked(encoded, offset);
    encoded.checkLength(offset);
  }

  function decodeCctpTokenBurnMessageUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (CctpTokenBurnMessage memory ret, uint newOffset) {
    (bytes memory encHeader, offset) = encoded.sliceUnchecked(offset, _CCTP_HEADER_SIZE);
    ret.header = decodeCctpHeaderUnchecked(encHeader);
    uint32 version;
    (version,           offset) = encoded.asUint32Unchecked(offset);
    if (version != TOKEN_MESSENGER_BODY_VERSION)
      revert InvalidCctpMessageBodyVersion();
    (ret.burnToken,     offset) = encoded.asBytes32Unchecked(offset);
    (ret.mintRecipient, offset) = encoded.asBytes32Unchecked(offset);
    (ret.amount,        offset) = encoded.asUint256Unchecked(offset);
    (ret.messageSender, offset) = encoded.asBytes32Unchecked(offset);
    newOffset = offset;
  }
}