// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {ProxyBase} from "wormhole-sdk/proxy/ProxyBase.sol";
import {Role, senderRole, failAuthIf} from "wormhole-sdk/components/dispatcher/AccessControl.sol";
import {UPGRADE_CONTRACT_ID, IMPLEMENTATION_ID} from "wormhole-sdk/components/dispatcher/Ids.sol";

error InvalidGovernanceCommand(uint8 command);
error InvalidGovernanceQuery(uint8 query);

abstract contract Upgrade is ProxyBase {
  using BytesParsing for bytes;

  function dispatchExecUpgrade(
    bytes calldata data,
    uint offset,
    uint8 command
  ) internal returns (bool, uint) {
    return (command == UPGRADE_CONTRACT_ID)
      ? (true, _upgradeContract(data, offset))
      : (false, offset);
  }

  function dispatchQueryUpgrade(
    bytes calldata,
    uint offset,
    uint8 query
  ) view internal returns (bool, bytes memory, uint) {
    return query == IMPLEMENTATION_ID
      ? (true, abi.encodePacked(_getImplementation()), offset)
      : (false, new bytes(0), offset);
  }

  function upgrade(address implementation, bytes calldata data) external {
    failAuthIf(senderRole() != Role.Owner);

    _upgradeTo(implementation, data);
  }

  function _upgradeContract(
    bytes calldata commands,
    uint offset
  ) internal returns (uint) {
    failAuthIf(senderRole() != Role.Owner);

    address newImplementation;
    (newImplementation, offset) = commands.asAddressCdUnchecked(offset);
    //contract upgrades must be the last command in the batch
    commands.checkLengthCd(offset);

    _upgradeTo(newImplementation, new bytes(0));

    return offset;
  }
}
