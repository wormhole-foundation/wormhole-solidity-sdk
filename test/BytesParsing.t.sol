// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { BytesParsing } from "wormhole-sdk/libraries/BytesParsing.sol";

contract TestBytesParsing is Test {
  using BytesParsing for bytes;

  function testBytesParsing() public {
  }
}