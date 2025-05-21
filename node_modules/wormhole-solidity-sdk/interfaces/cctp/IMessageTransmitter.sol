// SPDX-License-Identifier: Apache 2
// Copyright (c) 2022, Circle Internet Financial Limited.
//
// stripped, flattened version of:
//   https://github.com/circlefin/evm-cctp-contracts/blob/master/src/MessageTransmitter.sol

pragma solidity ^0.8.0;

import {IOwnable2Step} from "./shared/IOwnable2Step.sol";
import {IPausable} from "./shared/IPausable.sol";

interface IAttestable {
  event AttesterEnabled(address indexed attester);
  event AttesterDisabled(address indexed attester);

  event SignatureThresholdUpdated(uint256 oldSignatureThreshold, uint256 newSignatureThreshold);
  event AttesterManagerUpdated(
    address indexed previousAttesterManager,
    address indexed newAttesterManager
  );

  function attesterManager() external view returns (address);
  function isEnabledAttester(address attester) external view returns (bool);
  function getNumEnabledAttesters() external view returns (uint256);
  function getEnabledAttester(uint256 index) external view returns (address);

  function updateAttesterManager(address newAttesterManager) external;
  function setSignatureThreshold(uint256 newSignatureThreshold) external;
  function enableAttester(address attester) external;
  function disableAttester(address attester) external;
}

interface IMessageTransmitter is IAttestable, IPausable, IOwnable2Step {
  event MessageSent(bytes message);

  event MessageReceived(
    address indexed caller,
    uint32 sourceDomain,
    uint64 indexed nonce,
    bytes32 sender,
    bytes messageBody
  );

  function localDomain() external view returns (uint32);
  function version() external view returns (uint32);
  function maxMessageBodySize() external view returns (uint256);
  function nextAvailableNonce() external view returns (uint64);
  function usedNonces(bytes32 nonce) external view returns (bool);

  function sendMessage(
    uint32 destinationDomain,
    bytes32 recipient,
    bytes calldata messageBody
  ) external returns (uint64);

  function sendMessageWithCaller(
    uint32 destinationDomain,
    bytes32 recipient,
    bytes32 destinationCaller,
    bytes calldata messageBody
  ) external returns (uint64);

  function replaceMessage(
    bytes calldata originalMessage,
    bytes calldata originalAttestation,
    bytes calldata newMessageBody,
    bytes32 newDestinationCaller
  ) external;

  function receiveMessage(
    bytes calldata message,
    bytes calldata attestation
  ) external returns (bool success);

  function setMaxMessageBodySize(uint256 newMaxMessageBodySize) external;
}
