// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.14; //for (bugfixed) support of `using ... global;` syntax for libraries

import {CoreBridgeVM, GuardianSignature} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {
  toUniversalAddress,
  keccak256Cd,
  keccak256Word,
  keccak256SliceUnchecked
} from "wormhole-sdk/Utils.sol";

// ╭─────────────────────────────────────────────────╮
// │ Library for encoding and decoding Wormhole VAAs │
// ╰─────────────────────────────────────────────────╯

// # VAA Format
//
// see:
//  * ../interfaces/ICoreBridge.sol CoreBridgeVM struct (VM = Verified Message)
//  * [CoreBridge](https://github.com/wormhole-foundation/wormhole/blob/c35940ae9689f6df9e983d51425763509b74a80f/ethereum/contracts/Messages.sol#L147)
//  * [Typescript SDK](https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/3cd10030b5e924f0621c7231e24410b8a0946a07/core/definitions/src/vaa/vaa.ts#L32-L51)
//
// ╭──────────┬──────────────────────────────────────────────────────────────────────────────╮
// │ Section  │ Description                                                                  │
// ├──────────┼──────────────────────────────────────────────────────────────────────────────┤
// │ Header   │ version, guardian signature info required to verify the VAA                  │
// │ Envelope │ contains metadata of the emitted message, such as emitter or timestamp       │
// │ Payload  │ the emitted message, raw bytes, no length prefix, consumes remainder of data │
// ╰──────────┴──────────────────────────────────────────────────────────────────────────────╯
// Body = Envelope + Payload
// The VAA body is exactly the information that goes into a published message of the CoreBridge
//   and is what gets keccak256-hashed when calculating the VAA hash (i.e. the header is excluded).
//
// Note:
//   Guardians do _not_ sign the body directly, but rather the hash of the body, i.e. from the PoV
//     of a guardian, the message itself is already only a hash.
//   But [the first step of the ECDSA signature scheme](https://en.wikipedia.org/wiki/Elliptic_Curve_Digital_Signature_Algorithm#Signature_generation_algorithm)
//     is to hash the message, leading to the hash being hashed a second time when signing.
//   Likewise, ecrecover also operates on the hash of the message, rather than the message itself.
//   This means that when verifying guardian signatures of a VAA, the hash that must be passed to
//     ecrecover is the doubly-hashed body.
//
// ╭─────────────────────────────────────── WARNING ───────────────────────────────────────╮
// │ There is an unfortunate inconsistency between the implementation of the CoreBridge on │
// │   EVM, where CoreBridgeVM.hash is the *doubly* hashed body [1], while everything else │
// │   only uses the singly-hashed body (see Solana CoreBridge [2] and Typescript SDK [3]) │
// ╰───────────────────────────────────────────────────────────────────────────────────────╯
// [1] https://github.com/wormhole-foundation/wormhole/blob/1dbe8459b96e182932d0dd5ae4b6bbce6f48cb09/ethereum/contracts/Messages.sol#L178-L186
// [2] https://github.com/wormhole-foundation/wormhole/blob/1dbe8459b96e182932d0dd5ae4b6bbce6f48cb09/solana/bridge/program/src/api/post_vaa.rs#L214C4-L244
// [3] https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/3cd10030b5e924f0621c7231e24410b8a0946a07/core/definitions/src/vaa/functions.ts#L189
//
// ## Format in Detail
//
// ╭─────────────┬──────────────────┬──────────────────────────────────────────────────────────────╮
// │    Type     │       Name       │     Description                                              │
// ┝━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │           Header                                                                              │
// ├─────────────┬──────────────────┬──────────────────────────────────────────────────────────────┤
// │    uint8    │ version          │ fixed value of 1 (see HEADER_VERSION below)                  │
// │    uint32   │ guardianSetIndex │ the guardian set that signed the VAA                         │
// │    uint8    │ signatureCount   │ must be greater than guardian set size * 2 / 3 for quorum    │
// │ Signature[] │ signatures       │ signatures of the guardians that signed the VAA              │
// ┝━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │          Signature                                                                            │
// ├─────────────┬──────────────────┬──────────────────────────────────────────────────────────────┤
// │    uint8    │ guardianIndex    │ position of the signing guardian in the guardian set         │
// │   bytes32   │ r                │ ECDSA r value                                                │
// │   bytes32   │ s                │ ECDSA s value                                                │
// │    uint8    │ v                │ encoded: 0/1, decoded: 27/28, see SIGNATURE_RECOVERY_MAGIC   │
// ┝━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │          Envelope                                                                             │
// ├─────────────┬──────────────────┬──────────────────────────────────────────────────────────────┤
// │    uint32   │ timestamp        │ unix timestamp of block containing the emitted message       │
// │    uint32   │ nonce            │ user-defined nonce                                           │
// │    uint16   │ emitterChainId   │ Wormhole (not EVM) chain id of the emitter                   │
// │   bytes32   │ emitterAddress   │ universal address of the emitter                             │
// │    uint64   │ sequence         │ sequence number of the message (counter per emitter)         │
// │    uint8    │ consistencyLevel │ https://wormhole.com/docs/build/reference/consistency-levels │
// ┝━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │          Payload                                                                              │
// ├─────────────┬──────────────────┬──────────────────────────────────────────────────────────────┤
// │    bytes    │ payload          │ emitted message, consumes rest of VAA (no length prefix)     │
// ╰─────────────┴──────────────────┴──────────────────────────────────────────────────────────────╯
//
// # Library
//
// This library is built on top of BytesParsing which is a lot more gas efficient than BytesLib,
//   which is used in the CoreBridge.
//
// It also provides decoding functions for parsing the individual components of the VAA separately
//   and returning them on the stack, rather than as a struct which requires memory allocation.
//
// ## Library Functions & Naming Conventions
//
// All library functions come in 2 flavors:
//   1. Calldata (using the Cd tag)
//   2. Memory (using the Mem tag)
//
// Additionally, most functions also have an additional struct flavor that returns the decoded
//   values in the associated struct (in memory), rather than as individual values (on the stack).
//
// The parameter name `encodedVaa` is used for functions where the bytes are expected to contain
//   a single, full VAA. Otherwise, i.e. for partials or multiple VAAs, the name `encoded` is used.
//
// Like in BytesParsing, the Unchecked function name suffix does not refer to Solidity's `unchecked`
//   keyword, but rather to the fact that no bounds checking is performed. All math is done using
//   unchecked arithmetic because overflows are impossible due to the nature of the VAA format,
//   while we explicitly check for underflows where necessary.
//
// Function names, somewhat redundantly, contain the tag "Vaa" to add clarity and avoid potential
//   name collisions when using the library with a `using ... for bytes` directive.
//
//   Function Base Name  │     Description
//  ─────────────────────┼────────────────────────────────────────────────────────────────────────
//   decodeVmStruct      │ decodes a legacy VM struct (no non-struct flavor available)
//   decodeVaaEssentials │ decodes the emitter, sequence, and payload
//   decodeVaaBody       │ decodes the envelope and payload
//   checkVaaVersion     │
//   skipVaaHeader       │ returns the offset to the envelope
//   calcVaaSingleHash   │ see explanation/WARNING box at the top
//   calcVaaDoubleHash   │ see explanation/WARNING box at the top
//   decodeVaaEnvelope   │
//   decodeVaaPayload    │
//
// encode functions (for testing, converts back into serialized byte array format):
//   * encode (overloaded for each struct)
//   * encodeVaaHeader
//   * encodeVaaEnvelope
//   * encodeVaaBody
//   * encodeVaa

struct VaaHeader {
  //uint8 version;
  uint32 guardianSetIndex;
  GuardianSignature[] signatures;
}

struct VaaEnvelope {
  uint32 timestamp;
  uint32 nonce;
  uint16 emitterChainId;
  bytes32 emitterAddress;
  uint64 sequence;
  uint8 consistencyLevel;
}

struct VaaBody {
  VaaEnvelope envelope;
  bytes payload;
}

struct Vaa {
  VaaHeader header;
  VaaEnvelope envelope;
  bytes payload;
}

struct VaaEssentials {
  uint16 emitterChainId;
  bytes32 emitterAddress;
  uint64 sequence;
  bytes payload;
}

library VaaLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkBound} for uint;

  error InvalidVersion(uint8 version);

  uint8 internal constant HEADER_VERSION = 1;
  //see https://github.com/wormhole-foundation/wormhole/blob/c35940ae9689f6df9e983d51425763509b74a80f/ethereum/contracts/Messages.sol#L174
  //origin: https://bitcoin.stackexchange.com/a/102382
  uint8 internal constant SIGNATURE_RECOVERY_MAGIC = 27;

  //the following offsets are provided for more eclectic, manual parsing
  uint internal constant HEADER_VERSION_OFFSET = 0;
  uint internal constant HEADER_VERSION_SIZE = 1;

  uint internal constant HEADER_GUARDIAN_SET_INDEX_OFFSET =
    HEADER_VERSION_OFFSET + HEADER_VERSION_SIZE;
  uint internal constant HEADER_GUARDIAN_SET_INDEX_SIZE = 4;

  uint internal constant HEADER_SIGNATURE_COUNT_OFFSET =
    HEADER_GUARDIAN_SET_INDEX_OFFSET + HEADER_GUARDIAN_SET_INDEX_SIZE;
  uint internal constant HEADER_SIGNATURE_COUNT_SIZE = 1;

  uint internal constant HEADER_SIGNATURE_ARRAY_OFFSET =
    HEADER_SIGNATURE_COUNT_OFFSET + HEADER_SIGNATURE_COUNT_SIZE;

  uint internal constant GUARDIAN_SIGNATURE_GUARDIAN_INDEX_OFFSET = 0;
  uint internal constant GUARDIAN_SIGNATURE_GUARDIAN_INDEX_SIZE = 1;

  uint internal constant GUARDIAN_SIGNATURE_R_OFFSET =
    GUARDIAN_SIGNATURE_GUARDIAN_INDEX_OFFSET + GUARDIAN_SIGNATURE_GUARDIAN_INDEX_SIZE;
  uint internal constant GUARDIAN_SIGNATURE_R_SIZE = 32;

  uint internal constant GUARDIAN_SIGNATURE_S_OFFSET =
    GUARDIAN_SIGNATURE_R_OFFSET + GUARDIAN_SIGNATURE_R_SIZE;
  uint internal constant GUARDIAN_SIGNATURE_S_SIZE = 32;

  uint internal constant GUARDIAN_SIGNATURE_V_OFFSET =
    GUARDIAN_SIGNATURE_S_OFFSET + GUARDIAN_SIGNATURE_S_SIZE;
  uint internal constant GUARDIAN_SIGNATURE_V_SIZE = 1;

  uint internal constant GUARDIAN_SIGNATURE_SIZE =
    GUARDIAN_SIGNATURE_V_OFFSET + GUARDIAN_SIGNATURE_V_SIZE;

  uint internal constant ENVELOPE_TIMESTAMP_OFFSET = 0;
  uint internal constant ENVELOPE_TIMESTAMP_SIZE = 4;

  uint internal constant ENVELOPE_NONCE_OFFSET =
    ENVELOPE_TIMESTAMP_OFFSET + ENVELOPE_TIMESTAMP_SIZE;
  uint internal constant ENVELOPE_NONCE_SIZE = 4;

  uint internal constant ENVELOPE_EMITTER_CHAIN_ID_OFFSET =
    ENVELOPE_NONCE_OFFSET + ENVELOPE_NONCE_SIZE;
  uint internal constant ENVELOPE_EMITTER_CHAIN_ID_SIZE = 2;

  uint internal constant ENVELOPE_EMITTER_ADDRESS_OFFSET =
    ENVELOPE_EMITTER_CHAIN_ID_OFFSET + ENVELOPE_EMITTER_CHAIN_ID_SIZE;
  uint internal constant ENVELOPE_EMITTER_ADDRESS_SIZE = 32;

  uint internal constant ENVELOPE_SEQUENCE_OFFSET =
    ENVELOPE_EMITTER_ADDRESS_OFFSET + ENVELOPE_EMITTER_ADDRESS_SIZE;
  uint internal constant ENVELOPE_SEQUENCE_SIZE = 8;

  uint internal constant ENVELOPE_CONSISTENCY_LEVEL_OFFSET =
    ENVELOPE_SEQUENCE_OFFSET + ENVELOPE_SEQUENCE_SIZE;
  uint internal constant ENVELOPE_CONSISTENCY_LEVEL_SIZE = 1;

  uint internal constant ENVELOPE_SIZE =
    ENVELOPE_CONSISTENCY_LEVEL_OFFSET + ENVELOPE_CONSISTENCY_LEVEL_SIZE;

  // ------------ Convenience Decoding Functions ------------

  //legacy decoder for CoreBridgeVM
  function decodeVmStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (CoreBridgeVM memory vm) {
    vm.version = HEADER_VERSION;
    uint envelopeOffset;
    (vm.guardianSetIndex, vm.signatures, envelopeOffset) = decodeVaaHeaderCdUnchecked(encodedVaa);
    vm.hash = calcVaaDoubleHashCd(encodedVaa, envelopeOffset);
    ( vm.timestamp,
      vm.nonce,
      vm.emitterChainId,
      vm.emitterAddress,
      vm.sequence,
      vm.consistencyLevel,
      vm.payload
    ) = decodeVaaBodyCd(encodedVaa, envelopeOffset);
  }

  function decodeVmStructMem(
    bytes memory encodedVaa
  ) internal pure returns (CoreBridgeVM memory vm) {
    (vm, ) = decodeVmStructMemUnchecked(encodedVaa, 0, encodedVaa.length);
  }

  function decodeVaaStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (Vaa memory vaa) {
    uint envelopeOffset;
    (vaa.header, envelopeOffset) = decodeVaaHeaderStructCdUnchecked(encodedVaa);
    uint payloadOffset;
    (vaa.envelope, payloadOffset) = decodeVaaEnvelopeStructCdUnchecked(encodedVaa, envelopeOffset);
    vaa.payload = decodeVaaPayloadCd(encodedVaa, payloadOffset);
  }

  function decodeVaaStructMem(
    bytes memory encodedVaa
  ) internal pure returns (Vaa memory vaa) {
    (vaa, ) = decodeVaaStructMemUnchecked(encodedVaa, 0, encodedVaa.length);
  }

  function decodeVaaEssentialsCd(
    bytes calldata encodedVaa
  ) internal pure returns (
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    bytes calldata payload
  ) { unchecked {
    checkVaaVersionCdUnchecked(encodedVaa);

    uint envelopeOffset = skipVaaHeaderCdUnchecked(encodedVaa);
    uint offset = envelopeOffset + ENVELOPE_EMITTER_CHAIN_ID_OFFSET;
    (emitterChainId, offset) = encodedVaa.asUint16CdUnchecked(offset);
    (emitterAddress, offset) = encodedVaa.asBytes32CdUnchecked(offset);
    (sequence,             ) = encodedVaa.asUint64CdUnchecked(offset);

    uint payloadOffset = envelopeOffset + ENVELOPE_SIZE;
    payload = decodeVaaPayloadCd(encodedVaa, payloadOffset);
  }}

  function decodeVaaEssentialsStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (VaaEssentials memory ret) {
    (ret.emitterChainId, ret.emitterAddress, ret.sequence, ret.payload) =
      decodeVaaEssentialsCd(encodedVaa);
  }

  //The returned values are considered the essentials because it's important to check the emitter
  //  to avoid spoofing. Also, VAAs that use finalized consistency levels should leverage the
  //  sequence number (on a per emitter basis!) and a bitmap for replay protection rather than the
  //  hashed body because it is more gas efficient (storage slot is likely already dirty).
  function decodeVaaEssentialsMem(
    bytes memory encodedVaa
  ) internal pure returns (
    uint16 emitterChainId,
    bytes32 emitterAddress,
    uint64 sequence,
    bytes memory payload
  ) {
    (emitterChainId, emitterAddress, sequence, payload, ) =
      decodeVaaEssentialsMem(encodedVaa, 0, encodedVaa.length);
  }

  function decodeVaaEssentialsStructMem(
    bytes memory encodedVaa
  ) internal pure returns (VaaEssentials memory ret) {
    (ret.emitterChainId, ret.emitterAddress, ret.sequence, ret.payload, ) =
      decodeVaaEssentialsMem(encodedVaa, 0, encodedVaa.length);
  }

  function decodeVaaEssentialsMem(
    bytes memory encoded,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    bytes memory payload,
    uint    newOffset
  ) { unchecked {
    uint offset = checkVaaVersionMemUnchecked(encoded, headerOffset);

    uint envelopeOffset = skipVaaHeaderMemUnchecked(encoded, offset);
    offset = envelopeOffset + ENVELOPE_EMITTER_CHAIN_ID_OFFSET;
    (emitterChainId, offset) = encoded.asUint16MemUnchecked(offset);
    (emitterAddress, offset) = encoded.asBytes32MemUnchecked(offset);
    (sequence,             ) = encoded.asUint64MemUnchecked(offset);

    uint payloadOffset = envelopeOffset + ENVELOPE_SIZE;
    (payload, newOffset) = decodeVaaPayloadMemUnchecked(encoded, payloadOffset, vaaLength);
  }}

  function decodeVaaEssentialsStructMem(
    bytes memory encodedVaa,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (VaaEssentials memory ret, uint newOffset) {
    (ret.emitterChainId, ret.emitterAddress, ret.sequence, ret.payload, newOffset) =
      decodeVaaEssentialsMem(encodedVaa, headerOffset, vaaLength);
  }

  function decodeVaaBodyCd(
    bytes calldata encodedVaa
  ) internal pure returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes calldata payload
  ) {
    checkVaaVersionCdUnchecked(encodedVaa);
    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payload) =
      decodeVaaBodyCd(encodedVaa, skipVaaHeaderCdUnchecked(encodedVaa));
  }

  function decodeVaaBodyStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (VaaBody memory body) {
    ( body.envelope.timestamp,
      body.envelope.nonce,
      body.envelope.emitterChainId,
      body.envelope.emitterAddress,
      body.envelope.sequence,
      body.envelope.consistencyLevel,
      body.payload
    ) = decodeVaaBodyCd(encodedVaa);
  }

  function decodeVaaBodyMem(
    bytes memory encodedVaa
  ) internal pure returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes memory payload
  ) {
    checkVaaVersionMemUnchecked(encodedVaa, 0);
    uint envelopeOffset = skipVaaHeaderMemUnchecked(encodedVaa, 0);
    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payload, ) =
      decodeVaaBodyMemUnchecked(encodedVaa, envelopeOffset, encodedVaa.length);
  }

  function decodeVaaBodyStructMem(
    bytes memory encodedVaa
  ) internal pure returns (VaaBody memory body) {
    ( body.envelope.timestamp,
      body.envelope.nonce,
      body.envelope.emitterChainId,
      body.envelope.emitterAddress,
      body.envelope.sequence,
      body.envelope.consistencyLevel,
      body.payload,
    ) = decodeVaaBodyMemUnchecked(encodedVaa, 0, encodedVaa.length);
  }

  // Convinience decoding function for token bridge Vaas
  function decodeEmitterChainAndPayloadCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (uint16 emitterChainId, bytes calldata payload) { unchecked {
    checkVaaVersionCdUnchecked(encodedVaa);
    uint envelopeOffset = skipVaaHeaderCdUnchecked(encodedVaa);
    uint offset = envelopeOffset + ENVELOPE_EMITTER_CHAIN_ID_OFFSET;
    (emitterChainId, offset) = encodedVaa.asUint16CdUnchecked(offset);
    offset +=
      ENVELOPE_EMITTER_ADDRESS_SIZE + ENVELOPE_SEQUENCE_SIZE + ENVELOPE_CONSISTENCY_LEVEL_SIZE;
    payload = decodeVaaPayloadCd(encodedVaa, offset);
  }}

  function decodeEmitterChainAndPayloadMemUnchecked(
    bytes memory encodedVaa
  ) internal pure returns (uint16 emitterChainId, bytes memory payload) { unchecked {
    checkVaaVersionMemUnchecked(encodedVaa, 0);
    uint envelopeOffset = skipVaaHeaderMemUnchecked(encodedVaa, 0);
    uint offset = envelopeOffset + ENVELOPE_EMITTER_CHAIN_ID_OFFSET;
    (emitterChainId, offset) = encodedVaa.asUint16MemUnchecked(offset);
    offset +=
      ENVELOPE_EMITTER_ADDRESS_SIZE + ENVELOPE_SEQUENCE_SIZE + ENVELOPE_CONSISTENCY_LEVEL_SIZE;
    (payload, ) = decodeVaaPayloadMemUnchecked(encodedVaa, offset, encodedVaa.length);
  }}

  // ------------ Advanced Decoding Functions ------------

  function checkVaaVersionCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (uint newOffset) {
    uint8 version;
    (version, newOffset) = encodedVaa.asUint8CdUnchecked(0);
    checkVaaVersion(version);
  }

  function checkVaaVersionMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint newOffset) {
    uint8 version;
    (version, newOffset) = encoded.asUint8MemUnchecked(offset);
    checkVaaVersion(version);
  }

  function checkVaaVersion(uint8 version) internal pure {
    if (version != HEADER_VERSION)
      revert InvalidVersion(version);
  }

  //return the offset to the start of the envelope/body
  function skipVaaHeaderCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (uint envelopeOffset) { unchecked {
    (uint sigCount, uint offset) = encodedVaa.asUint8CdUnchecked(HEADER_SIGNATURE_COUNT_OFFSET);
    envelopeOffset = offset + sigCount * GUARDIAN_SIGNATURE_SIZE;
  }}

  function skipVaaHeaderMemUnchecked(
    bytes memory encoded,
    uint headerOffset
  ) internal pure returns (uint envelopeOffset) { unchecked {
    uint offset = headerOffset + HEADER_SIGNATURE_COUNT_OFFSET;
    uint sigCount;
    (sigCount, offset) = encoded.asUint8MemUnchecked(offset);
    envelopeOffset = offset + sigCount * GUARDIAN_SIGNATURE_SIZE;
  }}

  //see WARNING box at the top
  function calcVaaSingleHashCd(
    bytes calldata encodedVaa,
    uint envelopeOffset
  ) internal pure returns (bytes32) {
    return keccak256Cd(_decodeRemainderCd(encodedVaa, envelopeOffset));
  }

  //see WARNING box at the top
  function calcVaaSingleHashMem(
    bytes memory encoded,
    uint envelopeOffset,
    uint vaaLength
  ) internal pure returns (bytes32) { unchecked {
    envelopeOffset.checkBound(vaaLength);
    return keccak256SliceUnchecked(encoded, envelopeOffset, vaaLength - envelopeOffset);
  }}

  //see WARNING box at the top
  function calcSingleHash(Vaa memory vaa) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(encode(vaa.envelope), vaa.payload));
  }

  //see WARNING box at the top
  function calcSingleHash(VaaBody memory body) internal pure returns (bytes32) {
    return keccak256(encode(body));
  }

  //see WARNING box at the top
  //this function matches CoreBridgeVM.hash and is what's been used for (legacy) replay protection
  function calcVaaDoubleHashCd(
    bytes calldata encodedVaa,
    uint envelopeOffset
  ) internal pure returns (bytes32) {
    return keccak256Word(calcVaaSingleHashCd(encodedVaa, envelopeOffset));
  }

  //see WARNING box at the top
  function calcVaaDoubleHashMem(
    bytes memory encoded,
    uint envelopeOffset,
    uint vaaLength
  ) internal pure returns (bytes32) {
    return keccak256Word(calcVaaSingleHashMem(encoded, envelopeOffset, vaaLength));
  }

  //see WARNING box at the top
  function calcDoubleHash(Vaa memory vaa) internal pure returns (bytes32) {
    return keccak256Word(calcSingleHash(vaa));
  }

  //see WARNING box at the top
  function calcDoubleHash(VaaBody memory body) internal pure returns (bytes32) {
    return keccak256Word(calcSingleHash(body));
  }

  function decodeVmStructMemUnchecked(
    bytes memory encoded,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (CoreBridgeVM memory vm, uint newOffset) {
    vm.version = HEADER_VERSION;
    uint envelopeOffset;
    (vm.guardianSetIndex, vm.signatures, envelopeOffset) =
      decodeVaaHeaderMemUnchecked(encoded, headerOffset);
    vm.hash = calcVaaDoubleHashMem(encoded, envelopeOffset, vaaLength);
    ( vm.timestamp,
      vm.nonce,
      vm.emitterChainId,
      vm.emitterAddress,
      vm.sequence,
      vm.consistencyLevel,
      vm.payload,
      newOffset
    ) = decodeVaaBodyMemUnchecked(encoded, envelopeOffset, vaaLength);
  }

  function decodeVaaStructMemUnchecked(
    bytes memory encoded,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (Vaa memory vaa, uint newOffset) {
    uint envelopeOffset;
    (vaa.header.guardianSetIndex, vaa.header.signatures, envelopeOffset) =
      decodeVaaHeaderMemUnchecked(encoded, headerOffset);
    uint payloadOffset;
    (vaa.envelope, payloadOffset) = decodeVaaEnvelopeStructMemUnchecked(encoded, envelopeOffset);

    (vaa.payload, newOffset) = decodeVaaPayloadMemUnchecked(encoded, payloadOffset, vaaLength);
  }

  function decodeVaaBodyCd(
    bytes calldata encodedVaa,
    uint envelopeOffset
  ) internal pure returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes calldata payload
  ) {
    uint payloadOffset;
    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payloadOffset) =
      decodeVaaEnvelopeCdUnchecked(encodedVaa, envelopeOffset);
    payload = decodeVaaPayloadCd(encodedVaa, payloadOffset);
  }

  function decodeVaaBodyStructCd(
    bytes calldata encodedVaa,
    uint envelopeOffset
  ) internal pure returns (VaaBody memory body) {
    ( body.envelope.timestamp,
      body.envelope.nonce,
      body.envelope.emitterChainId,
      body.envelope.emitterAddress,
      body.envelope.sequence,
      body.envelope.consistencyLevel,
      body.payload
    ) = decodeVaaBodyCd(encodedVaa, envelopeOffset);
  }

  function decodeVaaBodyMemUnchecked(
    bytes memory encoded,
    uint envelopeOffset,
    uint vaaLength
  ) internal pure returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes memory payload,
    uint    newOffset
  ) {
    uint payloadOffset;
    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payloadOffset) =
      decodeVaaEnvelopeMemUnchecked(encoded, envelopeOffset);
    (payload, newOffset) = decodeVaaPayloadMemUnchecked(encoded, payloadOffset, vaaLength);
  }

  function decodeVaaBodyStructMemUnchecked(
    bytes memory encoded,
    uint envelopeOffset,
    uint vaaLength
  ) internal pure returns (VaaBody memory body, uint newOffset) {
    ( body.envelope.timestamp,
      body.envelope.nonce,
      body.envelope.emitterChainId,
      body.envelope.emitterAddress,
      body.envelope.sequence,
      body.envelope.consistencyLevel,
      body.payload,
      newOffset
    ) = decodeVaaBodyMemUnchecked(encoded, envelopeOffset, vaaLength);
  }

  function decodeVaaEnvelopeCdUnchecked(
    bytes calldata encodedVaa,
    uint envelopeOffset
  ) internal pure returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    uint    payloadOffset
  ) {
    uint offset = envelopeOffset;
    (timestamp,        offset) = encodedVaa.asUint32CdUnchecked(offset);
    (nonce,            offset) = encodedVaa.asUint32CdUnchecked(offset);
    (emitterChainId,   offset) = encodedVaa.asUint16CdUnchecked(offset);
    (emitterAddress,   offset) = encodedVaa.asBytes32CdUnchecked(offset);
    (sequence,         offset) = encodedVaa.asUint64CdUnchecked(offset);
    (consistencyLevel, offset) = encodedVaa.asUint8CdUnchecked(offset);
    payloadOffset = offset;
  }

  function decodeVaaEnvelopeStructCdUnchecked(
    bytes calldata encodedVaa,
    uint envelopeOffset
  ) internal pure returns (VaaEnvelope memory envelope, uint payloadOffset) {
    ( envelope.timestamp,
      envelope.nonce,
      envelope.emitterChainId,
      envelope.emitterAddress,
      envelope.sequence,
      envelope.consistencyLevel,
      payloadOffset
    ) = decodeVaaEnvelopeCdUnchecked(encodedVaa, envelopeOffset);
  }

  function decodeVaaEnvelopeMemUnchecked(
    bytes memory encoded,
    uint envelopeOffset
  ) internal pure returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    uint    payloadOffset
  ) {
    uint offset = envelopeOffset;
    (timestamp,        offset) = encoded.asUint32MemUnchecked(offset);
    (nonce,            offset) = encoded.asUint32MemUnchecked(offset);
    (emitterChainId,   offset) = encoded.asUint16MemUnchecked(offset);
    (emitterAddress,   offset) = encoded.asBytes32MemUnchecked(offset);
    (sequence,         offset) = encoded.asUint64MemUnchecked(offset);
    (consistencyLevel, offset) = encoded.asUint8MemUnchecked(offset);
    payloadOffset = offset;
  }

  function decodeVaaEnvelopeStructMemUnchecked(
    bytes memory encoded,
    uint envelopeOffset
  ) internal pure returns (VaaEnvelope memory envelope, uint payloadOffset) {
    ( envelope.timestamp,
      envelope.nonce,
      envelope.emitterChainId,
      envelope.emitterAddress,
      envelope.sequence,
      envelope.consistencyLevel,
      payloadOffset
    ) = decodeVaaEnvelopeMemUnchecked(encoded, envelopeOffset);
  }

  function decodeVaaHeaderCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (
    uint32 guardianSetIndex,
    GuardianSignature[] memory signatures,
    uint envelopeOffset
  ) { unchecked {
    checkVaaVersionCdUnchecked(encodedVaa);
    uint offset = HEADER_GUARDIAN_SET_INDEX_OFFSET;
    (guardianSetIndex, offset) = encodedVaa.asUint32CdUnchecked(offset);

    uint signersLen;
    (signersLen, offset) = encodedVaa.asUint8CdUnchecked(offset);

    signatures = new GuardianSignature[](signersLen);
    for (uint i = 0; i < signersLen; ++i)
      (signatures[i], offset) = decodeGuardianSignatureStructCdUnchecked(encodedVaa, offset);

    envelopeOffset = offset;
  }}

  function decodeVaaHeaderStructCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (VaaHeader memory header, uint envelopeOffset) {
    ( header.guardianSetIndex,
      header.signatures,
      envelopeOffset
    ) = decodeVaaHeaderCdUnchecked(encodedVaa);
  }

  function decodeVaaHeaderMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint32 guardianSetIndex,
    GuardianSignature[] memory signatures,
    uint envelopeOffset
  ) { unchecked {
    offset = checkVaaVersionMemUnchecked(encoded, offset);
    (guardianSetIndex, offset) = encoded.asUint32MemUnchecked(offset);

    uint signersLen;
    (signersLen, offset) = encoded.asUint8MemUnchecked(offset);

    signatures = new GuardianSignature[](signersLen);
    for (uint i = 0; i < signersLen; ++i)
      (signatures[i], offset) = decodeGuardianSignatureStructMemUnchecked(encoded, offset);

    envelopeOffset = offset;
  }}

  function decodeVaaHeaderStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (VaaHeader memory header, uint envelopeOffset) {
    ( header.guardianSetIndex,
      header.signatures,
      envelopeOffset
    ) = decodeVaaHeaderMemUnchecked(encoded, offset);
  }

  function decodeGuardianSignatureCdUnchecked(
    bytes calldata encodedVaa,
    uint offset
  ) internal pure returns (
    uint8 guardianIndex,
    bytes32 r,
    bytes32 s,
    uint8 v,
    uint newOffset
  ) { unchecked {
    (guardianIndex, offset) = encodedVaa.asUint8CdUnchecked(offset);
    (r,             offset) = encodedVaa.asBytes32CdUnchecked(offset);
    (s,             offset) = encodedVaa.asBytes32CdUnchecked(offset);
    (v,             offset) = encodedVaa.asUint8CdUnchecked(offset);
    v += SIGNATURE_RECOVERY_MAGIC;
    newOffset = offset;
  }}

  function decodeGuardianSignatureStructCdUnchecked(
    bytes calldata encodedVaa,
    uint offset
  ) internal pure returns (GuardianSignature memory ret, uint newOffset) {
    (ret.guardianIndex, ret.r, ret.s, ret.v, newOffset) =
      decodeGuardianSignatureCdUnchecked(encodedVaa, offset);
  }

  function decodeGuardianSignatureMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (
    uint8 guardianIndex,
    bytes32 r,
    bytes32 s,
    uint8 v,
    uint newOffset
  ) { unchecked {
    (guardianIndex, offset) = encoded.asUint8MemUnchecked(offset);
    (r,             offset) = encoded.asBytes32MemUnchecked(offset);
    (s,             offset) = encoded.asBytes32MemUnchecked(offset);
    (v,             offset) = encoded.asUint8MemUnchecked(offset);
    v += SIGNATURE_RECOVERY_MAGIC;
    newOffset = offset;
  }}

  function decodeGuardianSignatureStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (GuardianSignature memory ret, uint newOffset) {
    (ret.guardianIndex, ret.r, ret.s, ret.v, newOffset) =
      decodeGuardianSignatureMemUnchecked(encoded, offset);
  }

  function decodeVaaPayloadCd(
    bytes calldata encodedVaa,
    uint payloadOffset
  ) internal pure returns (bytes calldata payload) {
    payload = _decodeRemainderCd(encodedVaa, payloadOffset);
  }

  function decodeVaaPayloadMemUnchecked(
    bytes memory encoded,
    uint payloadOffset,
    uint vaaLength
  ) internal pure returns (bytes memory payload, uint newOffset) { unchecked {
    //check to avoid underflow in following subtraction
    payloadOffset.checkBound(vaaLength);
    (payload, newOffset) = encoded.sliceMemUnchecked(payloadOffset, vaaLength - payloadOffset);
  }}

  // ------------ Encoding ------------

  function encode(CoreBridgeVM memory vm) internal pure returns (bytes memory) { unchecked {
    require(vm.version == HEADER_VERSION, "Invalid version");
    return abi.encodePacked(
      encodeVaaHeader(vm.guardianSetIndex, vm.signatures),
      vm.timestamp,
      vm.nonce,
      vm.emitterChainId,
      vm.emitterAddress,
      vm.sequence,
      vm.consistencyLevel,
      vm.payload
    );
  }}

  function encodeVaaHeader(
    uint32 guardianSetIndex,
    GuardianSignature[] memory signatures
  ) internal pure returns (bytes memory) {
    bytes memory sigs;
    for (uint i = 0; i < signatures.length; ++i) {
      GuardianSignature memory sig = signatures[i];
      uint8 v = sig.v - SIGNATURE_RECOVERY_MAGIC; //deliberately checked
      sigs = bytes.concat(sigs, abi.encodePacked(sig.guardianIndex, sig.r, sig.s, v));
    }

    return abi.encodePacked(
      HEADER_VERSION,
      guardianSetIndex,
      uint8(signatures.length),
      sigs
    );
  }

  function encode(VaaHeader memory header) internal pure returns (bytes memory) {
    return encodeVaaHeader(header.guardianSetIndex, header.signatures);
  }

  function encodeVaaEnvelope(
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      timestamp,
      nonce,
      emitterChainId,
      emitterAddress,
      sequence,
      consistencyLevel
    );
  }

  function encode(VaaEnvelope memory envelope) internal pure returns (bytes memory) {
    return encodeVaaEnvelope(
      envelope.timestamp,
      envelope.nonce,
      envelope.emitterChainId,
      envelope.emitterAddress,
      envelope.sequence,
      envelope.consistencyLevel
    );
  }

  function encodeVaaBody(
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes memory payload
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      encodeVaaEnvelope(
        timestamp,
        nonce,
        emitterChainId,
        emitterAddress,
        sequence,
        consistencyLevel
      ),
      payload
    );
  }

  function encode(VaaBody memory body) internal pure returns (bytes memory) {
    return abi.encodePacked(encode(body.envelope), body.payload);
  }

  function encodeVaa(
    uint32 guardianSetIndex,
    GuardianSignature[] memory signatures,
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes memory payload
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      encodeVaaHeader(guardianSetIndex, signatures),
      encodeVaaBody(
        timestamp,
        nonce,
        emitterChainId,
        emitterAddress,
        sequence,
        consistencyLevel,
        payload
      )
    );
  }

  function encode(Vaa memory vaa) internal pure returns (bytes memory) {
    return encodeVaa(
      vaa.header.guardianSetIndex,
      vaa.header.signatures,
      vaa.envelope.timestamp,
      vaa.envelope.nonce,
      vaa.envelope.emitterChainId,
      vaa.envelope.emitterAddress,
      vaa.envelope.sequence,
      vaa.envelope.consistencyLevel,
      vaa.payload
    );
  }

  // ------------ Private ------------

  //we use this function over encodedVaa[offset:] to consistently get BytesParsing errors
  function _decodeRemainderCd(
    bytes calldata encodedVaa,
    uint offset
  ) private pure returns (bytes calldata remainder) { unchecked {
    //check to avoid underflow in following subtraction
    offset.checkBound(encodedVaa.length);
    (remainder, ) = encodedVaa.sliceCdUnchecked(offset, encodedVaa.length - offset);
  }}
}

using VaaLib for VaaHeader global;
using VaaLib for VaaEnvelope global;
using VaaLib for VaaBody global;
using VaaLib for Vaa global;
