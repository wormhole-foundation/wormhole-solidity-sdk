// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

//Message format emitted by Circle MessageTransmitter - akin to Wormhole CoreBridge
//  see: https://github.com/circlefin/evm-cctp-contracts/blob/master/src/messages/Message.sol
//
//Unlike the Wormhole CoreBridge which broadcasts, Circle Messages always have an intended
//  destination and recipient.
//
//Cctp messages are "redeemed" by calling receiveMessage() on the Circle Message Transmitter
//  which in turn invokes handleReceiveMessage() on the recipient of the message:
//  see: https://github.com/circlefin/evm-cctp-contracts/blob/adb2a382b09ea574f4d18d8af5b6706e8ed9b8f2/src/MessageTransmitter.sol#L294-L295
//So even messages that originate from the TokenMessenger are first sent to the MessageTransmitter
//  whereas Wormhole TokenBridge messages must be redeemed with the TokenBridge, which internally
//  verifies the veracity of the VAA with the CoreBridge.
//To provide a similar restriction like the TokenBridge's redeemWithPayload() function which can
//  only be called by the recipient of the TokenBridge transferWithPayload message, Circle provides
//  an additional, optional field named destinationCaller which must be the caller of
//  receiveMessage() when it has been specified (i.e. the field is != 0).
struct CctpHeader {
  //uint32 headerVersion;
  uint32 sourceDomain;
  uint32 destinationDomain;
  uint64 nonce;
  //caller of the Circle Message Transmitter -> for us always the foreign TokenMessenger
  bytes32 sender;
  //caller of the Circle Message Transmitter -> for us always the local TokenMessenger
  bytes32 recipient;
  bytes32 destinationCaller;
}

struct CctpMessage {
  CctpHeader header;
  bytes messageBody;
}

struct CctpTokenBurnMessage {
  CctpHeader header;
  //uint32 bodyVersion;
  //the address of the USDC contract on the foreign domain whose tokens were burned
  bytes32 burnToken;
  //always our local WormholeCctpTokenMessenger contract (e.g. CircleIntegration, TokenRouter)a
  bytes32 mintRecipient;
  uint256 amount;
  //address of caller of depositAndBurn on the foreign chain - for us always foreignCaller
  bytes32 messageSender;
}

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

  function isCctpTokenBurnMessage(bytes memory encoded) internal pure returns (bool) {
    if (encoded.length != _CCTP_TOKEN_BURN_MESSAGE_SIZE)
      return false;

    (uint headerVersion,) = encoded.asUint32Unchecked(0);
    (uint bodyVersion,  ) = encoded.asUint32Unchecked(_CCTP_HEADER_SIZE);
    return headerVersion == MESSAGE_TRANSMITTER_HEADER_VERSION &&
             bodyVersion == TOKEN_MESSENGER_BODY_VERSION;
  }

  function decodeCctpHeader(
    bytes memory encoded
  ) internal pure returns (CctpHeader memory ret) {
    uint offset;
    uint32 version;
    (version,               offset) = encoded.asUint32Unchecked(offset);
    require(version == MESSAGE_TRANSMITTER_HEADER_VERSION, "cctp msg header version mismatch");
    (ret.sourceDomain,      offset) = encoded.asUint32Unchecked(offset);
    (ret.destinationDomain, offset) = encoded.asUint32Unchecked(offset);
    (ret.nonce,             offset) = encoded.asUint64Unchecked(offset);
    (ret.sender,            offset) = encoded.asBytes32Unchecked(offset);
    (ret.recipient,         offset) = encoded.asBytes32Unchecked(offset);
    (ret.destinationCaller, offset) = encoded.asBytes32Unchecked(offset);
    encoded.length.checkLength(offset);
  }

  function decodeCctpMessage(
    bytes memory encoded
  ) internal pure returns (CctpMessage memory ret) {
    (bytes memory encHeader, uint offset) = encoded.sliceUnchecked(0, _CCTP_HEADER_SIZE);
    ret.header = decodeCctpHeader(encHeader);
    (ret.messageBody, offset) = encoded.slice(offset, encoded.length - offset); //checked!
    return ret;
  }

  function decodeCctpTokenBurnMessage(
    bytes memory encoded
  ) internal pure returns (CctpTokenBurnMessage memory ret) {
    (bytes memory encHeader, uint offset) = encoded.sliceUnchecked(0, _CCTP_HEADER_SIZE);
    ret.header = decodeCctpHeader(encHeader);
    uint32 version;
    (version,           offset) = encoded.asUint32Unchecked(offset);
    require(version == TOKEN_MESSENGER_BODY_VERSION, "cctp msg body version mismatch");
    (ret.burnToken,     offset) = encoded.asBytes32Unchecked(offset);
    (ret.mintRecipient, offset) = encoded.asBytes32Unchecked(offset);
    (ret.amount,        offset) = encoded.asUint256Unchecked(offset);
    (ret.messageSender, offset) = encoded.asBytes32Unchecked(offset);
    encoded.length.checkLength(offset);
    return ret;
  }
}