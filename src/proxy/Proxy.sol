// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

import { implementationState } from "./Eip1967Implementation.sol";

//slimmed down, more opinionated implementation of the EIP1967 reference implementation
//  see: https://eips.ethereum.org/EIPS/eip-1967
contract Proxy {
  error ProxyConstructionFailed(bytes revertData);

  constructor(address logic, bytes memory data) payable {
    implementationState().implementation = logic;

    //We can't externally call ourselves and use msg.sender to prevent unauhorized execution of
    //  the construction code, because the proxy's code only gets written to state when the
    //  deployment transaction completes (and returns the deployed bytecode via CODECOPY).
    //So we only have delegatecall at our disposal and instead use an initialized flag (stored in
    //  the same storage slot as the implementation address) to prevent invalid re-initialization.
    (bool success, bytes memory revertData) =
      logic.delegatecall(abi.encodeWithSignature("checkedUpgrade(bytes)", (data)));

    if (!success)
      revert ProxyConstructionFailed(revertData);
  }

  fallback() external payable {
    //can't just do a naked sload of the implementation slot here because it also contains
    //  the initialized flag!
    address implementation = implementationState().implementation;
    assembly {
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
    }
  }
}