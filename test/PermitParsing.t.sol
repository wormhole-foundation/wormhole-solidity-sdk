// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {PermitParsing} from "wormhole-sdk/libraries/PermitParsing.sol";

contract PermitParsingTest is Test {
  using BytesParsing for bytes;

  function decodePermit(
    bytes calldata params,
    uint offset
  ) external pure returns (uint256, uint256, bytes32, bytes32, uint8, uint) {
    return PermitParsing.decodePermitCdUnchecked(params, offset);
  }

  function decodePermit2Permit(
    bytes calldata params,
    uint offset
  ) external pure returns (uint160, uint48, uint48, uint256, bytes memory, uint) {
    return PermitParsing.decodePermit2PermitCdUnchecked(params, offset);
  }

  function decodePermit2Transfer(
    bytes calldata params,
    uint offset
  ) external pure returns (uint256, uint256, uint256, bytes memory, uint) {
    return PermitParsing.decodePermit2TransferCdUnchecked(params, offset);
  }

  function testParsePermit(
    uint256 value,
    uint256 deadline,
    bytes32 r,
    bytes32 s,
    uint8 v
  ) public {
    bytes memory params = abi.encodePacked(value, deadline, r, s, v);

    (
      uint256 _value,
      uint256 _deadline,
      bytes32 _r,
      bytes32 _s,
      uint8 _v,
      uint offset
    ) = PermitParsing.decodePermitMemUnchecked(params, 0);
    assertEq(_value, value);
    assertEq(_deadline, deadline);
    assertEq(_r, r);
    assertEq(_s, s);
    assertEq(_v, v);
    assertEq(offset, params.length);

    (
      _value,
      _deadline,
      _r,
      _s,
      _v,
      offset
    ) = this.decodePermit(params, 0);
    assertEq(_value, value);
    assertEq(_deadline, deadline);
    assertEq(_r, r);
    assertEq(_s, s);
    assertEq(_v, v);
    assertEq(offset, params.length);
  }

  function testParsePermit2Permit(
    uint160 amount,
    uint48 expiration,
    uint48 nonce,
    uint256 sigDeadline,
    bytes memory signature
  ) public {
    vm.assume(signature.length == 65);
    bytes memory params = abi.encodePacked(amount, expiration, nonce, sigDeadline, signature);

    (
      uint160 _amount,
      uint48 _expiration,
      uint48 _nonce,
      uint256 _sigDeadline,
      bytes memory _signature,
      uint offset
    ) = PermitParsing.decodePermit2PermitMemUnchecked(params, 0);
    assertEq(_amount, amount);
    assertEq(_expiration, expiration);
    assertEq(_nonce, nonce);
    assertEq(_sigDeadline, sigDeadline);
    assertEq(_signature, signature);
    assertEq(offset, params.length);


    (
      _amount,
      _expiration,
      _nonce,
      _sigDeadline,
      _signature,
      offset
    ) = this.decodePermit2Permit(params, 0);
    assertEq(_amount, amount);
    assertEq(_expiration, expiration);
    assertEq(_nonce, nonce);
    assertEq(_sigDeadline, sigDeadline);
    assertEq(_signature, signature);
    assertEq(offset, params.length);
  }

  function testParsePermit2Transfer(
    uint256 amount,
    uint256 nonce,
    uint256 sigDeadline,
    bytes memory signature
  ) public {
    vm.assume(signature.length == 65);
    bytes memory params = abi.encodePacked(amount, nonce, sigDeadline, signature);

    (
      uint256 _amount,
      uint256 _nonce,
      uint256 _sigDeadline,
      bytes memory _signature,
      uint offset
    ) = PermitParsing.decodePermit2TransferMemUnchecked(params, 0);
    assertEq(_amount, amount);
    assertEq(_nonce, nonce);
    assertEq(_sigDeadline, sigDeadline);
    assertEq(_signature, signature);
    assertEq(offset, params.length);

    (
      _amount,
      _nonce,
      _sigDeadline,
      _signature,
      offset
    ) = this.decodePermit2Transfer(params, 0);
    assertEq(_amount, amount);
    assertEq(_nonce, nonce);
    assertEq(_sigDeadline, sigDeadline);
    assertEq(_signature, signature);
    assertEq(offset, params.length);
  }
}