// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {adminState} from "wormhole-sdk/proxy/Eip1967Admin.sol";
import {
  ProxyBase,
  UpgradeFailed,
  InvalidData,
  InvalidImplementation
} from "wormhole-sdk/proxy/ProxyBase.sol";
import {Proxy, ProxyConstructionFailed} from "wormhole-sdk/proxy/Proxy.sol";

error NotAuthorized();
error NoValueAllowed();

contract LogicContractV1 is ProxyBase {
  uint256 public immutable immutableNum;
  string public message;

  constructor(uint256 num) {
    immutableNum = num;
  }

  function _proxyConstructor(bytes calldata data) internal override {
    if (msg.value != 0)
      revert NoValueAllowed();

    adminState().admin = msg.sender;
    message = abi.decode(data, (string));
  }

  function getImplementation() external view returns (address) {
    return _getImplementation();
  }

  function customUpgradeFun(address newImplementation, bytes calldata data) external {
    if (msg.sender != adminState().admin)
      revert NotAuthorized();

    _upgradeTo(newImplementation, data);
  }
}

contract LogicContractV2 is LogicContractV1 {
  constructor(uint256 num) LogicContractV1(num) {}

  function _contractUpgrade(bytes calldata data) internal override {
    message = abi.decode(data, (string));
  }
}

contract TestProxy is Test {
  function testProxyUpgrade() public {
    address admin = makeAddr("admin");
    address rando = makeAddr("rando");

    address logic1 = address(new LogicContractV1(1));
    address logic2 = address(new LogicContractV2(2));

    startHoax(admin);
    //no value allowed
    vm.expectRevert(abi.encodeWithSelector(
      ProxyConstructionFailed.selector,
      abi.encodePacked(bytes4(NoValueAllowed.selector))
    ));
    new Proxy{value: 1 ether}(logic1, abi.encode("v1"));

    //deploy
    LogicContractV1 contrct = LogicContractV1(address(new Proxy(logic1, abi.encode("v1"))));

    assertEq(contrct.getImplementation(), logic1);
    assertEq(contrct.immutableNum(), 1);
    assertEq(contrct.message(), "v1");

    startHoax(rando);
    //unauthorized upgrade
    vm.expectRevert(NotAuthorized.selector);
    contrct.customUpgradeFun(logic2, abi.encode("v2"));

    startHoax(admin);
    //upgrade
    contrct.customUpgradeFun(logic2, abi.encode("v2"));

    assertEq(contrct.getImplementation(), logic2);
    assertEq(contrct.immutableNum(), 2);
    assertEq(contrct.message(), "v2");

    startHoax(rando);
    //unauthorized downgrade
    vm.expectRevert(NotAuthorized.selector);
    contrct.customUpgradeFun(logic1, new bytes(0));

    startHoax(admin);
    //v1 uses default _contractUpgrade implementation which reverts on any data
    vm.expectRevert(abi.encodeWithSelector(
      UpgradeFailed.selector,
      abi.encodePacked(bytes4(InvalidData.selector))
    ));
    contrct.customUpgradeFun(logic1, abi.encode("downgrade"));

    //questionable, but possible downgrade:
    contrct.customUpgradeFun(logic1, new bytes(0));

    //highlight hazards of questionable downgrade:
    assertEq(contrct.getImplementation(), logic1);
    assertEq(contrct.immutableNum(), 1);
    assertEq(contrct.message(), "v2");
  }

  function testProxyInvalidUpgradeFails() public {
    address logic1 = address(new LogicContractV1(1));
    LogicContractV1 contrct = LogicContractV1(address(new Proxy(logic1, abi.encode("v1"))));

    vm.expectRevert(InvalidImplementation.selector);
    contrct.customUpgradeFun(makeAddr("wrongAddress"), abi.encode("oops"));
  }
}
