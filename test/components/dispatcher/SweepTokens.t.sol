// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {SWEEP_TOKENS_ID}    from "wormhole-sdk/components/dispatcher/Ids.sol";
import {UpgradeTester}      from "wormhole-sdk/testing/UpgradeTester.sol";
import {ERC20Mock}          from "wormhole-sdk/testing/ERC20Mock.sol";
import {DispatcherTestBase} from "./utils/DispatcherTestBase.sol";

contract SweepTokensTest is DispatcherTestBase {
  ERC20Mock token;

  function _setUp1() internal override {
    token = new ERC20Mock("FakeToken", "FT");
  }

  function testSweepTokens_erc20() public {
    uint tokenAmount = 1e6;
    deal(address(token), address(dispatcher), tokenAmount);

    assertEq(token.balanceOf(owner), 0);
    assertEq(token.balanceOf(address(dispatcher)), tokenAmount);

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        SWEEP_TOKENS_ID, address(token), tokenAmount
      )
    );

    assertEq(token.balanceOf(address(dispatcher)), 0);
    assertEq(token.balanceOf(owner), tokenAmount);
  }

  function testSweepTokens_eth() public {
    uint ethAmount = 1 ether;
    vm.deal(address(dispatcher), ethAmount);
    uint ownerEthBalance = address(owner).balance;
    assertEq(address(dispatcher).balance, ethAmount);

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        SWEEP_TOKENS_ID, address(0), ethAmount
      )
    );

    assertEq(address(dispatcher).balance, 0);
    assertEq(address(owner).balance, ownerEthBalance + ethAmount);
  }
}
