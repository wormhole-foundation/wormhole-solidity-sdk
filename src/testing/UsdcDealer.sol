// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";

import "IERC20/IERC20.sol";
import {VM_ADDRESS} from "wormhole-sdk/testing/Constants.sol";

interface IUSDC is IERC20 {
  function masterMinter() external view returns (address);

  function mint(address to, uint256 amount) external;
  function configureMinter(address minter, uint256 minterAllowedAmount) external;
}

//workaround because forge's `deal()` does not work reliably to mint usdc (for some reason)
library UsdcDealer {
  Vm constant vm = Vm(VM_ADDRESS);

  function deal(IUSDC usdc, address to, uint256 amount) internal {
    vm.prank(usdc.masterMinter());
    usdc.configureMinter(address(this), amount);
    usdc.mint(address(to), amount);
  }
}
