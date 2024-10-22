
// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/**
 * Payment to the target failed.
 */
error PaymentFailure(address target);

using SafeERC20 for IERC20;
function transferTokens(address token, address to, uint256 amount) {
  if (token == address(0))
    _transferEth(to, amount);
  else
    IERC20(token).safeTransfer(to, amount);
}

function _transferEth(address to, uint256 amount) {
  if (amount == 0) return;

  (bool success, ) = to.call{value: amount}(new bytes(0));
  if (!success) revert PaymentFailure(to);
}