// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.24;

import "wormhole-sdk/libraries/CctpMessages.sol";

// This file was auto-generated by wormhole-solidity-sdk gen/libraryTestWrapper.ts

contract CctpMessageLibTestWrapper {
  function isCctpTokenBurnMessageCd(bytes calldata encodedMsg) external pure returns (bool) {
    return CctpMessageLib.isCctpTokenBurnMessageCd(encodedMsg);
  }

  function isCctpTokenBurnMessageMem(bytes calldata encodedMsg) external pure returns (bool) {
    return CctpMessageLib.isCctpTokenBurnMessageMem(encodedMsg);
  }

  function decodeCctpMessageCd(bytes calldata encodedMsg) external pure returns (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes calldata messageBody
  ) {
    return CctpMessageLib.decodeCctpMessageCd(encodedMsg);
  }

  function decodeCctpMessageStructCd(bytes calldata encodedMsg) external pure returns (CctpMessage memory message) {
    return CctpMessageLib.decodeCctpMessageStructCd(encodedMsg);
  }

  function decodeCctpMessageMem(bytes calldata encodedMsg) external pure returns (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes memory messageBody
  ) {
    return CctpMessageLib.decodeCctpMessageMem(encodedMsg);
  }

  function decodeCctpMessageStructMem(bytes calldata encodedMsg) external pure returns (CctpMessage memory message) {
    return CctpMessageLib.decodeCctpMessageStructMem(encodedMsg);
  }

  function decodeCctpTokenBurnMessageCd(bytes calldata encodedMsg) external pure returns (
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
  ) {
    return CctpMessageLib.decodeCctpTokenBurnMessageCd(encodedMsg);
  }

  function decodeCctpTokenBurnMessageStructCd(bytes calldata encodedMsg) external pure returns (CctpTokenBurnMessage memory message) {
    return CctpMessageLib.decodeCctpTokenBurnMessageStructCd(encodedMsg);
  }

  function decodeCctpTokenBurnMessageMem(bytes calldata encodedMsg) external pure returns (
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
  ) {
    return CctpMessageLib.decodeCctpTokenBurnMessageMem(encodedMsg);
  }

  function decodeCctpTokenBurnMessageStructMem(bytes calldata encodedMsg) external pure returns (CctpTokenBurnMessage memory message) {
    return CctpMessageLib.decodeCctpTokenBurnMessageStructMem(encodedMsg);
  }

  function checkHeaderVersion(uint32 version) external pure {
    CctpMessageLib.checkHeaderVersion(version);
  }

  function checkTokenMessengerBodyVersion(uint32 version) external pure {
    CctpMessageLib.checkTokenMessengerBodyVersion(version);
  }

  function decodeCctpHeaderCdUnchecked(bytes calldata encoded) external pure returns (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    uint bodyOffset
  ) {
    return CctpMessageLib.decodeCctpHeaderCdUnchecked(encoded);
  }

  function decodeCctpHeaderStructCdUnchecked(bytes calldata encodedMsg) external pure returns (CctpHeader memory header, uint bodyOffset) {
    return CctpMessageLib.decodeCctpHeaderStructCdUnchecked(encodedMsg);
  }

  function decodeCctpHeaderMemUnchecked(bytes calldata encoded, uint offset) external pure returns (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    uint bodyOffset
  ) {
    return CctpMessageLib.decodeCctpHeaderMemUnchecked(encoded, offset);
  }

  function decodeCctpHeaderStructMemUnchecked(bytes calldata encoded, uint offset) external pure returns (CctpHeader memory header, uint bodyOffset) {
    return CctpMessageLib.decodeCctpHeaderStructMemUnchecked(encoded, offset);
  }

  function decodeCctpMessageMemUnchecked(
    bytes calldata encoded,
    uint offset,
    uint messageLength
  ) external pure returns (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes memory messageBody,
    uint newOffset
  ) {
    return CctpMessageLib.decodeCctpMessageMemUnchecked(encoded, offset, messageLength);
  }

  function decodeCctpMessageStructMemUnchecked(
    bytes calldata encoded,
    uint offset,
    uint messageLength
  ) external pure returns (CctpMessage memory message, uint newOffset) {
    return CctpMessageLib.decodeCctpMessageStructMemUnchecked(encoded, offset, messageLength);
  }

  function decodeCctpTokenBurnBodyCd(bytes calldata encoded, uint bodyOffset) external pure returns (
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender,
    uint newOffset
  ) {
    return CctpMessageLib.decodeCctpTokenBurnBodyCd(encoded, bodyOffset);
  }

  function decodeCctpTokenBurnBodyStructCd(bytes calldata encodedMsg, uint bodyOffset) external pure returns (CctpTokenBurnBody memory body, uint newOffset) {
    return CctpMessageLib.decodeCctpTokenBurnBodyStructCd(encodedMsg, bodyOffset);
  }

  function decodeCctpTokenBurnBodyMemUnchecked(bytes calldata encodedMsg, uint bodyOffset) external pure returns (
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender,
    uint newOffset
  ) {
    return CctpMessageLib.decodeCctpTokenBurnBodyMemUnchecked(encodedMsg, bodyOffset);
  }

  function decodeCctpTokenBurnBodyStructMemUnchecked(bytes calldata encodedMsg, uint offset) external pure returns (CctpTokenBurnBody memory body, uint newOffset) {
    return CctpMessageLib.decodeCctpTokenBurnBodyStructMemUnchecked(encodedMsg, offset);
  }

  function decodeCctpTokenBurnMessageMemUnchecked(bytes calldata encoded, uint offset) external pure returns (
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender,
    uint newOffset
  ) {
    return CctpMessageLib.decodeCctpTokenBurnMessageMemUnchecked(encoded, offset);
  }

  function decodeCctpTokenBurnMessageStructMemUnchecked(bytes calldata encoded, uint offset) external pure returns (CctpTokenBurnMessage memory message, uint newOffset) {
    return CctpMessageLib.decodeCctpTokenBurnMessageStructMemUnchecked(encoded, offset);
  }

  function encodeCctpMessage(
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes calldata messageBody
  ) external pure returns (bytes memory) {
    return CctpMessageLib.encodeCctpMessage(sourceDomain, destinationDomain, nonce, sender, recipient, destinationCaller, messageBody);
  }

  function encode(CctpMessage calldata message) external pure returns (bytes memory) {
    return CctpMessageLib.encode(message);
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
  ) external pure returns (bytes memory) {
    return CctpMessageLib.encodeCctpTokenBurnMessage(sourceDomain, destinationDomain, nonce, sender, recipient, destinationCaller, burnToken, mintRecipient, amount, messageSender);
  }

  function encode(CctpTokenBurnMessage calldata burnMsg) external pure returns (bytes memory) {
    return CctpMessageLib.encode(burnMsg);
  }

  function encodeCctpHeader(
    uint32 sourceDomain,
    uint32 destinationDomain,
    uint64 nonce,
    bytes32 sender,
    bytes32 recipient,
    bytes32 destinationCaller
  ) external pure returns (bytes memory) {
    return CctpMessageLib.encodeCctpHeader(sourceDomain, destinationDomain, nonce, sender, recipient, destinationCaller);
  }

  function encode(CctpHeader calldata header) external pure returns (bytes memory) {
    return CctpMessageLib.encode(header);
  }

  function encodeCctpTokenBurnBody(
    bytes32 burnToken,
    bytes32 mintRecipient,
    uint256 amount,
    bytes32 messageSender
  ) external pure returns (bytes memory) {
    return CctpMessageLib.encodeCctpTokenBurnBody(burnToken, mintRecipient, amount, messageSender);
  }

  function encode(CctpTokenBurnBody calldata burnBody) external pure returns (bytes memory) {
    return CctpMessageLib.encode(burnBody);
  }
}
