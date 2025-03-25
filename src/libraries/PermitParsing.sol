// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.14; //for (bugfixed) support of `using ... global;` syntax for libraries

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

// ╭─────────────────────────────────────────────────────────────────────────╮
// │ Library for decoding ERC2612 Permit and Permit2 signatures and metadata │
// ╰─────────────────────────────────────────────────────────────────────────╯

// # Format
//
// ╭─────────┬─────────────┬───────────────────────────────────────────────────╮
// │  Type   │     Name    │     Description                                   │
// ┝━━━━━━━━━┷━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │       ERC2612 Permit                                                      │
// ├─────────┬─────────────┬───────────────────────────────────────────────────┤
// │ uint256 │ value       │ amount of tokens to approve                       │
// │ uint256 │ deadline    │ unix timestamp until which the signature is valid │
// │ bytes32 │ r           │ ECDSA signature component                         │
// │ bytes32 │ s           │ ECDSA signature component                         │
// │ uint8   │ v           │ ECDSA signature component                         │
// ┝━━━━━━━━━┷━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │       Permit2 Permit                                                      │
// ├─────────┬─────────────┬───────────────────────────────────────────────────┤
// │ uint160 │ amount      │ amount of tokens to approve                       │
// │ uint48  │ expiration  │ unix timestamp until which the approval is valid  │
// │ uint48  │ nonce       │ akin to EVM transaction nonce (must count up)     │
// │ uint256 │ sigDeadline │ timestamp until which the signature is valid      │
// │ bytes   │ signature   │ ECDSA signature (r,s,v packed into 65 bytes)      │
// ┝━━━━━━━━━┷━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │       Permit2 Transfer                                                    │
// ├─────────┬─────────────┬───────────────────────────────────────────────────┤
// │ uint256 │ amount      │ amount of tokens to transfer                      │
// │ uint256 │ nonce       │ akin to EVM transaction nonce (must count up)     │
// │ uint256 │ sigDeadline │ unix timestamp until which the signature is valid │
// │ bytes   │ signature   │ ECDSA signature (r,s,v packed into 65 bytes)      │
// ╰─────────┴─────────────┴───────────────────────────────────────────────────╯
//
// # Library Functions & Naming Conventions
//
// All decode library functions come in 2x2=4 flavors:
//   1. Data-Location:
//     1.1. Calldata (using the Cd tag)
//     1.2. Memory (using the Mem tag)
//   2. Return Value:
//     2.1. individual, stack-based return values (no extra tag)
//     2.2. the associated, memory-allocated Struct (using the Struct tag)
//
// Like in BytesParsing, the Unchecked function name suffix does not refer to
//   Solidity's `unchecked` keyword, but rather to the fact that no bounds checking
//   is performed.
//
// Decoding functions flavorless base names:
//   * decodePermit
//   * decodePermit2Permit
//   * decodePermit2Transfer
//
// Encoding functions (should only be relevant for testing):
//   * encode (overloaded for each struct)
//   * encodePermit
//   * encodePermit2Permit
//   * encodePermit2Transfer

struct Permit {
  uint256 value;
  uint256 deadline;
  bytes32 r;
  bytes32 s;
  uint8   v;
}

struct Permit2Permit {
  uint160 amount;
  uint48  expiration;
  uint48  nonce;
  uint256 sigDeadline;
  bytes   signature;
}

struct Permit2Transfer {
  uint256 amount;
  uint256 nonce;
  uint256 sigDeadline;
  bytes   signature;
}

library PermitParsing {
  using BytesParsing for bytes;
  using {BytesParsing.checkLength} for uint;

  error InvalidSignatureLength(uint length);

  uint internal constant SIGNATURE_SIZE = 65;
  uint internal constant PERMIT_SIZE = 32 + 32 + SIGNATURE_SIZE;
  uint internal constant PERMIT2_PERMIT_SIZE = 20 + 6 + 6 + 32 + SIGNATURE_SIZE;
  uint internal constant PERMIT2_TRANSFER_SIZE = 32 + 32 + 32 + SIGNATURE_SIZE;

  // ERC2612 Permit

  function decodePermitCd(
    bytes calldata params
  ) internal pure returns (
    uint256 value,
    uint256 deadline,
    bytes32 r,
    bytes32 s,
    uint8   v
  ) {
    uint offset = 0;
    (value, deadline, r, s, v, offset) = decodePermitCdUnchecked(params, offset);
    params.length.checkLength(offset);
  }

  function decodePermitStructCd(
    bytes calldata params
  ) internal pure returns (Permit memory permit) {
    ( permit.value,
      permit.deadline,
      permit.r,
      permit.s,
      permit.v
    ) = decodePermitCd(params);
  }

  function decodePermitCdUnchecked(
    bytes calldata params,
    uint offset
  ) internal pure returns (
    uint256 value,
    uint256 deadline,
    bytes32 r,
    bytes32 s,
    uint8 v,
    uint newOffset
  ) {
    (value,    offset) = params.asUint256CdUnchecked(offset);
    (deadline, offset) = params.asUint256CdUnchecked(offset);
    (r,        offset) = params.asBytes32CdUnchecked(offset);
    (s,        offset) = params.asBytes32CdUnchecked(offset);
    (v,        offset) = params.asUint8CdUnchecked(offset);
    newOffset = offset;
  }

  function decodePermitCdStructUnchecked(
    bytes calldata params,
    uint offset
  ) internal pure returns (Permit memory permit, uint newOffset) {
    ( permit.value,
      permit.deadline,
      permit.r,
      permit.s,
      permit.v,
      newOffset
    ) = decodePermitCdUnchecked(params, offset);
  }

  function decodePermitMem(
    bytes memory params
  ) internal pure returns (
    uint256 value,
    uint256 deadline,
    bytes32 r,
    bytes32 s,
    uint8   v
  ) {
    uint offset = 0;
    (value, deadline, r, s, v, offset) = decodePermitMemUnchecked(params, offset);
    params.length.checkLength(offset);
  }

  function decodePermitStructMem(
    bytes memory params
  ) internal pure returns (Permit memory permit) {
    ( permit.value,
      permit.deadline,
      permit.r,
      permit.s,
      permit.v
    ) = decodePermitMem(params);
  }

  function decodePermitMemUnchecked(
    bytes memory params,
    uint offset
  ) internal pure returns (
    uint256 value,
    uint256 deadline,
    bytes32 r,
    bytes32 s,
    uint8   v,
    uint newOffset
  ) {
    (value,    offset) = params.asUint256MemUnchecked(offset);
    (deadline, offset) = params.asUint256MemUnchecked(offset);
    (r,        offset) = params.asBytes32MemUnchecked(offset);
    (s,        offset) = params.asBytes32MemUnchecked(offset);
    (v,        offset) = params.asUint8MemUnchecked(offset);
    newOffset = offset;
  }

  function decodePermitMemStructUnchecked(
    bytes memory params,
    uint offset
  ) internal pure returns (Permit memory permit, uint newOffset) {
    ( permit.value,
      permit.deadline,
      permit.r,
      permit.s,
      permit.v,
      newOffset
    ) = decodePermitMemUnchecked(params, offset);
  }

  // Permit2 Permit

  function decodePermit2PermitCd(
    bytes calldata params
  ) internal pure returns (
    uint160 amount,
    uint48  expiration,
    uint48  nonce,
    uint256 sigDeadline,
    bytes calldata signature
  ) {
    uint offset = 0;
    (amount, expiration, nonce, sigDeadline, signature, offset) =
      decodePermit2PermitCdUnchecked(params, offset);
    params.length.checkLength(offset);
  }

  function decodePermit2PermitStructCd(
    bytes calldata params
  ) internal pure returns (Permit2Permit memory permit) {
    ( permit.amount,
      permit.expiration,
      permit.nonce,
      permit.sigDeadline,
      permit.signature
    ) = decodePermit2PermitCd(params);
  }

  function decodePermit2PermitCdUnchecked(
    bytes calldata params,
    uint offset
  ) internal pure returns (
    uint160 amount,
    uint48  expiration,
    uint48  nonce,
    uint256 sigDeadline,
    bytes calldata signature,
    uint    newOffset
  ) {
    (amount,      offset) = params.asUint160CdUnchecked(offset);
    (expiration,  offset) = params.asUint48CdUnchecked(offset);
    (nonce,       offset) = params.asUint48CdUnchecked(offset);
    (sigDeadline, offset) = params.asUint256CdUnchecked(offset);
    (signature,   offset) = params.sliceCdUnchecked(offset, SIGNATURE_SIZE);
    newOffset = offset;
  }

  function decodePermit2PermitCdStructUnchecked(
    bytes calldata params,
    uint offset
  ) internal pure returns (Permit2Permit memory permit, uint newOffset) {
    ( permit.amount,
      permit.expiration,
      permit.nonce,
      permit.sigDeadline,
      permit.signature,
      newOffset
    ) = decodePermit2PermitCdUnchecked(params, offset);
  }

  function decodePermit2PermitMem(
    bytes memory params
  ) internal pure returns (
    uint160 amount,
    uint48  expiration,
    uint48  nonce,
    uint256 sigDeadline,
    bytes memory signature
  ) {
    uint offset = 0;
    (amount, expiration, nonce, sigDeadline, signature, offset) =
      decodePermit2PermitMemUnchecked(params, offset);
    params.length.checkLength(offset);
  }

  function decodePermit2PermitStructMem(
    bytes memory params
  ) internal pure returns (Permit2Permit memory permit) {
    ( permit.amount,
      permit.expiration,
      permit.nonce,
      permit.sigDeadline,
      permit.signature
    ) = decodePermit2PermitMem(params);
  }

  function decodePermit2PermitMemUnchecked(
    bytes memory params,
    uint offset
  ) internal pure returns (
    uint160 amount,
    uint48  expiration,
    uint48  nonce,
    uint256 sigDeadline,
    bytes memory signature,
    uint    newOffset
  ) {
    (amount,      offset) = params.asUint160MemUnchecked(offset);
    (expiration,  offset) = params.asUint48MemUnchecked(offset);
    (nonce,       offset) = params.asUint48MemUnchecked(offset);
    (sigDeadline, offset) = params.asUint256MemUnchecked(offset);
    (signature,   offset) = params.sliceMemUnchecked(offset, SIGNATURE_SIZE);
    newOffset = offset;
  }

  function decodePermit2PermitMemStructUnchecked(
    bytes memory params,
    uint offset
  ) internal pure returns (Permit2Permit memory permit, uint newOffset) {
    ( permit.amount,
      permit.expiration,
      permit.nonce,
      permit.sigDeadline,
      permit.signature,
      newOffset
    ) = decodePermit2PermitMemUnchecked(params, offset);
  }

  // Permit2 Transfer

  function decodePermit2TransferCd(
    bytes calldata params
  ) internal pure returns (
    uint256 amount,
    uint256 nonce,
    uint256 sigDeadline,
    bytes memory signature
  ) {
    uint offset = 0;
    (amount, nonce, sigDeadline, signature, offset) =
      decodePermit2TransferCdUnchecked(params, offset);
    params.length.checkLength(offset);
  }

  function decodePermit2TransferStructCd(
    bytes calldata params
  ) internal pure returns (Permit2Transfer memory transfer) {
    ( transfer.amount,
      transfer.nonce,
      transfer.sigDeadline,
      transfer.signature
    ) = decodePermit2TransferCd(params);
  }

  function decodePermit2TransferCdUnchecked(
    bytes calldata params,
    uint offset
  ) internal pure returns (
    uint256 amount,
    uint256 nonce,
    uint256 sigDeadline,
    bytes memory signature,
    uint    newOffset
  ) {
    (amount,      offset) = params.asUint256CdUnchecked(offset);
    (nonce,       offset) = params.asUint256CdUnchecked(offset);
    (sigDeadline, offset) = params.asUint256CdUnchecked(offset);
    (signature,   offset) = params.sliceCdUnchecked(offset, SIGNATURE_SIZE);
    newOffset = offset;
  }

  function decodePermit2TransferCdStructUnchecked(
    bytes calldata params,
    uint offset
  ) internal pure returns (Permit2Transfer memory transfer, uint newOffset) {
    ( transfer.amount,
      transfer.nonce,
      transfer.sigDeadline,
      transfer.signature,
      newOffset
    ) = decodePermit2TransferCdUnchecked(params, offset);
  }

  function decodePermit2TransferMem(
    bytes memory params
  ) internal pure returns (
    uint256 amount,
    uint256 nonce,
    uint256 sigDeadline,
    bytes memory signature
  ) {
    (amount, nonce, sigDeadline, signature, ) =
      decodePermit2TransferMemUnchecked(params, 0);
  }

  function decodePermit2TransferStructMem(
    bytes memory params
  ) internal pure returns (Permit2Transfer memory transfer) {
    ( transfer.amount,
      transfer.nonce,
      transfer.sigDeadline,
      transfer.signature
    ) = decodePermit2TransferMem(params);
  }

  function decodePermit2TransferMemUnchecked(
    bytes memory params,
    uint offset
  ) internal pure returns (
    uint256 amount,
    uint256 nonce,
    uint256 sigDeadline,
    bytes memory signature,
    uint newOffset
  ) {
    (amount,      offset) = params.asUint256MemUnchecked(offset);
    (nonce,       offset) = params.asUint256MemUnchecked(offset);
    (sigDeadline, offset) = params.asUint256MemUnchecked(offset);
    (signature,   offset) = params.sliceMemUnchecked(offset, SIGNATURE_SIZE);
    newOffset = offset;
  }

  function decodePermit2TransferMemStructUnchecked(
    bytes memory params,
    uint offset
  ) internal pure returns (Permit2Transfer memory transfer, uint newOffset) {
    ( transfer.amount,
      transfer.nonce,
      transfer.sigDeadline,
      transfer.signature,
      newOffset
    ) = decodePermit2TransferMemUnchecked(params, offset);
  }

  // ------------ Encoding ------------

  function encodePermit(
    uint256 value,
    uint256 deadline,
    bytes32 r,
    bytes32 s,
    uint8   v
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(value, deadline, r, s, v);
  }

  function encode(Permit memory permit) internal pure returns (bytes memory) {
    return encodePermit(permit.value, permit.deadline, permit.r, permit.s, permit.v);
  }

  function encodePermit2Permit(
    uint160 amount,
    uint48  expiration,
    uint48  nonce,
    uint256 sigDeadline,
    bytes memory signature
  ) internal pure returns (bytes memory) {
    if (signature.length != SIGNATURE_SIZE)
      revert InvalidSignatureLength(signature.length);

    return abi.encodePacked(amount, expiration, nonce, sigDeadline, signature);
  }

  function encode(Permit2Permit memory permit) internal pure returns (bytes memory) {
    return encodePermit2Permit(
      permit.amount,
      permit.expiration,
      permit.nonce,
      permit.sigDeadline,
      permit.signature
    );
  }

  function encodePermit2Transfer(
    uint256 amount,
    uint256 nonce,
    uint256 sigDeadline,
    bytes memory signature
  ) internal pure returns (bytes memory) {
    if (signature.length != SIGNATURE_SIZE)
      revert InvalidSignatureLength(signature.length);

    return abi.encodePacked(amount, nonce, sigDeadline, signature);
  }

  function encode(Permit2Transfer memory transfer) internal pure returns (bytes memory) {
    return encodePermit2Transfer(
      transfer.amount,
      transfer.nonce,
      transfer.sigDeadline,
      transfer.signature
    );
  }
}

using PermitParsing for Permit global;
using PermitParsing for Permit2Permit global;
using PermitParsing for Permit2Transfer global;
