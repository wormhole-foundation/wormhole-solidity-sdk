// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

library Permit2Parsing {
  using BytesParsing for bytes;

  uint constant SIGNATURE_SIZE = 65;

  function _parsePermit(
    bytes calldata params,
    uint offset
  ) internal pure returns (uint256, uint256, bytes32, bytes32, uint8, uint) {
    uint256 value;
    uint256 deadline;
    bytes32 r;
    bytes32 s;
    uint8 v;
    (value,    offset) = params.asUint256CdUnchecked(offset);
    (deadline, offset) = params.asUint256CdUnchecked(offset);
    (r,        offset) = params.asBytes32CdUnchecked(offset);
    (s,        offset) = params.asBytes32CdUnchecked(offset);
    (v,        offset) = params.asUint8CdUnchecked(offset);
    return (value, deadline, r, s, v, offset);
  }

  function _parsePermit2Permit(
    bytes calldata params,
    uint offset
  ) internal pure returns (uint160, uint48, uint48, uint256, bytes memory, uint) {
    uint160 amount;
    uint48 expiration;
    uint48 nonce;
    uint256 sigDeadline;
    bytes memory signature;
    (amount,      offset) = params.asUint160CdUnchecked(offset);
    (expiration,  offset) = params.asUint48CdUnchecked(offset);
    (nonce,       offset) = params.asUint48CdUnchecked(offset);
    (sigDeadline, offset) = params.asUint256CdUnchecked(offset);
    (signature,   offset) = params.sliceCdUnchecked(offset, SIGNATURE_SIZE);
    return (amount, expiration, nonce, sigDeadline, signature, offset);
  }

  function _parsePermit2Transfer(
    bytes calldata params,
    uint offset
  ) internal pure returns (uint256, uint256, uint256, bytes memory, uint) {
    uint256 amount;
    uint256 nonce;
    uint256 sigDeadline;
    bytes memory signature;
    (amount,      offset) = params.asUint256CdUnchecked(offset);
    (nonce,       offset) = params.asUint256CdUnchecked(offset);
    (sigDeadline, offset) = params.asUint256CdUnchecked(offset);
    (signature,   offset) = params.sliceCdUnchecked(offset, SIGNATURE_SIZE);
    return (amount, nonce, sigDeadline, signature, offset);
  }
}