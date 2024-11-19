// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {Proxy}        from "wormhole-sdk/proxy/Proxy.sol";
import {reRevert}     from "wormhole-sdk/Utils.sol";
import {Dispatcher}   from "./Dispatcher.sol";

contract DispatcherTestBase is Test {
  using BytesParsing for bytes;

  address immutable owner;
  address immutable admin;

  address    dispatcherImplementation;
  Dispatcher dispatcher;

  constructor() {
    owner = makeAddr("owner");
    admin = makeAddr("admin");
  }

  function _setUp1() internal virtual { }

  function setUp() public {
    uint8 adminCount = 1;
    
    dispatcherImplementation = address(new Dispatcher());
    dispatcher = Dispatcher(address(new Proxy(
        dispatcherImplementation, 
        abi.encodePacked(
          owner,
          adminCount,
          admin
        )
    )));

    _setUp1();
  }

  function invokeStaticDispatcher(bytes memory encoded) view internal returns (bytes memory data) {
    (bool success, bytes memory result) = address(dispatcher).staticcall(encoded);
    return decodeBytesResult(success, result);
  }

  function invokeDispatcher(bytes memory encoded) internal returns (bytes memory data) {
    return invokeDispatcher(encoded, 0);
  }

  function invokeDispatcher(bytes memory encoded, uint value) internal returns (bytes memory data) {
    (bool success, bytes memory result) = address(dispatcher).call{value: value}(encoded);
    return decodeBytesResult(success, result);
  }

  function decodeBytesResult(bool success, bytes memory result) pure private returns (bytes memory data) {
    if (!success) {
      reRevert(result);
    }
    data = abi.decode(result, (bytes));
  }
}