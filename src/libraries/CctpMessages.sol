// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {eagerAnd, eagerOr} from "wormhole-sdk/Utils.sol";

// ╭─────────────────────────────────────────────────────────────────────────────────────╮
// │ Library for encoding and decoding CCTP MessageTransmitter & TokenMessenger messages │
// ╰─────────────────────────────────────────────────────────────────────────────────────╯

// # Basic Analogy (~=)
//
// Wormhole CoreBridge  ~= Circle's MessageTransmitter
// Wormhole TokenBridge ~= Circle's TokenMessenger
//
// see:
//  * https://developers.circle.com/stablecoins/docs/message-format
//  * (Generic) CCTP Message - https://github.com/circlefin/evm-cctp-contracts/blob/master/src/messages/Message.sol
//  * CCTP TokenBurn payload - https://github.com/circlefin/evm-cctp-contracts/blob/master/src/TokenMessenger.sol
//
//        VAA   │   CCTP
// ─────────────┼─────────────────────
//       header │ attestation
//         body │ message
//     envelope │ message header
//  vaa.payload │ message.messageBody
//
// Unlike the Wormhole CoreBridge which broadcasts, Circle Messages always have an intended
//   destination and recipient.
// Another difference is that CCTP messages are "redeemed" by calling receiveMessage() on Circle's
//   MessageTransmitter which in turn invokes handleReceiveMessage() on the recipient of the
//   message, see https://github.com/circlefin/evm-cctp-contracts/blob/adb2a382b09ea574f4d18d8af5b6706e8ed9b8f2/src/MessageTransmitter.sol#L294-L295
// So even messages that originate from the TokenMessenger are first sent to the MessageTransmitter
//   upon redemption, whereas Wormhole TokenBridge messages must be redeemed with the TokenBridge,
//   which internally verifies the veracity of the VAA with the CoreBridge.
// To provide a similar restriction like the TokenBridge's redeemWithPayload() function, which can
//   only be called by the recipient of a TokenBridge TransferWithPayload message, Circle provides
//   an additional, optional field named destinationCaller which must be the caller of
//   receiveMessage() when it has been specified (i.e. the field is != 0).
//
// # Message Formats
//
// All CCTP messages consist of a header (~= VAA's envelope) followed by a message body (~=
//   VAA payload - unfortunate name clash cf. VAA body).
// Unlike a VAA, which contains the guardian signatures, CCTP attestations are not part of the
//   message format and are passed along separately.
//
// ╭─────────┬───────────────────┬──────────────────────────────────────────────────────────────╮
// │  Type   │       Name        │       Description                                            │
// ┝━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │       (Generic) CCTP Message (~= VAA envelope, but with dedicated recipient)               │
// ├─────────┬───────────────────┬──────────────────────────────────────────────────────────────┤
// │  uint32 │ headerVersion     │ ~= VAA.version, see MESSAGE_TRANSMITTER_HEADER_VERSION below │
// │  uint32 │ sourceDomain      │ ~= VAA.emitterChainId but using Circle's domain id instead   │
// │  uint32 │ destinationDomain │ ~= TokenBridge.toChainId but  - " " -                        │
// │  uint64 │ nonce             │ ~= VAA.sequence, but global rather than per emitter          │
// │ bytes32 │ sender            │ ~= VAA.emitterAddress                                        │
// │ bytes32 │ recipient         │ address that will have handleReceiveMessage() invoked        │
// │ bytes32 │ destinationCaller │ see explanation above, zero means unrestricted               │
// │   bytes │ messageBody       │ ~= VAA.payload                                               │
// ┝━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │       CCTP TokenBurn Payload (~= TokenBridge Transfer Payload)                             │
// ├─────────┬───────────────────┬──────────────────────────────────────────────────────────────┤
// │  uint32 │ bodyVersion       │ fixed value, see TOKEN_MESSENGER_BODY_VERSION below          │
// │ bytes32 │ burnToken         │ ~= TokenBridge.tokenAddress                                  │
// │ bytes32 │ mintRecipient     │ ~= TokenBridge.toAddress                                     │
// │ uint256 │ amount            │ the number of tokens burned/minted (no normalization)        │
// │ bytes32 │ messageSender     │ ~= TokenBridge.fromAddress, invoker of depositAndBurn        │
// ╰─────────┴───────────────────┴──────────────────────────────────────────────────────────────╯
//
// # Library Functions & Naming Conventions
//
// All decoding library functions come in 2 flavors:
//   1. Calldata (using the Cd tag)
//   2. Memory (using the Mem tag)
//
// Additionally, most functions also have a raw vs. struct flavor, where the former
//   return the values on the stack, while the latter allocate the associated struct in memory.
//
// The parameter name `encodedMsg` is used for functions where the bytes are expected to contain
//   a single, full CCTP message. Otherwise, i.e. for partials or multiple messages, the name
//   `encoded` is used.
//
// Like in BytesParsing, the Unchecked function name suffix does not refer to Solidity's `unchecked`
//   keyword, but rather to the fact that no bounds checking is performed.
//
// Function names, somewhat redundantly, contain the tag "Cctp" to add clarity and avoid potential
//   name collisions when using the library with a `using ... for bytes` directive.
//
// Decoding functions flavorless base names:
//   * decodeCctpHeader
//   * decodeCctpMessage
//   * decodeCctpTokenBurnBody
//   * decodeCctpTokenBurnMessage
//
// Encoding functions (should only be relevant for testing):
//   * encode (overloaded for each struct)
//   * encodeCctpHeader
//   * encodeCctpMessage
//   * encodeCctpTokenBurnMessage
//
// Other functions:
//   * isCctpTokenBurnMessage (Mem/Cd)

struct CctpHeader {
  //uint32 headerVersion;
  uint32 sourceDomain;
  uint32 destinationDomain;
  uint64 nonce;
  bytes32 sender;
  bytes32 recipient;
  bytes32 destinationCaller;
}

struct CctpMessage {
  CctpHeader header;
  bytes messageBody;
}

struct CctpTokenBurnBody {
  //uint32 bodyVersion;
  bytes32 burnToken;
  bytes32 mintRecipient;
  uint256 amount;
  bytes32 messageSender;
}

struct CctpTokenBurnMessage {
  CctpHeader header;
  CctpTokenBurnBody body;
}

library CctpMessageLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkBound, BytesParsing.checkLength} for uint;

  error InvalidCctpMessageHeaderVersion();
  error InvalidCctpMessageBodyVersion();

  //returned by MessageTransmitter.version() - see here:
  //https://github.com/circlefin/evm-cctp-contracts/blob/1662356f9e60bb3f18cb6d09f95f628f0cc3637f/src/MessageTransmitter.sol#L238
  //it's actually not a constant but an immutable, which does not make a whole lot of sense
  //in practice it's set to 0, see https://etherscan.io/address/0x0a992d191deec32afe36203ad87d7d289a738f81#readContract#F15
  uint32 constant HEADER_VERSION = 0;

  //returned by TokenMessenger.messageBodyVersion() - see here:
  //https://github.com/circlefin/evm-cctp-contracts/blob/1662356f9e60bb3f18cb6d09f95f628f0cc3637f/src/TokenMessenger.sol#L107
  //same silliness as for header version, see https://etherscan.io/address/0xbd3fa81b58ba92a82136038b25adec7066af3155#readContract#F3
  uint32 constant TOKEN_MESSENGER_BODY_VERSION = 0;

  // Header format offsets and sizes
  uint internal constant HEADER_VERSION_OFFSET = 0;
  uint internal constant HEADER_VERSION_SIZE = 4;

  uint internal constant HEADER_SOURCE_DOMAIN_OFFSET =
    HEADER_VERSION_OFFSET + HEADER_VERSION_SIZE;
  uint internal constant HEADER_SOURCE_DOMAIN_SIZE = 4;

  uint internal constant HEADER_DESTINATION_DOMAIN_OFFSET =
    HEADER_SOURCE_DOMAIN_OFFSET + HEADER_SOURCE_DOMAIN_SIZE;
  uint internal constant HEADER_DESTINATION_DOMAIN_SIZE = 4;

  uint internal constant HEADER_NONCE_OFFSET =
    HEADER_DESTINATION_DOMAIN_OFFSET + HEADER_DESTINATION_DOMAIN_SIZE;
  uint internal constant HEADER_NONCE_SIZE = 8;

  uint internal constant HEADER_SENDER_OFFSET =
    HEADER_NONCE_OFFSET + HEADER_NONCE_SIZE;
  uint internal constant HEADER_SENDER_SIZE = 32;

  uint internal constant HEADER_RECIPIENT_OFFSET =
    HEADER_SENDER_OFFSET + HEADER_SENDER_SIZE;
  uint internal constant HEADER_RECIPIENT_SIZE = 32;

  uint internal constant HEADER_DESTINATION_CALLER_OFFSET =
    HEADER_RECIPIENT_OFFSET + HEADER_RECIPIENT_SIZE;
  uint internal constant HEADER_DESTINATION_CALLER_SIZE = 32;

  uint internal constant HEADER_SIZE =
    HEADER_DESTINATION_CALLER_OFFSET + HEADER_DESTINATION_CALLER_SIZE;

  // TokenBurn format offsets and sizes
  uint internal constant TOKEN_BURN_BODY_OFFSET = HEADER_SIZE;

  uint internal constant TOKEN_BURN_BODY_VERSION_OFFSET = 0;
  uint internal constant TOKEN_BURN_BODY_VERSION_SIZE = 4;

  uint internal constant TOKEN_BURN_BODY_TOKEN_OFFSET =
    TOKEN_BURN_BODY_VERSION_OFFSET + TOKEN_BURN_BODY_VERSION_SIZE;
  uint internal constant TOKEN_BURN_BODY_TOKEN_SIZE = 32;

  uint internal constant TOKEN_BURN_BODY_MINT_RECIPIENT_OFFSET =
    TOKEN_BURN_BODY_TOKEN_OFFSET + TOKEN_BURN_BODY_TOKEN_SIZE;
  uint internal constant TOKEN_BURN_BODY_MINT_RECIPIENT_SIZE = 32;

  uint internal constant TOKEN_BURN_BODY_AMOUNT_OFFSET =
    TOKEN_BURN_BODY_MINT_RECIPIENT_OFFSET + TOKEN_BURN_BODY_MINT_RECIPIENT_SIZE;
  uint internal constant TOKEN_BURN_BODY_AMOUNT_SIZE = 32;

  uint internal constant TOKEN_BURN_BODY_MESSAGE_SENDER_OFFSET =
    TOKEN_BURN_BODY_AMOUNT_OFFSET + TOKEN_BURN_BODY_AMOUNT_SIZE;
  uint internal constant TOKEN_BURN_BODY_MESSAGE_SENDER_SIZE = 32;

  uint internal constant TOKEN_BURN_BODY_SIZE =
    TOKEN_BURN_BODY_MESSAGE_SENDER_OFFSET + TOKEN_BURN_BODY_MESSAGE_SENDER_SIZE;

  uint internal constant TOKEN_BURN_MESSAGE_SIZE =
    HEADER_SIZE + TOKEN_BURN_BODY_SIZE;

  // ------------ Message Type Checking Functions ------------

  function isCctpTokenBurnMessageCd(bytes calldata encodedMsg) internal pure returns (bool) {
    (uint headerVersion,) = encodedMsg.asUint32CdUnchecked(HEADER_VERSION_OFFSET);
    (uint bodyVersion,  ) = encodedMsg.asUint32CdUnchecked(
      TOKEN_BURN_BODY_OFFSET + TOKEN_BURN_BODY_VERSION_OFFSET
    );
    return _isCctpTokenBurnMessage(headerVersion, bodyVersion, encodedMsg.length);
  }

  function isCctpTokenBurnMessageMem(bytes memory encodedMsg) internal pure returns (bool) {
    (uint headerVersion,) = encodedMsg.asUint32MemUnchecked(HEADER_VERSION_OFFSET);
    (uint bodyVersion,  ) = encodedMsg.asUint32MemUnchecked(
      TOKEN_BURN_BODY_OFFSET + TOKEN_BURN_BODY_VERSION_OFFSET
    );
    return _isCctpTokenBurnMessage(headerVersion, bodyVersion, encodedMsg.length);
  }

  function _isCctpTokenBurnMessage(
    uint headerVersion,
    uint bodyVersion,
    uint messageLength
  ) private pure returns (bool) {
    //avoid short-circuiting to save gas and code size
    return eagerAnd(
      eagerAnd(messageLength == TOKEN_BURN_MESSAGE_SIZE, headerVersion == HEADER_VERSION),
      bodyVersion == TOKEN_MESSENGER_BODY_VERSION
    );
  }

  // ------------ Convenience Decoding Functions ------------

  function decodeCctpMessageCd(
    bytes calldata encodedMsg
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes calldata messageBody
  ) {
    uint bodyOffset; //optimization because we have it on the stack already
                     //should always equal TOKEN_BURN_BODY_OFFSET
    ( sourceDomain,
      destinationDomain,
      nonce,
      sender,
      recipient,
      destinationCaller,
      bodyOffset
    ) = decodeCctpHeaderCdUnchecked(encodedMsg);
    //check to avoid underflow in following subtraction
    //we avoid using the built-in encodedMsg[bodyOffset:] so we only get BytesParsing errors
    bodyOffset.checkBound(encodedMsg.length);
    (messageBody, ) = encodedMsg.sliceCdUnchecked(bodyOffset, encodedMsg.length - bodyOffset);
  }

  function decodeCctpMessageStructCd(
    bytes calldata encodedMsg
  ) internal pure returns (CctpMessage memory message) {
    ( message.header.sourceDomain,
      message.header.destinationDomain,
      message.header.nonce,
      message.header.sender,
      message.header.recipient,
      message.header.destinationCaller,
      message.messageBody
    ) = decodeCctpMessageCd(encodedMsg);
  }

  function decodeCctpMessageMem(
    bytes memory encodedMsg
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes memory messageBody
  ) {
    ( sourceDomain,
      destinationDomain,
      nonce,
      sender,
      recipient,
      destinationCaller,
      messageBody,
    ) = decodeCctpMessageMemUnchecked(encodedMsg, 0, encodedMsg.length);
  }

  function decodeCctpMessageStructMem(
    bytes memory encodedMsg
  ) internal pure returns (CctpMessage memory message) {
    ( message.header.sourceDomain,
      message.header.destinationDomain,
      message.header.nonce,
      message.header.sender,
      message.header.recipient,
      message.header.destinationCaller,
      message.messageBody,
    ) = decodeCctpMessageMemUnchecked(encodedMsg, 0, encodedMsg.length);
  }

  function decodeCctpTokenBurnMessageCd(
    bytes calldata encodedMsg
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender
  ) {
    uint offset;
    ( sourceDomain,
      destinationDomain,
      nonce,
      sender,
      recipient,
      destinationCaller,
      offset
    ) = decodeCctpHeaderCdUnchecked(encodedMsg);
    ( burnToken,
      mintRecipient,
      amount,
      messageSender,
      offset
    ) = decodeCctpTokenBurnBodyCd(encodedMsg, offset);
    encodedMsg.length.checkLength(offset);
  }

  function decodeCctpTokenBurnMessageStructCd(
    bytes calldata encodedMsg
  ) internal pure returns (CctpTokenBurnMessage memory message) {
    ( message.header.sourceDomain,
      message.header.destinationDomain,
      message.header.nonce,
      message.header.sender,
      message.header.recipient,
      message.header.destinationCaller,
      message.body.burnToken,
      message.body.mintRecipient,
      message.body.amount,
      message.body.messageSender
    ) = decodeCctpTokenBurnMessageCd(encodedMsg);
  }

  function decodeCctpTokenBurnMessageMem(
    bytes memory encodedMsg
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender
  ) {
    uint offset;
    ( sourceDomain,
      destinationDomain,
      nonce,
      sender,
      recipient,
      destinationCaller,
      burnToken,
      mintRecipient,
      amount,
      messageSender,
      offset
    ) = decodeCctpTokenBurnMessageMemUnchecked(encodedMsg, 0);
    encodedMsg.length.checkLength(offset);
  }

  function decodeCctpTokenBurnMessageStructMem(
    bytes memory encodedMsg
  ) internal pure returns (CctpTokenBurnMessage memory message) {
    ( message.header.sourceDomain,
      message.header.destinationDomain,
      message.header.nonce,
      message.header.sender,
      message.header.recipient,
      message.header.destinationCaller,
      message.body.burnToken,
      message.body.mintRecipient,
      message.body.amount,
      message.body.messageSender
    ) = decodeCctpTokenBurnMessageMem(encodedMsg);
  }

  // ------------ Advanced Decoding Functions ------------

  function checkHeaderVersion(uint32 version) internal pure {
    if (version != HEADER_VERSION)
      revert InvalidCctpMessageHeaderVersion();
  }

  function checkTokenMessengerBodyVersion(uint32 version) internal pure {
    if (version != TOKEN_MESSENGER_BODY_VERSION)
      revert InvalidCctpMessageBodyVersion();
  }

  function decodeCctpHeaderCdUnchecked(
    bytes calldata encoded
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    uint    bodyOffset
  ) {
    uint offset = 0;
    uint32 version;
    (version,           offset) = encoded.asUint32CdUnchecked(offset);
    checkHeaderVersion(version);
    (sourceDomain,      offset) = encoded.asUint32CdUnchecked(offset);
    (destinationDomain, offset) = encoded.asUint32CdUnchecked(offset);
    (nonce,             offset) = encoded.asUint64CdUnchecked(offset);
    (sender,            offset) = encoded.asBytes32CdUnchecked(offset);
    (recipient,         offset) = encoded.asBytes32CdUnchecked(offset);
    (destinationCaller, offset) = encoded.asBytes32CdUnchecked(offset);
    bodyOffset = offset;
  }

  function decodeCctpHeaderStructCdUnchecked(
    bytes calldata encodedMsg
  ) internal pure returns (CctpHeader memory header, uint bodyOffset) {
    ( header.sourceDomain,
      header.destinationDomain,
      header.nonce,
      header.sender,
      header.recipient,
      header.destinationCaller,
      bodyOffset
    ) = decodeCctpHeaderCdUnchecked(encodedMsg);
  }

  function decodeCctpHeaderMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    uint    bodyOffset
  ) {
    uint32 version;
    (version,           offset) = encoded.asUint32MemUnchecked(offset);
    checkHeaderVersion(version);
    (sourceDomain,      offset) = encoded.asUint32MemUnchecked(offset);
    (destinationDomain, offset) = encoded.asUint32MemUnchecked(offset);
    (nonce,             offset) = encoded.asUint64MemUnchecked(offset);
    (sender,            offset) = encoded.asBytes32MemUnchecked(offset);
    (recipient,         offset) = encoded.asBytes32MemUnchecked(offset);
    (destinationCaller, offset) = encoded.asBytes32MemUnchecked(offset);
    bodyOffset = offset;
  }

  function decodeCctpHeaderStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (CctpHeader memory header, uint bodyOffset) {
    ( header.sourceDomain,
      header.destinationDomain,
      header.nonce,
      header.sender,
      header.recipient,
      header.destinationCaller,
      bodyOffset
    ) = decodeCctpHeaderMemUnchecked(encoded, offset);
  }

  function decodeCctpMessageMemUnchecked(
    bytes memory encoded,
    uint offset,
    uint messageLength
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes memory messageBody,
    uint newOffset
  ) { unchecked {
    (sourceDomain, destinationDomain, nonce, sender, recipient, destinationCaller, offset) =
      decodeCctpHeaderMemUnchecked(encoded, offset);
    offset.checkBound(messageLength);
    (messageBody, offset) = encoded.sliceMemUnchecked(offset, messageLength - offset);
    newOffset = offset;
  }}

  function decodeCctpMessageStructMemUnchecked(
    bytes memory encoded,
    uint offset,
    uint messageLength
  ) internal pure returns (CctpMessage memory message, uint newOffset) {
    ( message.header.sourceDomain,
      message.header.destinationDomain,
      message.header.nonce,
      message.header.sender,
      message.header.recipient,
      message.header.destinationCaller,
      message.messageBody,
      newOffset
    ) = decodeCctpMessageMemUnchecked(encoded, offset, messageLength);
  }

  function decodeCctpTokenBurnBodyCd(
    bytes calldata encoded,
    uint bodyOffset
  ) internal pure returns (
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender,
    uint newOffset
  ) {
    uint offset = bodyOffset;
    uint32 version;
    (version,       offset) = encoded.asUint32CdUnchecked(offset);
    checkTokenMessengerBodyVersion(version);
    (burnToken,     offset) = encoded.asBytes32CdUnchecked(offset);
    (mintRecipient, offset) = encoded.asBytes32CdUnchecked(offset);
    (amount,        offset) = encoded.asUint256CdUnchecked(offset);
    (messageSender, offset) = encoded.asBytes32CdUnchecked(offset);
    newOffset = offset;
  }

  function decodeCctpTokenBurnBodyStructCd(
    bytes calldata encodedMsg,
    uint bodyOffset
  ) internal pure returns (CctpTokenBurnBody memory body, uint newOffset) {
    ( body.burnToken,
      body.mintRecipient,
      body.amount,
      body.messageSender,
      newOffset
    ) = decodeCctpTokenBurnBodyCd(encodedMsg, bodyOffset);
  }

  function decodeCctpTokenBurnBodyMemUnchecked(
    bytes memory encodedMsg,
    uint bodyOffset
  ) internal pure returns (
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender,
    uint newOffset
  ) {
    uint offset = bodyOffset;
    uint32 version;
    (version,       offset) = encodedMsg.asUint32MemUnchecked(offset);
    checkTokenMessengerBodyVersion(version);
    (burnToken,     offset) = encodedMsg.asBytes32MemUnchecked(offset);
    (mintRecipient, offset) = encodedMsg.asBytes32MemUnchecked(offset);
    (amount,        offset) = encodedMsg.asUint256MemUnchecked(offset);
    (messageSender, offset) = encodedMsg.asBytes32MemUnchecked(offset);
    newOffset = offset;
  }

  function decodeCctpTokenBurnBodyStructMemUnchecked(
    bytes memory encodedMsg,
    uint offset
  ) internal pure returns (CctpTokenBurnBody memory body, uint newOffset) {
    ( body.burnToken,
      body.mintRecipient,
      body.amount,
      body.messageSender,
      newOffset
    ) = decodeCctpTokenBurnBodyMemUnchecked(encodedMsg, offset);
  }

  function decodeCctpTokenBurnMessageMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint32  sourceDomain,
    uint32  destinationDomain,
    uint64  nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender,
    uint newOffset
  ) {
    (sourceDomain, destinationDomain, nonce, sender, recipient, destinationCaller, offset) =
      decodeCctpHeaderMemUnchecked(encoded, offset);
    (burnToken, mintRecipient, amount, messageSender, offset) =
      decodeCctpTokenBurnBodyMemUnchecked(encoded, offset);
    newOffset = offset;
  }

  function decodeCctpTokenBurnMessageStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (CctpTokenBurnMessage memory message, uint newOffset) {
    (message.header, offset) = decodeCctpHeaderStructMemUnchecked(encoded, offset);
    (message.body,   offset) = decodeCctpTokenBurnBodyStructMemUnchecked(encoded, newOffset);
    newOffset = offset;
  }

  // ------------ Encoding ------------

  function encodeCctpMessage(
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes memory messageBody
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      encodeCctpHeader(
        sourceDomain,
        destinationDomain,
        nonce,
        sender,
        recipient,
        destinationCaller
      ),
      messageBody
    );
  }

  function encode(CctpMessage memory message) internal pure returns (bytes memory) {
    return encodeCctpMessage(
      message.header.sourceDomain,
      message.header.destinationDomain,
      message.header.nonce,
      message.header.sender,
      message.header.recipient,
      message.header.destinationCaller,
      message.messageBody
    );
  }

  function encodeCctpTokenBurnMessage(
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      encodeCctpHeader(
        sourceDomain,
        destinationDomain,
        nonce,
        sender,
        recipient,
        destinationCaller
      ),
      encodeCctpTokenBurnBody(burnToken, mintRecipient, amount, messageSender)
    );
  }

  function encode(CctpTokenBurnMessage memory burnMsg) internal pure returns (bytes memory) {
    return abi.encodePacked(encode(burnMsg.header), encode(burnMsg.body));
  }

  function encodeCctpHeader(
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      HEADER_VERSION,
      sourceDomain,
      destinationDomain,
      nonce,
      sender,
      recipient,
      destinationCaller
    );
  }

  function encode(CctpHeader memory header) internal pure returns (bytes memory) {
    return encodeCctpHeader(
      header.sourceDomain,
      header.destinationDomain,
      header.nonce,
      header.sender,
      header.recipient,
      header.destinationCaller
    );
  }

  function encodeCctpTokenBurnBody(
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      TOKEN_MESSENGER_BODY_VERSION,
      burnToken,
      mintRecipient,
      amount,
      messageSender
    );
  }

  function encode(CctpTokenBurnBody memory burnBody) internal pure returns (bytes memory) {
    return encodeCctpTokenBurnBody(
      burnBody.burnToken,
      burnBody.mintRecipient,
      burnBody.amount,
      burnBody.messageSender
    );
  }
}

using CctpMessageLib for CctpMessage global;
using CctpMessageLib for CctpTokenBurnMessage global;
using CctpMessageLib for CctpHeader global;
using CctpMessageLib for CctpTokenBurnBody global;
