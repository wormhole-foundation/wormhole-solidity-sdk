// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

import { implementationState } from "./Eip1967Implementation.sol";

error InvalidSender();
error IdempotentUpgrade();
error InvalidMsgValue();
error InvalidData();
error UpgradeFailed(bytes revertData);

event Upgraded(address indexed implementation);

//works with both standard EIP1967 proxies and our own, slimmed down Proxy contract
abstract contract ProxyBase {
  //address private immutable _logicContract = address(this);

  //payable for proxyConstructor use case
  //selector: f4189c473
  function checkedUpgrade(bytes calldata data) payable external {
    if (msg.sender != address(this)) {
      if (implementationState().initialized)
        revert InvalidSender();

      _proxyConstructor(data);
    }
    else
      _contractUpgrade(data);

    //If we upgrade from an old OpenZeppelin proxy, then initialized will not have been set to true
    //  even though the constructor has been called, so we simply manually set it here in all cases.
    //This is slightly gas inefficient but better to be safe than sorry for rare use cases like
    //  contract upgrades.
    implementationState().initialized = true;
  }

  //msg.value should be enforced/checked before calling _upgradeTo
  function _upgradeTo(address newImplementation, bytes memory data) internal {
    if (newImplementation == implementationState().implementation)
      revert IdempotentUpgrade();

    implementationState().implementation = newImplementation;

    (bool success, bytes memory revertData) =
      address(this).call(abi.encodeCall(this.checkedUpgrade, (data)));

    if (!success)
      revert UpgradeFailed(revertData);

    emit Upgraded(newImplementation);
  }

  function _getImplementation() internal view returns (address) {
    return implementationState().implementation;
  }

  function _proxyConstructor(bytes calldata data) internal virtual {
    if (msg.value > 0)
      revert InvalidMsgValue();

    _noDataAllowed(data);

    //!!don't forget to check/enforce msg.value when overriding!!
  }

  function _contractUpgrade(bytes calldata data) internal virtual {
    _noDataAllowed(data);

    //override and implement in the new logic contract (if required)
  }

  function _noDataAllowed(bytes calldata data) internal pure {
    if (data.length > 0)
      revert InvalidData();
  }
}