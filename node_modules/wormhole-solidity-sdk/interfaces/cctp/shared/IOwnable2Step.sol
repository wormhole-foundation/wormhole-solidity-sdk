// SPDX-License-Identifier: Apache 2
// Copyright (c) 2022, Circle Internet Financial Limited.
//
// stripped, flattened version of:
//   https://github.com/circlefin/evm-cctp-contracts/blob/master/src/roles/Ownable2Step.sol

pragma solidity ^0.8.0;

interface IOwnable2Step {
  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  function transferOwnership(address newOwner) external;
  function acceptOwnership() external;

  function owner() external view returns (address);
  function pendingOwner() external view returns (address);
}
