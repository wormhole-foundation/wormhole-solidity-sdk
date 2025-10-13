// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2022, Circle Internet Financial Limited.
//
// stripped version of:
//   https://github.com/circlefin/evm-cctp-contracts/blob/master/src/roles/Pausable.sol

pragma solidity ^0.8.0;

interface IPausable {
  event Pause();
  event Unpause();
  event PauserChanged(address indexed newAddress);

  function paused() external view returns (bool);
  function pauser() external view returns (address);

  function pause() external;
  function unpause() external;
  function updatePauser(address newPauser) external;
}
