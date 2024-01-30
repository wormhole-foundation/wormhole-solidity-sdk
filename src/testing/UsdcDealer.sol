// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";

import "wormhole-sdk/interfaces/token/IUSDC.sol";
import {VM_ADDRESS} from "./Constants.sol";

//for some reason, using forge's `deal()` to mint usdc does not work reliably
//  hence this workaround
library UsdcDealer {
  Vm constant vm = Vm(VM_ADDRESS);

  function deal(IUSDC usdc, address to, uint256 amount) internal {
    vm.prank(usdc.masterMinter());
    usdc.configureMinter(address(this), amount);
    usdc.mint(address(to), amount);
  }
}
