// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2022, Circle Internet Financial Limited.
//stripped version of:
//https://github.com/circlefin/evm-cctp-contracts/blob/master/src/interfaces/ITokenMinter.sol

pragma solidity ^0.8.0;

import {IOwnable2Step} from "./shared/IOwnable2Step.sol";
import {IPausable} from "./shared/IPausable.sol";

interface ITokenController {
  event TokenPairLinked(address localToken, uint32 remoteDomain, bytes32 remoteToken);
  event TokenPairUnlinked(address localToken, uint32 remoteDomain, bytes32 remoteToken);

  event SetBurnLimitPerMessage(address indexed token, uint256 burnLimitPerMessage);
  event SetTokenController(address tokenController);

  function burnLimitsPerMessage(address token) external view returns (uint256);
  function remoteTokensToLocalTokens(bytes32 sourceIdHash) external view returns (address);
  function tokenController() external view returns (address);

  function linkTokenPair(address localToken, uint32 remoteDomain, bytes32 remoteToken) external;
  function unlinkTokenPair(address localToken, uint32 remoteDomain, bytes32 remoteToken) external;
  function setMaxBurnAmountPerMessage(address localToken, uint256 burnLimitPerMessage) external;
}

interface ITokenMinter is ITokenController, IPausable, IOwnable2Step {
  event LocalTokenMessengerAdded(address localTokenMessenger);
  event LocalTokenMessengerRemoved(address localTokenMessenger);

  function localTokenMessenger() external view returns (address);
  function getLocalToken(uint32 remoteDomain, bytes32 remoteToken) external view returns (address);

  function mint(uint32 sourceDomain, bytes32 burnToken, address to, uint256 amount) external;
  function burn(address burnToken, uint256 burnAmount) external;

  function addLocalTokenMessenger(address newLocalTokenMessenger) external;
  function removeLocalTokenMessenger() external;
  function setTokenController(address newTokenController) external;
}
