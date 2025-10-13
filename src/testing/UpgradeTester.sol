// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ProxyBase} from "wormhole-sdk/proxy/ProxyBase.sol";

contract UpgradeTester is ProxyBase {
  event Constructed(bytes data);
  event Upgraded(bytes data);

  function upgradeTo(address newImplementation, bytes calldata data) external {
    _upgradeTo(newImplementation, data);
  }

  function getImplementation() external view returns (address) {
    return _getImplementation();
  }

  function _proxyConstructor(bytes calldata data) internal override {
    emit Constructed(data);
  }

  function _contractUpgrade(bytes calldata data) internal override {
    emit Upgraded(data);
  }
}
