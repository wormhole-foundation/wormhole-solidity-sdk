
// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IERC20} from "../interfaces/token/IERC20.sol";
import {SafeERC20} from "SafeERC20/SafeERC20.sol";

error PaymentFailure(address target);

//Note: Always forwards all gas, so consider gas griefing attack opportunities by the recipient.
//Note: Don't use this method if you need events for 0 amount transfers.
function tokenOrNativeTransfer(address tokenOrZeroForNative, address to, uint256 amount) {
  if (amount == 0)
    return;

  if (tokenOrZeroForNative == address(0)) {
    (bool success, ) = to.call{value: amount}(new bytes(0));
    if (!success)
      revert PaymentFailure(to);
  }
  else
    SafeERC20.safeTransfer(IERC20(tokenOrZeroForNative), to, amount);
}
