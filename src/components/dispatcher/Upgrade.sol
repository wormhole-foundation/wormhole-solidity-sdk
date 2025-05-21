// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing} from "../../libraries/BytesParsing.sol";
import {ProxyBase} from "../../proxy/ProxyBase.sol";
import {Role, senderRole, failAuthIf} from "./AccessControl.sol";
import {UPGRADE_CONTRACT_ID, IMPLEMENTATION_ID} from "./Ids.sol";

error InvalidGovernanceCommand(uint8 command);
error InvalidGovernanceQuery(uint8 query);

abstract contract Upgrade is ProxyBase {
  using BytesParsing for bytes;

  // ------ external ------

  //selector: c987336c
  function upgrade(address implementation, bytes calldata data) external {
    failAuthIf(senderRole() != Role.Owner);

    _upgradeTo(implementation, data);
  }

  // ------ internal ------

  /**
   * Dispatch an execute function. Execute functions almost always modify contract state.
   */
  function dispatchExecUpgrade(
    bytes calldata data,
    uint offset,
    uint8 command
  ) internal returns (bool, uint) {
    return (command == UPGRADE_CONTRACT_ID)
      ? (true, _upgradeContract(data, offset))
      : (false, offset);
  }

  /**
   * Dispatch a query function. Query functions never modify contract state.
   */
  function dispatchQueryUpgrade(
    bytes calldata,
    uint offset,
    uint8 query
  ) view internal returns (bool, bytes memory, uint) {
    return query == IMPLEMENTATION_ID
      ? (true, abi.encodePacked(_getImplementation()), offset)
      : (false, new bytes(0), offset);
  }

  function _upgradeContract(
    bytes calldata commands,
    uint offset
  ) internal returns (uint) {
    failAuthIf(senderRole() != Role.Owner);

    address newImplementation;
    (newImplementation, offset) = commands.asAddressCdUnchecked(offset);
    bytes calldata data;
    (data, offset) = commands.sliceCdUnchecked(offset, commands.length - offset);

    //contract upgrades must be the last command in the batch
    BytesParsing.checkLength(offset, commands.length);

    _upgradeTo(newImplementation, data);

    return offset;
  }
}
