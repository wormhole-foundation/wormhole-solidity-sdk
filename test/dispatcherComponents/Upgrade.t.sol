// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {NotAuthorized} from "wormhole-sdk/dispatcherComponents/AccessControl.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {UpgradeTester} from "wormhole-sdk/testing/UpgradeTester.sol";
import {IdempotentUpgrade} from "wormhole-sdk/proxy/ProxyBase.sol";
import {DispatcherTestBase} from "./utils/DispatcherTestBase.sol";
import "wormhole-sdk/dispatcherComponents/ids.sol";

contract UpgradeTest is DispatcherTestBase {
  using BytesParsing for bytes;

  function testContractUpgrade_NotAuthorized() public {
    address fakeAddress = makeAddr("fakeAddress");

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        UPGRADE_CONTRACT_ID,
        address(fakeAddress)
      )
    );

    vm.prank(admin);
    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        UPGRADE_CONTRACT_ID,
        address(fakeAddress)
      )
    );
  }

  function testContractUpgrade_IdempotentUpgrade() public {
    UpgradeTester upgradeTester = new UpgradeTester();

    vm.startPrank(owner);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        UPGRADE_CONTRACT_ID,
        address(upgradeTester)
      )
    );

    vm.expectRevert(IdempotentUpgrade.selector);
    UpgradeTester(address(dispatcher)).upgradeTo(address(upgradeTester), new bytes(0));
  }

  function testContractUpgrade() public {
    UpgradeTester upgradeTester = new UpgradeTester();

    bytes memory response = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
        IMPLEMENTATION_ID
      )
    );
    assertEq(response.length, 20);
    (address implementation,) = response.asAddressUnchecked(0);

    vm.startPrank(owner);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        UPGRADE_CONTRACT_ID,
        address(upgradeTester)
      )
    );

    UpgradeTester(address(dispatcher)).upgradeTo(implementation, new bytes(0));

    response = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
        IMPLEMENTATION_ID
      )
    );
    assertEq(response.length, 20);
    (address restoredImplementation,) = response.asAddressUnchecked(0);
    assertEq(restoredImplementation, implementation);
  }

  function testExternalContractUpgrade_NotAuthorized() public {
    address fakeAddress = makeAddr("fakeAddress");

    vm.expectRevert(NotAuthorized.selector);
    dispatcher.upgrade(address(fakeAddress), new bytes(0));

    vm.prank(admin);
    vm.expectRevert(NotAuthorized.selector);
    dispatcher.upgrade(address(fakeAddress), new bytes(0));
  }

  function testExternalContractUpgrade_IdempotentUpgrade() public {
    UpgradeTester upgradeTester = new UpgradeTester();

    vm.startPrank(owner);
    dispatcher.upgrade(address(upgradeTester), new bytes(0));

    vm.expectRevert(IdempotentUpgrade.selector);
    UpgradeTester(address(dispatcher)).upgradeTo(address(upgradeTester), new bytes(0));
  }

  function testExternalContractUpgrade() public {
    UpgradeTester upgradeTester = new UpgradeTester();

    bytes memory response = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
        IMPLEMENTATION_ID
      )
    );
    assertEq(response.length, 20);
    (address implementation,) = response.asAddressUnchecked(0);

    vm.startPrank(owner);
    dispatcher.upgrade(address(upgradeTester), new bytes(0));

    UpgradeTester(address(dispatcher)).upgradeTo(implementation, new bytes(0));

    response = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
        IMPLEMENTATION_ID
      )
    );
    assertEq(response.length, 20);
    (address restoredImplementation,) = response.asAddressUnchecked(0);
    assertEq(restoredImplementation, implementation);
  }
}
