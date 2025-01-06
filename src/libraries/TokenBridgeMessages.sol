// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {WORD_SIZE} from "wormhole-sdk/constants/Common.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

// ╭─────────────────────────────────────────────────────────────╮
// │ Library for encoding and decoding Wormhole TokenBridge VAAs │
// ╰─────────────────────────────────────────────────────────────╯

// # Payload Formats
//
// see:
//   * [TokenBridge](https://github.com/wormhole-foundation/wormhole/blob/1dbe8459b96e182932d0dd5ae4b6bbce6f48cb09/ethereum/contracts/bridge/Bridge.sol#L595-L629)
//   * [Typescript SDK](https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/definitions/src/protocols/tokenBridge/tokenBridgeLayout.ts)
//
// ╭────────────┬──────────────────┬────────────────────────────────────────────────────────╮
// │    Type    │       Name       │     Description                                        │
// ┝━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │       CommonTransferHeader (shared by Transfer and TransferWithPayload)                │
// ├────────────┬──────────────────┬────────────────────────────────────────────────────────┤
// │  uint8     │ payloadId        │ either 1 or 3 (see PAYLOAD_ID constants below)         │
// │  uint256   │ normalizedAmount │ amount of transferred tokens truncated to 8 decimals   │
// │  bytes32   │ tokenAddress     │ address of the token on the origin chain               │
// │  uint16    │ tokenChainId     │ Wormhole chain id of the token's origin chain          │
// │  bytes32   │ toAddress        │ address of the recipient on the destination chain      │
// │  uint16    │ toChainId        │ Wormhole chain id of the destination chain             │
// ┝━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │        Transfer                                                                        │
// ├────────────────────────────────────────────────────────────────────────────────────────┤
// │  CommonTransferHeader                                                                  │
// ├╌╌╌╌╌╌╌╌╌╌╌╌┬╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┬╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
// │  uint256   │ fee              │ ignored/unused legacy field, should always be 0        │
// ┝━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │        TransferWithPayload                                                             │
// ├────────────────────────────────────────────────────────────────────────────────────────┤
// │  CommonTransferHeader                                                                  │
// ├╌╌╌╌╌╌╌╌╌╌╌╌┬╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┬╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
// │  bytes32   │ fromAddress      │ address of the sender on the origin chain              │
// │  bytes     │ payload          │ additional payload of the transfer                     │
// ┝━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │        AttestMeta                                                                      │
// ├────────────┬──────────────────┬────────────────────────────────────────────────────────┤
// │  uint8     │ payloadId        │ fixed value: 2 (see PAYLOAD_ID_ATTEST_META below)      │
// │  bytes32   │ tokenAddress     │ address of the token on the origin chain               │
// │  uint16    │ tokenChainId     │ Wormhole chain id of the origin chain                  │
// │  uint8     │ decimals         │ number of decimals of the token                        │
// │  bytes32   │ symbol           │ symbol of the token                                    │
// │  bytes32   │ name             │ name of the token                                      │
// ╰────────────┴──────────────────┴────────────────────────────────────────────────────────╯
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
// Additionally, like in BytesParsing, the Unchecked function name suffix does not refer to
//   Solidity's `unchecked` keyword, but rather to the fact that no bounds checking is performed.
//
// Decoding functions flavorless base names:
//   * decodeTransfer
//   * decodeTransferWithPayload
//   * decodeAttestMeta
//
// Encoding functions (should only be relevant for testing):
//   * encode (overloaded for each struct)
//   * encodeTransfer
//   * encodeTransferWithPayload
//   * encodeAttestMeta
//
// Other functions:
//   * checkPayloadId

struct TokenBridgeTransfer {
  //uint8 payloadId; //see PAYLOAD_ID_TRANSFER
  uint256 normalizedAmount;
  bytes32 tokenAddress;
  uint16  tokenChainId;
  bytes32 toAddress;
  uint16  toChainId;
  //uint256 fee; //discarded
}

struct TokenBridgeTransferWithPayload {
  //uint8 payloadId; //see PAYLOAD_ID_TRANSFER_WITH_PAYLOAD
  uint256 normalizedAmount;
  bytes32 tokenAddress;
  uint16  tokenChainId;
  bytes32 toAddress;
  uint16  toChainId;
  bytes32 fromAddress;
  bytes   payload;
}

struct TokenBridgeAttestMeta {
  //uint8 payloadId; //see PAYLOAD_ID_ATTEST_META
  bytes32 tokenAddress;
  uint16  tokenChainId;
  uint8   decimals;
  bytes32 symbol;
  bytes32 name;
}

library TokenBridgeMessageLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkBound, BytesParsing.checkLength} for uint;

  error InvalidPayloadId(uint8 encoded);

  //constants are provided to allow more eclectic, manual decoding
  uint8 internal constant PAYLOAD_ID_TRANSFER = 1;
  uint8 internal constant PAYLOAD_ID_TRANSFER_WITH_PAYLOAD = 3;
  uint8 internal constant PAYLOAD_ID_ATTEST_META = 2;

  uint internal constant PAYLOAD_ID_OFFSET = 0;
  uint internal constant PAYLOAD_ID_SIZE = 1;

  // Common Transfer format offsets and sizes
  uint internal constant COMMON_TRANSFER_AMOUNT_OFFSET =
    PAYLOAD_ID_OFFSET + PAYLOAD_ID_SIZE;
  uint internal constant COMMON_TRANSFER_AMOUNT_SIZE = 32;

  uint internal constant COMMON_TRANSFER_TOKEN_ADDRESS_OFFSET =
    COMMON_TRANSFER_AMOUNT_OFFSET + COMMON_TRANSFER_AMOUNT_SIZE;
  uint internal constant COMMON_TRANSFER_TOKEN_ADDRESS_SIZE = 32;

  uint internal constant COMMON_TRANSFER_TOKEN_CHAIN_ID_OFFSET =
    COMMON_TRANSFER_TOKEN_ADDRESS_OFFSET + COMMON_TRANSFER_TOKEN_ADDRESS_SIZE;
  uint internal constant COMMON_TRANSFER_TOKEN_CHAIN_ID_SIZE = 2;

  uint internal constant COMMON_TRANSFER_TO_ADDRESS_OFFSET =
    COMMON_TRANSFER_TOKEN_CHAIN_ID_OFFSET + COMMON_TRANSFER_TOKEN_CHAIN_ID_SIZE;
  uint internal constant COMMON_TRANSFER_TO_ADDRESS_SIZE = 32;

  uint internal constant COMMON_TRANSFER_TO_CHAIN_ID_OFFSET =
    COMMON_TRANSFER_TO_ADDRESS_OFFSET + COMMON_TRANSFER_TO_ADDRESS_SIZE;
  uint internal constant COMMON_TRANSFER_TO_CHAIN_ID_SIZE = 2;

  uint internal constant COMMON_TRANSFER_SIZE =
    COMMON_TRANSFER_TO_CHAIN_ID_OFFSET + COMMON_TRANSFER_TO_CHAIN_ID_SIZE;

  // Additional Transfer fields
  uint internal constant TRANSFER_FEE_OFFSET = COMMON_TRANSFER_SIZE;
  uint internal constant TRANSFER_FEE_SIZE = 32;
  uint internal constant TRANSFER_SIZE =
    TRANSFER_FEE_OFFSET + TRANSFER_FEE_SIZE;

  // Additional TransferWithPayload fields
  uint internal constant TRANSFER_WITH_PAYLOAD_FROM_ADDRESS_OFFSET = COMMON_TRANSFER_SIZE;
  uint internal constant TRANSFER_WITH_PAYLOAD_FROM_ADDRESS_SIZE = 32;

  uint internal constant TRANSFER_WITH_PAYLOAD_PAYLOAD_OFFSET = //only a mother can love this name
    TRANSFER_WITH_PAYLOAD_FROM_ADDRESS_OFFSET + TRANSFER_WITH_PAYLOAD_FROM_ADDRESS_SIZE;

  // AttestMeta format offsets and sizes
  uint internal constant ATTEST_META_TOKEN_ADDRESS_OFFSET =
    PAYLOAD_ID_OFFSET + PAYLOAD_ID_SIZE;
  uint internal constant ATTEST_META_TOKEN_ADDRESS_SIZE = 32;

  uint internal constant ATTEST_META_TOKEN_CHAIN_ID_OFFSET =
    ATTEST_META_TOKEN_ADDRESS_OFFSET + ATTEST_META_TOKEN_ADDRESS_SIZE;
  uint internal constant ATTEST_META_TOKEN_CHAIN_ID_SIZE = 2;

  uint internal constant ATTEST_META_DECIMALS_OFFSET =
    ATTEST_META_TOKEN_CHAIN_ID_OFFSET + ATTEST_META_TOKEN_CHAIN_ID_SIZE;
  uint internal constant ATTEST_META_DECIMALS_SIZE = 1;

  uint internal constant ATTEST_META_SYMBOL_OFFSET =
    ATTEST_META_DECIMALS_OFFSET + ATTEST_META_DECIMALS_SIZE;
  uint internal constant ATTEST_META_SYMBOL_SIZE = 32;

  uint internal constant ATTEST_META_NAME_OFFSET =
    ATTEST_META_SYMBOL_OFFSET + ATTEST_META_SYMBOL_SIZE;
  uint internal constant ATTEST_META_NAME_SIZE = 32;

  uint internal constant ATTEST_META_SIZE =
    ATTEST_META_NAME_OFFSET + ATTEST_META_NAME_SIZE;

  // ------------ Decoding ------------

  function checkPayloadId(uint8 encoded, uint8 expected) internal pure {
    if (encoded != expected)
      revert InvalidPayloadId(encoded);
  }

  // Transfer

  function decodeTransferCd(
    bytes calldata encoded
  ) internal pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId
  ) {
    uint offset = 0;
    (normalizedAmount, tokenAddress, tokenChainId, toAddress, toChainId, offset) =
      _decodeTransferCommonHeaderCdUnchecked(encoded, PAYLOAD_ID_TRANSFER);

    offset += WORD_SIZE;
    encoded.length.checkLength(offset);
  }

  function decodeTransferStructCd(
    bytes calldata encoded
  ) internal pure returns (TokenBridgeTransfer memory transfer) {
    ( transfer.normalizedAmount,
      transfer.tokenAddress,
      transfer.tokenChainId,
      transfer.toAddress,
      transfer.toChainId
    ) = decodeTransferCd(encoded);
  }

  function decodeTransferMem(
    bytes memory encoded
  ) internal pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId
  ) {
    uint offset = 0;
    (normalizedAmount, tokenAddress, tokenChainId, toAddress, toChainId, offset) =
      decodeTransferMemUnchecked(encoded, offset);
    encoded.length.checkLength(offset);
  }

  function decodeTransferStructMem(
    bytes memory encoded
  ) internal pure returns (TokenBridgeTransfer memory transfer) {
    ( transfer.normalizedAmount,
      transfer.tokenAddress,
      transfer.tokenChainId,
      transfer.toAddress,
      transfer.toChainId
    ) = decodeTransferMem(encoded);
  }

  function decodeTransferMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId,
    uint    newOffset
  ) {
    (normalizedAmount, tokenAddress, tokenChainId, toAddress, toChainId, offset) =
      _decodeTransferCommonHeaderMemUnchecked(encoded, offset, PAYLOAD_ID_TRANSFER);

    offset += WORD_SIZE;
    newOffset = offset;
  }

  function decodeTransferStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (TokenBridgeTransfer memory transfer, uint newOffset) {
    ( transfer.normalizedAmount,
      transfer.tokenAddress,
      transfer.tokenChainId,
      transfer.toAddress,
      transfer.toChainId,
      newOffset
    ) = decodeTransferMemUnchecked(encoded, offset);
  }

  // TransferWithPayload

  function decodeTransferWithPayloadCd(
    bytes calldata encoded
  ) internal pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId,
    bytes32 fromAddress,
    bytes calldata payload
  ) { unchecked {
    uint offset = 0;
    (normalizedAmount, tokenAddress, tokenChainId, toAddress, toChainId, offset) =
      _decodeTransferCommonHeaderCdUnchecked(encoded, PAYLOAD_ID_TRANSFER_WITH_PAYLOAD);

    (fromAddress, offset) = encoded.asBytes32CdUnchecked(offset);

    offset.checkBound(encoded.length); //check for underflow
    (payload, ) = encoded.sliceCdUnchecked(offset, encoded.length - offset);
  }}

  function decodeTransferWithPayloadStructCd(
    bytes calldata encoded
  ) internal pure returns (TokenBridgeTransferWithPayload memory twp) {
    ( twp.normalizedAmount,
      twp.tokenAddress,
      twp.tokenChainId,
      twp.toAddress,
      twp.toChainId,
      twp.fromAddress,
      twp.payload
    ) = decodeTransferWithPayloadCd(encoded);
  }

  function decodeTransferWithPayloadMem(
    bytes memory encoded
  ) internal pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId,
    bytes32 fromAddress,
    bytes memory payload
  ) {
    (normalizedAmount, tokenAddress, tokenChainId, toAddress, toChainId, fromAddress, payload, ) =
      decodeTransferWithPayloadMem(encoded, 0, encoded.length);
  }

  function decodeTransferWithPayloadStructMem(
    bytes memory encoded
  ) internal pure returns (TokenBridgeTransferWithPayload memory twp) {
    (twp, ) = decodeTransferWithPayloadStructMem(encoded, 0, encoded.length);
  }

  function decodeTransferWithPayloadMem(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId,
    bytes32 fromAddress,
    bytes memory payload,
    uint    newOffset
  ) { unchecked {
    (normalizedAmount, tokenAddress, tokenChainId, toAddress, toChainId, offset) =
      _decodeTransferCommonHeaderMemUnchecked(encoded, offset, PAYLOAD_ID_TRANSFER_WITH_PAYLOAD);

    (fromAddress, offset) = encoded.asBytes32MemUnchecked(offset);

    offset.checkBound(length); //check for underflow
    (payload, newOffset) = encoded.sliceMemUnchecked(offset, length - offset);

  }}

  function decodeTransferWithPayloadStructMem(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (TokenBridgeTransferWithPayload memory twp, uint newOffset) {
    ( twp.normalizedAmount,
      twp.tokenAddress,
      twp.tokenChainId,
      twp.toAddress,
      twp.toChainId,
      twp.fromAddress,
      twp.payload,
      newOffset
    ) = decodeTransferWithPayloadMem(encoded, offset, length);
  }

  // AttestMeta

  function decodeAttestMetaCd(
    bytes calldata encoded
  ) internal pure returns (
    bytes32 tokenAddress,
    uint16  tokenChainId,
    uint8   decimals,
    bytes32 symbol,
    bytes32 name
  ) {
    uint offset = 0;
    uint8 payloadId;
    (payloadId,    offset) = encoded.asUint8CdUnchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_ATTEST_META);
    (tokenAddress, offset) = encoded.asBytes32CdUnchecked(offset);
    (tokenChainId, offset) = encoded.asUint16CdUnchecked(offset);
    (decimals,     offset) = encoded.asUint8CdUnchecked(offset);
    (symbol,       offset) = encoded.asBytes32CdUnchecked(offset);
    (name,         offset) = encoded.asBytes32CdUnchecked(offset);
    encoded.length.checkLength(offset);
  }

  function decodeAttestMetaStructCd(
    bytes calldata encoded
  ) internal pure returns (TokenBridgeAttestMeta memory attestMeta) {
    ( attestMeta.tokenAddress,
      attestMeta.tokenChainId,
      attestMeta.decimals,
      attestMeta.symbol,
      attestMeta.name
    ) = decodeAttestMetaCd(encoded);
  }

  function decodeAttestMetaMem(
    bytes memory encoded
  ) internal pure returns (
    bytes32 tokenAddress,
    uint16  tokenChainId,
    uint8   decimals,
    bytes32 symbol,
    bytes32 name
  ) {
    uint offset = 0;
    (tokenAddress, tokenChainId, decimals, symbol, name, offset) =
      decodeAttestMetaMemUnchecked(encoded, offset);
    encoded.length.checkLength(offset);
  }

  function decodeAttestMetaStructMem(
    bytes memory encoded
  ) internal pure returns (TokenBridgeAttestMeta memory attestMeta) {
    (attestMeta, ) = decodeAttestMetaStructMemUnchecked(encoded, 0);
  }

  function decodeAttestMetaMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    bytes32 tokenAddress,
    uint16  tokenChainId,
    uint8   decimals,
    bytes32 symbol,
    bytes32 name,
    uint    newOffset
  ) {
    uint8 payloadId;
    (payloadId,    offset) = encoded.asUint8MemUnchecked(offset);
    checkPayloadId(payloadId, PAYLOAD_ID_ATTEST_META);
    (tokenAddress, offset) = encoded.asBytes32MemUnchecked(offset);
    (tokenChainId, offset) = encoded.asUint16MemUnchecked(offset);
    (decimals,     offset) = encoded.asUint8MemUnchecked(offset);
    (symbol,       offset) = encoded.asBytes32MemUnchecked(offset);
    (name,         offset) = encoded.asBytes32MemUnchecked(offset);
    newOffset = offset;
  }

  function decodeAttestMetaStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (TokenBridgeAttestMeta memory attestMeta, uint newOffset) {
    ( attestMeta.tokenAddress,
      attestMeta.tokenChainId,
      attestMeta.decimals,
      attestMeta.symbol,
      attestMeta.name,
      newOffset
    ) = decodeAttestMetaMemUnchecked(encoded, offset);
  }

  // ------------ Encoding ------------

  function encodeTransfer(
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId
  ) internal pure returns (bytes memory encoded) {
    return abi.encodePacked(
      PAYLOAD_ID_TRANSFER,
      normalizedAmount,
      tokenAddress,
      tokenChainId,
      toAddress,
      toChainId,
      uint256(0) //add otherwise discarded fee field
    );
  }

  function encode(TokenBridgeTransfer memory transfer) internal pure returns (bytes memory) {
    return encodeTransfer(
      transfer.normalizedAmount,
      transfer.tokenAddress,
      transfer.tokenChainId,
      transfer.toAddress,
      transfer.toChainId
    );
  }

  function encodeTransferWithPayload(
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId,
    bytes32 fromAddress,
    bytes memory payload
  ) internal pure returns (bytes memory encoded) {
    return abi.encodePacked(
      PAYLOAD_ID_TRANSFER_WITH_PAYLOAD,
      normalizedAmount,
      tokenAddress,
      tokenChainId,
      toAddress,
      toChainId,
      fromAddress,
      payload
    );
  }

  function encode(TokenBridgeTransferWithPayload memory twp) internal pure returns (bytes memory) {
    return encodeTransferWithPayload(
      twp.normalizedAmount,
      twp.tokenAddress,
      twp.tokenChainId,
      twp.toAddress,
      twp.toChainId,
      twp.fromAddress,
      twp.payload
    );
  }

  function encodeAttestMeta(
    bytes32 tokenAddress,
    uint16  tokenChainId,
    uint8   decimals,
    bytes32 symbol,
    bytes32 name
  ) internal pure returns (bytes memory encoded) {
    return abi.encodePacked(
      PAYLOAD_ID_ATTEST_META,
      tokenAddress,
      tokenChainId,
      decimals,
      symbol,
      name
    );
  }

  function encode(TokenBridgeAttestMeta memory attestMeta) internal pure returns (bytes memory) {
    return encodeAttestMeta(
      attestMeta.tokenAddress,
      attestMeta.tokenChainId,
      attestMeta.decimals,
      attestMeta.symbol,
      attestMeta.name
    );
  }

  // ------------ Private ------------

  function _decodeTransferCommonHeaderCdUnchecked(
    bytes calldata encoded,
    uint8 expectedPayloadId
  ) private pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId,
    uint    newOffset
  ) {
    uint8 payloadId;
    uint offset = 0;
    (payloadId,        offset) = encoded.asUint8CdUnchecked(offset);
    checkPayloadId(payloadId, expectedPayloadId);
    (normalizedAmount, offset) = encoded.asUint256CdUnchecked(offset);
    (tokenAddress,     offset) = encoded.asBytes32CdUnchecked(offset);
    (tokenChainId,     offset) = encoded.asUint16CdUnchecked(offset);
    (toAddress,        offset) = encoded.asBytes32CdUnchecked(offset);
    (toChainId,        offset) = encoded.asUint16CdUnchecked(offset);
    newOffset = offset;
  }

  function _decodeTransferCommonHeaderMemUnchecked(
    bytes memory encoded,
    uint offset,
    uint8 expectedPayloadId
  ) private pure returns (
    uint256 normalizedAmount,
    bytes32 tokenAddress,
    uint16  tokenChainId,
    bytes32 toAddress,
    uint16  toChainId,
    uint    newOffset
  ) {
    uint8 payloadId;
    (payloadId,        offset) = encoded.asUint8MemUnchecked(offset);
    checkPayloadId(payloadId, expectedPayloadId);
    (normalizedAmount, offset) = encoded.asUint256MemUnchecked(offset);
    (tokenAddress,     offset) = encoded.asBytes32MemUnchecked(offset);
    (tokenChainId,     offset) = encoded.asUint16MemUnchecked(offset);
    (toAddress,        offset) = encoded.asBytes32MemUnchecked(offset);
    (toChainId,        offset) = encoded.asUint16MemUnchecked(offset);
    newOffset = offset;
  }
}

using TokenBridgeMessageLib for TokenBridgeTransfer global;
using TokenBridgeMessageLib for TokenBridgeTransferWithPayload global;
using TokenBridgeMessageLib for TokenBridgeAttestMeta global;
