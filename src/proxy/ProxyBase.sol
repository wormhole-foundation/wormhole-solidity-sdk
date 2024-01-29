// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

import { implementationState } from "./Eip1967Implementation.sol";

error InvalidSender();
error IdempotentUpgrade();
error UpgradeFailed(bytes revertData);

event Upgraded(address indexed implementation);

//works with both standard EIP1967 proxies and our own, slimmed down Proxy contract
abstract contract ProxyBase {
  //address private immutable _logicContract = address(this);

  //deliberately not payable since the contract would only be sending funds to itself
  //selector: f4189c473
  function checkedUpgrade(bytes calldata data) external {
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

  function _proxyConstructor(bytes calldata) internal virtual {
    //!!don't forget to check/enforce msg.value!!
    //also can't externally call our own contract here
  }

  function _contractUpgrade(bytes calldata) internal virtual {
    //override and implement in the new logic contract (if required)
  }
}