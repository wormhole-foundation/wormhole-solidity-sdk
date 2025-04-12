// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing}  from "wormhole-sdk/libraries/BytesParsing.sol";
import {RawDispatcher} from "wormhole-sdk/RawDispatcher.sol";
import {AccessControl} from "wormhole-sdk/components/dispatcher/AccessControl.sol";
import {SweepTokens}   from "wormhole-sdk/components/dispatcher/SweepTokens.sol";
import {Upgrade}       from "wormhole-sdk/components/dispatcher/Upgrade.sol";

contract Dispatcher is RawDispatcher, AccessControl, SweepTokens, Upgrade {
  using BytesParsing for bytes;

  function _proxyConstructor(bytes calldata args) internal override {
    uint offset = 0;

    address owner;
    (owner, offset) = args.asAddressCdUnchecked(offset);

    uint8 adminCount;
    (adminCount, offset) = args.asUint8CdUnchecked(offset);
    address[] memory admins = new address[](adminCount);
    for (uint i = 0; i < adminCount; ++i) {
      (admins[i], offset) = args.asAddressCdUnchecked(offset);
    }

    BytesParsing.checkLength(offset, args.length);

    _accessControlConstruction(owner, admins);
  }

  function _exec(bytes calldata data) internal override returns (bytes memory) { unchecked {
    uint offset = 0;

    while (offset < data.length) {
      uint8 command;
      (command, offset) = data.asUint8CdUnchecked(offset);

      bool dispatched;
      (dispatched, offset) = dispatchExecAccessControl(data, offset, command);
      if (!dispatched)
        (dispatched, offset) = dispatchExecUpgrade(data, offset, command);
      if (!dispatched)
        (dispatched, offset) = dispatchExecSweepTokens(data, offset, command);
    }

    BytesParsing.checkLength(offset, data.length);
    return new bytes(0);
  }}

  function _get(bytes calldata data) internal view override returns (bytes memory) { unchecked {
    bytes memory ret;
    uint offset = 0;

    while (offset < data.length) {
      uint8 query;
      (query, offset) = data.asUint8CdUnchecked(offset);

      bytes memory result;
      bool dispatched;
      (dispatched, result, offset) = dispatchQueryAccessControl(data, offset, query);
      if (!dispatched)
        (dispatched, result, offset) = dispatchQueryUpgrade(data, offset, query);

      ret = abi.encodePacked(ret, result);
    }

    BytesParsing.checkLength(offset, data.length);
    return ret;
  }}
}