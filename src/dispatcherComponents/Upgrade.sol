// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {ProxyBase} from "wormhole-sdk/proxy/ProxyBase.sol";
import {
  accessControlState,
  AccessControlState,
  NotAuthorized,
  senderHasAuth,
  Role
} from "./AccessControl.sol";
import "./ids.sol";

error InvalidGovernanceCommand(uint8 command);
error InvalidGovernanceQuery(uint8 query);

abstract contract Upgrade is ProxyBase {
  using BytesParsing for bytes;

  /**
   * Dispatch an execute function. Execute functions almost always modify contract state.
   */
  function dispatchExecUpgrade(bytes calldata data, uint256 offset, uint8 command) internal returns (bool, uint256) {
    if (command == UPGRADE_CONTRACT_ID)
      offset = _upgradeContract(data, offset);
    else return (false, offset);

    return (true, offset);
  }

  /**
   * Dispatch a query function. Query functions never modify contract state.
   */
  function dispatchQueryUpgrade(bytes calldata, uint256 offset, uint8 query) view internal returns (bool, bytes memory, uint256) {
    bytes memory result;
    if (query == IMPLEMENTATION_ID)
      result = abi.encodePacked(_getImplementation());
    else return (false, new bytes(0), offset);

    return (true, result, offset);
  }

  function upgrade(address implementation, bytes calldata data) external {
    if (senderHasAuth() != Role.Owner)
      revert NotAuthorized();
    
    _upgradeTo(implementation, data);
  }

  function _upgradeContract(
    bytes calldata commands,
    uint offset
  ) internal returns (uint) {
    if (senderHasAuth() != Role.Owner)
      revert NotAuthorized();

    address newImplementation;
    (newImplementation, offset) = commands.asAddressCdUnchecked(offset);
    //contract upgrades must be the last command in the batch
    commands.checkLengthCd(offset);

    _upgradeTo(newImplementation, new bytes(0));

    return offset;
  }
}
