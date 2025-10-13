// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "IERC20/IERC20.sol";

interface IWETH is IERC20 {
  event Deposit(address indexed dst, uint amount);
  event Withdrawal(address indexed src, uint amount);

  function deposit() external payable;
  function withdraw(uint256 amount) external;
}
