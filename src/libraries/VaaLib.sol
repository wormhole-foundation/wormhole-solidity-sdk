// SPDX-License-Identifier: Apache-2.0
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
// for MultiSig (= original) VAAs, see:
//  * ../interfaces/ICoreBridge.sol CoreBridgeVM struct (VM = Verified Message)
//  * [CoreBridge](https://github.com/wormhole-foundation/wormhole/blob/c35940ae9689f6df9e983d51425763509b74a80f/ethereum/contracts/Messages.sol#L147)
//  * [Typescript SDK](https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/3cd10030b5e924f0621c7231e24410b8a0946a07/core/definitions/src/vaa/vaa.ts#L32-L51)
//
// ╭──────────┬──────────────────────────────────────────────────────────────────────────────╮
// │ Section  │ Description                                                                  │
// ├──────────┼──────────────────────────────────────────────────────────────────────────────┤
// │ Header   │ version + attestation required to verify the VAA                             │
// │ Envelope │ contains metadata of the emitted message, such as emitter or timestamp       │
// │ Payload  │ the emitted message, raw bytes, no length prefix, consumes remainder of data │
// ╰──────────┴──────────────────────────────────────────────────────────────────────────────╯
// Header = Version  + Attestation
// Body   = Envelope + Payload
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
// ### VAA Headers
//
// ╭─────────────┬──────────────────┬──────────────────────────────────────────────────────────────╮
// │    Type     │       Name       │     Description                                              │
// ┝━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │     MultiSig Header                                                                           │
// ├─────────────┬──────────────────┬──────────────────────────────────────────────────────────────┤
// │    uint8    │ version          │ fixed value of 1 (see VERSION_MULTISIG)                      │
// │    uint32   │ guardianSetIndex │ the guardian set that signed the VAA                         │
// │    uint8    │ signatureCount   │ must be greater than guardian set size * 2 / 3 for quorum    │
// │ Signature[] │ signatures       │ signatures of the individual guardians that signed the VAA   │
// ├─────────────┴──────────────────┴──────────────────────────────────────────────────────────────┤
// │          Signature                                                                            │
// ├─────────────┬──────────────────┬──────────────────────────────────────────────────────────────┤
// │    uint8    │ guardianIndex    │ position of the signing guardian in the guardian set         │
// │   bytes32   │ r                │ ECDSA r value                                                │
// │   bytes32   │ s                │ ECDSA s value                                                │
// │    uint8    │ v                │ encoded: 0/1, decoded: 27/28, see SIGNATURE_RECOVERY_MAGIC   │
// ┝━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │      Schnorr Header                                                                           │
// ├─────────────┬──────────────────┬──────────────────────────────────────────────────────────────┤
// │    uint8    │ version          │ fixed value of 2 (see VERSION_SCHNORR)                       │
// │    uint32   │ schnorrKeyIndex  │ which (collective) Guardian Schnorr key signed the VAA       │
// │   bytes20   │ r                │ Schnorr r value                                              │
// │   bytes32   │ s                │ Schnorr s value                                              │
// ╰─────────────┴──────────────────┴──────────────────────────────────────────────────────────────╯
//
// ### VAA Body
//
// ╭─────────────┬──────────────────┬──────────────────────────────────────────────────────────────╮
// │    Type     │       Name       │     Description                                              │
// ┝━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
// │           Header (MultiSig or Schnorr)                                                        │
// ┝━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┥
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
// The parameter names `encodedVaa` and `encodedAttestation` are used for functions where the bytes
//   are expected to contain a single, full VAA/attestation. Otherwise, i.e. for partials or
//   multiple VAAs, the name `encoded` is used.
//
// Like in BytesParsing, the Unchecked function name suffix does not refer to Solidity's `unchecked`
//   keyword, but rather to the fact that no bounds checking is performed. All math is done using
//   unchecked arithmetic because overflows are impossible due to the nature of the VAA format,
//   while we explicitly check for underflows where necessary.
//
// Function names, somewhat redundantly, contain the tag "Vaa" to add clarity and avoid potential
//   name collisions when using the library with a `using ... for bytes` directive.
//
//   Function Base Name         │     Description
//  ────────────────────────────┼───────────────────────────────────────────────────────────────────
//   decodeVaaStruct            │ as expected (no non-struct flavor available)
//   decodeVaaEssentials        │ decodes the emitter, sequence, and payload (see struct comment)
//   decodeVaaHeader            │
//   decodeVaaEnvelope          │
//   decodeVaaPayload           │
//   decodeVaaBody              │ decodes the envelope and payload
//   decodeVaa<Type>            │ decodes the expected VAA type (Type = MultiSig or Schnorr)
//   decodeVaaAttestation<Type> │ decodes the attestation alone
//   decodeVmStruct             │ decodes a legacy VM struct (no non-struct flavor available)
//   checkVaaVersion            │
//   skipVaaHeader              │ returns the offset to the envelope
//   calcVaaSingleHash          │ see explanation/WARNING box at the top
//   calcVaaDoubleHash          │ see explanation/WARNING box at the top
//
// encode functions (for testing, converts back into serialized byte array format):
//   * encode (overloaded for each struct)
//   * encodeVaaHeader
//   * encodeVaaEnvelope
//   * encodeVaaBody
//   * encodeVaa
//   * encodeVaaAttestation<Type>

struct Vaa {
  VaaHeader   header;
  VaaEnvelope envelope;
  bytes       payload;
}

struct VaaHeader {
  uint8 version;
  bytes attestation;
}

struct VaaEnvelope {
  uint32  timestamp;
  uint32  nonce;
  uint16  emitterChainId;
  bytes32 emitterAddress;
  uint64  sequence;
  uint8   consistencyLevel;
}

//The values of VaaEssentials are considered essential because
// 1. the emitter chain and address are critical to avoid peer/message spoofing
// 2. messages that use finalized consistency levels (the vast majority) should leverage the
//  sequence number (on a per emitter basis!) and a bitmap for replay protection (rather than the
//  hashed body) because it is more gas efficient (storage slot is likely already dirty).
//
//In other words, they comprise the minimum viable set of values (for finalized VAAs only!)
//  that are required to safely identify and handle a message emitted by a peer.
struct VaaEssentials {
  uint16  emitterChainId;
  bytes32 emitterAddress;
  uint64  sequence;
  bytes   payload;
}

struct VaaBody {
  VaaEnvelope envelope;
  bytes       payload;
}

struct VaaAttestationMultiSig {
  uint32              guardianSetIndex;
  GuardianSignature[] signatures;
}

struct VaaAttestationSchnorr {
  uint32  schnorrKeyIndex;
  bytes20 r;
  bytes32 s;
}

struct VaaMultiSig {
  VaaAttestationMultiSig attestation;
  VaaEnvelope            envelope;
  bytes                  payload;
}

struct VaaSchnorr {
  VaaAttestationSchnorr  attestation;
  VaaEnvelope            envelope;
  bytes                  payload;
}

library VaaLib {
  using BytesParsing for bytes;
  using {BytesParsing.checkBound, BytesParsing.checkLength} for uint;

  error UnexpectedVersion(uint8 version);

  //see https://github.com/wormhole-foundation/wormhole/blob/c35940ae9689f6df9e983d51425763509b74a80f/ethereum/contracts/Messages.sol#L174
  //origin: https://bitcoin.stackexchange.com/a/102382
  uint8 internal constant SIGNATURE_RECOVERY_MAGIC = 27;

  uint8 public constant VERSION_MULTISIG = 1;
  uint8 public constant VERSION_SCHNORR  = 2;

  // ------------ Offsets (provided for more eclectic, manual parsing) ------------

  //VAA Header
  uint internal constant HEADER_VERSION_OFFSET = 0;
  uint internal constant HEADER_VERSION_SIZE   = 1;

  uint internal constant HEADER_ATTESTATION_OFFSET = HEADER_VERSION_OFFSET + HEADER_VERSION_SIZE;

  //MultiSig Attestation
  uint internal constant MULTISIG_GUARDIAN_SET_INDEX_OFFSET = HEADER_ATTESTATION_OFFSET;
  uint internal constant MULTISIG_GUARDIAN_SET_INDEX_SIZE   = 4;

  uint internal constant MULTISIG_SIGNATURE_COUNT_OFFSET =
    MULTISIG_GUARDIAN_SET_INDEX_OFFSET + MULTISIG_GUARDIAN_SET_INDEX_SIZE;
  uint internal constant MULTISIG_SIGNATURE_COUNT_SIZE   = 1;

  uint internal constant MULTISIG_SIGNATURE_ARRAY_OFFSET =
    MULTISIG_SIGNATURE_COUNT_OFFSET + MULTISIG_SIGNATURE_COUNT_SIZE;

  uint internal constant MULTISIG_SIGNATURE_GUARDIAN_INDEX_OFFSET = 0;
  uint internal constant MULTISIG_SIGNATURE_GUARDIAN_INDEX_SIZE   = 1;

  uint internal constant MULTISIG_SIGNATURE_R_OFFSET =
    MULTISIG_SIGNATURE_GUARDIAN_INDEX_OFFSET + MULTISIG_SIGNATURE_GUARDIAN_INDEX_SIZE;
  uint internal constant MULTISIG_SIGNATURE_R_SIZE   = 32;

  uint internal constant MULTISIG_SIGNATURE_S_OFFSET =
    MULTISIG_SIGNATURE_R_OFFSET + MULTISIG_SIGNATURE_R_SIZE;
  uint internal constant MULTISIG_SIGNATURE_S_SIZE   = 32;

  uint internal constant MULTISIG_SIGNATURE_V_OFFSET =
    MULTISIG_SIGNATURE_S_OFFSET + MULTISIG_SIGNATURE_S_SIZE;
  uint internal constant MULTISIG_SIGNATURE_V_SIZE   = 1;

  uint internal constant MULTISIG_GUARDIAN_SIGNATURE_SIZE =
    MULTISIG_SIGNATURE_GUARDIAN_INDEX_SIZE +
    MULTISIG_SIGNATURE_R_SIZE +
    MULTISIG_SIGNATURE_S_SIZE +
    MULTISIG_SIGNATURE_V_SIZE;

  //Schnorr Attestation
  uint internal constant SCHNORR_KEY_INDEX_OFFSET = HEADER_ATTESTATION_OFFSET;
  uint internal constant SCHNORR_KEY_INDEX_SIZE   = 4;

  uint internal constant SCHNORR_R_OFFSET = SCHNORR_KEY_INDEX_OFFSET + SCHNORR_KEY_INDEX_SIZE;
  uint internal constant SCHNORR_R_SIZE   = 20;

  uint internal constant SCHNORR_S_OFFSET = SCHNORR_R_OFFSET + SCHNORR_R_SIZE;
  uint internal constant SCHNORR_S_SIZE   = 32;

  uint internal constant SCHNORR_SIZE =
    SCHNORR_KEY_INDEX_SIZE + SCHNORR_R_SIZE + SCHNORR_S_SIZE;

  uint internal constant SCHNORR_ENVELOPE_OFFSET = SCHNORR_S_OFFSET + SCHNORR_S_SIZE;

  //VAA Envelope/Body
  uint internal constant ENVELOPE_TIMESTAMP_OFFSET = 0;
  uint internal constant ENVELOPE_TIMESTAMP_SIZE   = 4;

  uint internal constant ENVELOPE_NONCE_OFFSET =
    ENVELOPE_TIMESTAMP_OFFSET + ENVELOPE_TIMESTAMP_SIZE;
  uint internal constant ENVELOPE_NONCE_SIZE   = 4;

  uint internal constant ENVELOPE_EMITTER_CHAIN_ID_OFFSET =
    ENVELOPE_NONCE_OFFSET + ENVELOPE_NONCE_SIZE;
  uint internal constant ENVELOPE_EMITTER_CHAIN_ID_SIZE   = 2;

  uint internal constant ENVELOPE_EMITTER_ADDRESS_OFFSET =
    ENVELOPE_EMITTER_CHAIN_ID_OFFSET + ENVELOPE_EMITTER_CHAIN_ID_SIZE;
  uint internal constant ENVELOPE_EMITTER_ADDRESS_SIZE   = 32;

  uint internal constant ENVELOPE_SEQUENCE_OFFSET =
    ENVELOPE_EMITTER_ADDRESS_OFFSET + ENVELOPE_EMITTER_ADDRESS_SIZE;
  uint internal constant ENVELOPE_SEQUENCE_SIZE   = 8;

  uint internal constant ENVELOPE_CONSISTENCY_LEVEL_OFFSET =
    ENVELOPE_SEQUENCE_OFFSET + ENVELOPE_SEQUENCE_SIZE;
  uint internal constant ENVELOPE_CONSISTENCY_LEVEL_SIZE   = 1;

  uint internal constant ENVELOPE_SIZE =
    ENVELOPE_CONSISTENCY_LEVEL_OFFSET + ENVELOPE_CONSISTENCY_LEVEL_SIZE;

  // ------------ Convenience Decoding Functions ------------

  function decodeVaaStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (Vaa memory vaa) {
    uint offset;
    (vaa.header,   offset) = decodeVaaHeaderStructCdUnchecked(encodedVaa);
    (vaa.envelope, offset) = decodeVaaEnvelopeStructCdUnchecked(encodedVaa, offset);
    vaa.payload            = decodeVaaPayloadCd(encodedVaa, offset);
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

  //legacy decoder for CoreBridgeVM
  function decodeVmStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (CoreBridgeVM memory vm) {
    uint attestationOffset = checkVaaVersionCdUnchecked(VERSION_MULTISIG, encodedVaa);
    vm.version = VERSION_MULTISIG;

    uint envelopeOffset;
    (vm.guardianSetIndex, vm.signatures, envelopeOffset) =
      decodeVaaAttestationMultiSigCdUnchecked(encodedVaa, attestationOffset);

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

  //convenience decoding function for TokenBridge VAAs
  function decodeEmitterChainAndPayloadCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (uint16 emitterChainId, bytes calldata payload) { unchecked {
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
    uint envelopeOffset = skipVaaHeaderMemUnchecked(encodedVaa, 0);
    uint offset = envelopeOffset + ENVELOPE_EMITTER_CHAIN_ID_OFFSET;
    (emitterChainId, offset) = encodedVaa.asUint16MemUnchecked(offset);
    offset +=
      ENVELOPE_EMITTER_ADDRESS_SIZE + ENVELOPE_SEQUENCE_SIZE + ENVELOPE_CONSISTENCY_LEVEL_SIZE;
    (payload, ) = decodeVaaPayloadMemUnchecked(encodedVaa, offset, encodedVaa.length);
  }}

  // - Attestations

  function decodeVaaAttestationMultiSigCd(
    bytes calldata encodedAttestation
  ) internal pure returns (uint32 guardianSetIndex, GuardianSignature[] memory signatures) {
    uint offset;
    (guardianSetIndex, signatures, offset) =
      decodeVaaAttestationMultiSigCdUnchecked(encodedAttestation, 0);

    encodedAttestation.length.checkLength(offset);
  }

  function decodeVaaAttestationMultiSigMem(
    bytes memory encodedAttestation
  ) internal pure returns (uint32 guardianSetIndex, GuardianSignature[] memory signatures) {
    uint offset;
    (guardianSetIndex, signatures, offset) =
      decodeVaaAttestationMultiSigMemUnchecked(encodedAttestation, 0);

    encodedAttestation.length.checkLength(offset);
  }

  function decodeVaaAttestationMultiSigStructCd(
    bytes calldata encodedAttestation
  ) internal pure returns (VaaAttestationMultiSig memory attestation) {
    (attestation.guardianSetIndex, attestation.signatures) =
      decodeVaaAttestationMultiSigCd(encodedAttestation);
  }

  function decodeVaaAttestationMultiSigStructMem(
    bytes memory encodedAttestation
  ) internal pure returns (VaaAttestationMultiSig memory attestation) {
    (attestation.guardianSetIndex, attestation.signatures) =
      decodeVaaAttestationMultiSigMem(encodedAttestation);
  }

  function decodeVaaAttestationSchnorrCd(
    bytes calldata encodedAttestation
  ) internal pure returns (uint32 schnorrKeyIndex, bytes20 r, bytes32 s) {
    uint offset;
    (schnorrKeyIndex, r, s, offset) =
      decodeVaaAttestationSchnorrCdUnchecked(encodedAttestation, 0);

    encodedAttestation.length.checkLength(offset);
  }

  function decodeVaaAttestationSchnorrMem(
    bytes memory encodedAttestation
  ) internal pure returns (uint32 schnorrKeyIndex, bytes20 r, bytes32 s) {
    uint offset;
    (schnorrKeyIndex, r, s, offset) =
      decodeVaaAttestationSchnorrMemUnchecked(encodedAttestation, 0);

    encodedAttestation.length.checkLength(offset);
  }

  function decodeVaaAttestationSchnorrStructCd(
    bytes calldata encodedAttestation
  ) internal pure returns (VaaAttestationSchnorr memory attestation) {
    (attestation.schnorrKeyIndex, attestation.r, attestation.s) =
      decodeVaaAttestationSchnorrCd(encodedAttestation);
  }

  function decodeVaaAttestationSchnorrStructMem(
    bytes memory encodedAttestation
  ) internal pure returns (VaaAttestationSchnorr memory attestation) {
    (attestation.schnorrKeyIndex, attestation.r, attestation.s) =
      decodeVaaAttestationSchnorrMem(encodedAttestation);
  }

  // - Attestation specific VAAs

  function decodeVaaMultiSigStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (VaaMultiSig memory vaa) {
    uint offset = checkVaaVersionCdUnchecked(VERSION_MULTISIG, encodedVaa);
    (vaa.attestation, offset) = decodeVaaAttestationMultiSigStructCdUnchecked(encodedVaa, offset);
    (vaa.envelope,    offset) = decodeVaaEnvelopeStructCdUnchecked(encodedVaa, offset);
    vaa.payload               = decodeVaaPayloadCd(encodedVaa, offset);
  }

  function decodeVaaMultiSigStructMem(
    bytes memory encodedVaa
  ) internal pure returns (VaaMultiSig memory vaa) {
    (vaa, ) = decodeVaaMultiSigStructMemUnchecked(encodedVaa, 0, encodedVaa.length);
  }

  function decodeVaaSchnorrStructCd(
    bytes calldata encodedVaa
  ) internal pure returns (VaaSchnorr memory vaa) {
    uint offset = checkVaaVersionCdUnchecked(VERSION_SCHNORR, encodedVaa);
    (vaa.attestation, offset) = decodeVaaAttestationSchnorrStructCdUnchecked(encodedVaa, offset);
    (vaa.envelope,    offset) = decodeVaaEnvelopeStructCdUnchecked(encodedVaa, offset);
    vaa.payload               = decodeVaaPayloadCd(encodedVaa, offset);
  }

  function decodeVaaSchnorrStructMem(
    bytes memory encodedVaa
  ) internal pure returns (VaaSchnorr memory vaa) {
    (vaa, ) = decodeVaaSchnorrStructMemUnchecked(encodedVaa, 0, encodedVaa.length);
  }

  // ------------ Advanced Decoding Functions ------------

  // - Header

  function decodeVaaVersionCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (uint8 version, uint attestationOffset) {
    (version, attestationOffset) = encodedVaa.asUint8CdUnchecked(HEADER_VERSION_OFFSET);
  }

  function decodeVaaVersionMemUnchecked(
    bytes memory encoded,
    uint headerOffset
  ) internal pure returns (uint8 version, uint attestationOffset) {
    (version, attestationOffset) = encoded.asUint8MemUnchecked(headerOffset);
  }

  function checkVaaVersion(uint8 version, uint8 expected) internal pure {
    if (version != expected)
      revert UnexpectedVersion(version);
  }

  function checkVaaVersionCdUnchecked(
    uint8 expectedVersion,
    bytes calldata encodedVaa
  ) internal pure returns (uint attestationOffset) {
    uint8 version;
    (version, attestationOffset) = decodeVaaVersionCdUnchecked(encodedVaa);
    checkVaaVersion(version, expectedVersion);
  }

  function checkVaaVersionMemUnchecked(
    uint8 expectedVersion,
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint attestationOffset) {
    uint8 version;
    (version, attestationOffset) = encoded.asUint8MemUnchecked(offset);
    checkVaaVersion(version, expectedVersion);
  }

  function decodeVaaHeaderCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (
    uint8 version,
    bytes calldata attestation,
    uint envelopeOffset
  ) {
    uint attestationOffset; uint attestationSize;
    (version, attestationOffset, attestationSize) = _getHeaderMetaCdUnchecked(encodedVaa);

    (attestation, envelopeOffset) = encodedVaa.sliceCdUnchecked(attestationOffset, attestationSize);
  }

  function decodeVaaHeaderStructCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (
    VaaHeader memory header,
    uint envelopeOffset
  ) {
    (header.version, header.attestation, envelopeOffset) = decodeVaaHeaderCdUnchecked(encodedVaa);
  }

  function decodeVaaHeaderMemUnchecked(
    bytes memory encoded,
    uint headerOffset
  ) internal pure returns (
    uint8 version,
    bytes memory attestation,
    uint envelopeOffset
  ) {
    uint attestationOffset; uint attestationSize;
    (version, attestationOffset, attestationSize) =
      _getHeaderMetaMemUnchecked(encoded, headerOffset);

    (attestation, envelopeOffset) = encoded.sliceMemUnchecked(attestationOffset, attestationSize);
  }

  function decodeVaaHeaderStructMemUnchecked(
    bytes memory encoded,
    uint headerOffset
  ) internal pure returns (
    VaaHeader memory header,
    uint envelopeOffset
  ) {
    (header.version, header.attestation, envelopeOffset) =
      decodeVaaHeaderMemUnchecked(encoded, headerOffset);
  }

  function skipVaaHeaderCdUnchecked(
    bytes calldata encodedVaa
  ) internal pure returns (uint envelopeOffset) { unchecked {
    (, uint attestationOffset, uint attestationSize) = _getHeaderMetaCdUnchecked(encodedVaa);
    envelopeOffset = attestationOffset + attestationSize;
  }}

  function skipVaaHeaderMemUnchecked(
    bytes memory encoded,
    uint headerOffset
  ) internal pure returns (uint envelopeOffset) { unchecked {
    (, uint attestationOffset, uint attestationSize) =
      _getHeaderMetaMemUnchecked(encoded, headerOffset);

    envelopeOffset = attestationOffset + attestationSize;
  }}

  // - Hashing

  //see WARNING box at the top
  function calcVaaSingleHashCd(
    bytes calldata encodedVaa
  ) internal pure returns (bytes32) {
    return calcVaaSingleHashCd(encodedVaa, skipVaaHeaderCdUnchecked(encodedVaa));
  }
  function calcVaaSingleHashCd(
    bytes calldata encoded,
    uint envelopeOffset
  ) internal pure returns (bytes32) {
    return keccak256Cd(_decodeRemainderCd(encoded, envelopeOffset));
  }
  function calcVaaSingleHashMem(
    bytes memory encodedVaa
  ) internal pure returns (bytes32) { unchecked {
    uint envelopeOffset = skipVaaHeaderMemUnchecked(encodedVaa, 0);
    return calcVaaSingleHashMem(encodedVaa, envelopeOffset, encodedVaa.length);
  }}
  function calcVaaSingleHashMem(
    bytes memory encoded,
    uint envelopeOffset,
    uint vaaLength
  ) internal pure returns (bytes32) { unchecked {
    envelopeOffset.checkBound(vaaLength);
    return keccak256SliceUnchecked(encoded, envelopeOffset, vaaLength - envelopeOffset);
  }}
  function calcSingleHash(Vaa memory vaa) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(encode(vaa.envelope), vaa.payload));
  }
  function calcSingleHash(VaaMultiSig memory vaa) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(encode(vaa.envelope), vaa.payload));
  }
  function calcSingleHash(VaaSchnorr memory vaa) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(encode(vaa.envelope), vaa.payload));
  }
  function calcSingleHash(VaaBody memory body) internal pure returns (bytes32) {
    return keccak256(encode(body));
  }

  //see WARNING box at the top
  //these functions match CoreBridgeVM.hash and are what's been used for (legacy) replay protection
  function calcVaaDoubleHashCd(
    bytes calldata encodedVaa
  ) internal pure returns (bytes32) {
    return keccak256Word(calcVaaSingleHashCd(encodedVaa));
  }
  function calcVaaDoubleHashCd(
    bytes calldata encodedVaa,
    uint envelopeOffset
  ) internal pure returns (bytes32) {
    return keccak256Word(calcVaaSingleHashCd(encodedVaa, envelopeOffset));
  }
  function calcVaaDoubleHashMem(
    bytes memory encodedVaa
  ) internal pure returns (bytes32) {
    return keccak256Word(calcVaaSingleHashMem(encodedVaa));
  }
  function calcVaaDoubleHashMem(
    bytes memory encoded,
    uint envelopeOffset,
    uint vaaLength
  ) internal pure returns (bytes32) {
    return keccak256Word(calcVaaSingleHashMem(encoded, envelopeOffset, vaaLength));
  }
  function calcDoubleHash(Vaa memory vaa) internal pure returns (bytes32) {
    return keccak256Word(calcSingleHash(vaa));
  }
  function calcDoubleHash(VaaMultiSig memory vaa) internal pure returns (bytes32) {
    return keccak256Word(calcSingleHash(vaa));
  }
  function calcDoubleHash(VaaSchnorr memory vaa) internal pure returns (bytes32) {
    return keccak256Word(calcSingleHash(vaa));
  }
  function calcDoubleHash(VaaBody memory body) internal pure returns (bytes32) {
    return keccak256Word(calcSingleHash(body));
  }

  // - General structs

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
    uint envelopeOffset = skipVaaHeaderMemUnchecked(encoded, headerOffset);
    uint offset = envelopeOffset + ENVELOPE_EMITTER_CHAIN_ID_OFFSET;
    (emitterChainId, offset) = encoded.asUint16MemUnchecked(offset);
    (emitterAddress, offset) = encoded.asBytes32MemUnchecked(offset);
    (sequence,             ) = encoded.asUint64MemUnchecked(offset);

    offset = envelopeOffset + ENVELOPE_SIZE;
    (payload, offset) = decodeVaaPayloadMemUnchecked(encoded, offset, vaaLength);
    newOffset = offset;
  }}

  function decodeVaaEssentialsStructMem(
    bytes memory encodedVaa,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (VaaEssentials memory ret, uint newOffset) {
    (ret.emitterChainId, ret.emitterAddress, ret.sequence, ret.payload, newOffset) =
      decodeVaaEssentialsMem(encodedVaa, headerOffset, vaaLength);
  }

  function decodeVaaStructMemUnchecked(
    bytes memory encoded,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (Vaa memory vaa, uint newOffset) {
    uint offset;
    (vaa.header.version, vaa.header.attestation, offset) =
      decodeVaaHeaderMemUnchecked(encoded, headerOffset);

    (vaa.envelope, offset) = decodeVaaEnvelopeStructMemUnchecked(encoded, offset);
    (vaa.payload,  offset) = decodeVaaPayloadMemUnchecked(encoded, offset, vaaLength);
    newOffset = offset;
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
    uint offset = envelopeOffset;
    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, offset) =
      decodeVaaEnvelopeMemUnchecked(encoded, offset);
    (payload, offset) = decodeVaaPayloadMemUnchecked(encoded, offset, vaaLength);
    newOffset = offset;
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

  function decodeVmStructMemUnchecked(
    bytes memory encoded,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (CoreBridgeVM memory vm, uint newOffset) {
    uint offset = checkVaaVersionMemUnchecked(VERSION_MULTISIG, encoded, headerOffset);
    vm.version = VERSION_MULTISIG;

    (vm.guardianSetIndex, vm.signatures, offset) =
      decodeVaaAttestationMultiSigMemUnchecked(encoded, offset);

    vm.hash = calcVaaDoubleHashMem(encoded, offset, vaaLength);
    ( vm.timestamp,
      vm.nonce,
      vm.emitterChainId,
      vm.emitterAddress,
      vm.sequence,
      vm.consistencyLevel,
      vm.payload,
      offset
    ) = decodeVaaBodyMemUnchecked(encoded, offset, vaaLength);
    newOffset = offset;
  }

  function decodeVaaMultiSigStructMemUnchecked(
    bytes memory encoded,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (VaaMultiSig memory vaa, uint newOffset) {
    uint offset = checkVaaVersionMemUnchecked(VERSION_MULTISIG, encoded, headerOffset);
    (vaa.attestation, offset) = decodeVaaAttestationMultiSigStructMemUnchecked(encoded, offset);
    (vaa.envelope,    offset) = decodeVaaEnvelopeStructMemUnchecked(encoded, offset);
    (vaa.payload,     offset) = decodeVaaPayloadMemUnchecked(encoded, offset, vaaLength);
    newOffset = offset;
  }

  function decodeVaaSchnorrStructMemUnchecked(
    bytes memory encoded,
    uint headerOffset,
    uint vaaLength
  ) internal pure returns (VaaSchnorr memory vaa, uint newOffset) {
    uint offset = checkVaaVersionMemUnchecked(VERSION_SCHNORR, encoded, headerOffset);
    (vaa.attestation, offset) = decodeVaaAttestationSchnorrStructMemUnchecked(encoded, offset);
    (vaa.envelope,    offset) = decodeVaaEnvelopeStructMemUnchecked(encoded, offset);
    (vaa.payload,     offset) = decodeVaaPayloadMemUnchecked(encoded, offset, vaaLength);
    newOffset = offset;
  }

  // - Attestation MultiSig

  function decodeVaaAttestationMultiSigCdUnchecked(
    bytes calldata encodedVaa,
    uint attestationOffset
  ) internal pure returns (
    uint32 guardianSetIndex,
    GuardianSignature[] memory signatures,
    uint envelopeOffset
  ) { unchecked {
    uint offset = attestationOffset;
    (guardianSetIndex, offset) = encodedVaa.asUint32CdUnchecked(offset);

    uint sigCount;
    (sigCount, offset) = encodedVaa.asUint8CdUnchecked(offset);

    signatures = new GuardianSignature[](sigCount);
    for (uint i = 0; i < sigCount; ++i)
      (signatures[i], offset) = decodeGuardianSignatureStructCdUnchecked(encodedVaa, offset);

    envelopeOffset = offset;
  }}

  function decodeVaaAttestationMultiSigStructCdUnchecked(
    bytes calldata encodedVaa,
    uint attestationOffset
  ) internal pure returns (VaaAttestationMultiSig memory header, uint envelopeOffset) {
    (header.guardianSetIndex, header.signatures, envelopeOffset) =
      decodeVaaAttestationMultiSigCdUnchecked(encodedVaa, attestationOffset);
  }

  function decodeVaaAttestationMultiSigMemUnchecked(
    bytes memory encoded,
    uint attestationOffset
  ) internal pure returns (
    uint32 guardianSetIndex,
    GuardianSignature[] memory signatures,
    uint envelopeOffset
  ) { unchecked {
    uint offset = attestationOffset;
    (guardianSetIndex, offset) = encoded.asUint32MemUnchecked(offset);

    uint sigCount;
    (sigCount, offset) = encoded.asUint8MemUnchecked(offset);

    signatures = new GuardianSignature[](sigCount);
    for (uint i = 0; i < sigCount; ++i)
      (signatures[i], offset) = decodeGuardianSignatureStructMemUnchecked(encoded, offset);

    envelopeOffset = offset;
  }}

  function decodeVaaAttestationMultiSigStructMemUnchecked(
    bytes memory encoded,
    uint attestationOffset
  ) internal pure returns (VaaAttestationMultiSig memory header, uint envelopeOffset) {
    (header.guardianSetIndex, header.signatures, envelopeOffset) =
      decodeVaaAttestationMultiSigMemUnchecked(encoded, attestationOffset);
  }

  function decodeGuardianSignatureCdUnchecked(
    bytes calldata encodedVaa,
    uint offset
  ) internal pure returns (
    uint8   guardianIndex,
    bytes32 r,
    bytes32 s,
    uint8   v,
    uint    newOffset
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
    uint attestationOffset
  ) internal pure returns (GuardianSignature memory ret, uint envelopeOffset) {
    (ret.guardianIndex, ret.r, ret.s, ret.v, envelopeOffset) =
      decodeGuardianSignatureCdUnchecked(encodedVaa, attestationOffset);
  }

  function decodeGuardianSignatureMemUnchecked(
    bytes memory encoded,
    uint attestationOffset
  ) internal pure returns (
    uint8   guardianIndex,
    bytes32 r,
    bytes32 s,
    uint8   v,
    uint    envelopeOffset
  ) { unchecked {
    uint offset = attestationOffset;
    (guardianIndex, offset) = encoded.asUint8MemUnchecked(offset);
    (r,             offset) = encoded.asBytes32MemUnchecked(offset);
    (s,             offset) = encoded.asBytes32MemUnchecked(offset);
    (v,             offset) = encoded.asUint8MemUnchecked(offset);
    v += SIGNATURE_RECOVERY_MAGIC;
    envelopeOffset = offset;
  }}

  function decodeGuardianSignatureStructMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (GuardianSignature memory ret, uint newOffset) {
    (ret.guardianIndex, ret.r, ret.s, ret.v, newOffset) =
      decodeGuardianSignatureMemUnchecked(encoded, offset);
  }

  // - Attestation Schnorr

  function decodeVaaAttestationSchnorrCdUnchecked(
    bytes calldata encodedVaa,
    uint attestationOffset
  ) internal pure returns (
    uint32  schnorrKeyIndex,
    bytes20 r,
    bytes32 s,
    uint    newOffset
  ) {
    uint offset = attestationOffset;
    (schnorrKeyIndex, offset) = encodedVaa.asUint32CdUnchecked(offset);
    (r,               offset) = encodedVaa.asBytes20CdUnchecked(offset);
    (s,               offset) = encodedVaa.asBytes32CdUnchecked(offset);
    newOffset = offset;
  }

  function decodeVaaAttestationSchnorrStructCdUnchecked(
    bytes calldata encodedVaa,
    uint attestationOffset
  ) internal pure returns (VaaAttestationSchnorr memory header, uint envelopeOffset) {
    (header.schnorrKeyIndex, header.r, header.s, envelopeOffset) =
      decodeVaaAttestationSchnorrCdUnchecked(encodedVaa, attestationOffset);
  }

  function decodeVaaAttestationSchnorrMemUnchecked(
    bytes memory encoded,
    uint attestationOffset
  ) internal pure returns (
    uint32  schnorrKeyIndex,
    bytes20 r,
    bytes32 s,
    uint    envelopeOffset
  ) {
    uint offset = attestationOffset;
    (schnorrKeyIndex, offset) = encoded.asUint32MemUnchecked(offset);
    (r,               offset) = encoded.asBytes20MemUnchecked(offset);
    (s,               offset) = encoded.asBytes32MemUnchecked(offset);
    envelopeOffset = offset;
  }

  function decodeVaaAttestationSchnorrStructMemUnchecked(
    bytes memory encoded,
    uint attestationOffset
  ) internal pure returns (VaaAttestationSchnorr memory header, uint envelopeOffset) {
    (header.schnorrKeyIndex, header.r, header.s, envelopeOffset) =
      decodeVaaAttestationSchnorrMemUnchecked(encoded, attestationOffset);
  }

  // - Payload

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

  function encodeVaaHeader(
    uint8 version,
    bytes memory attestation
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(version, attestation);
  }

  function encode(VaaHeader memory val) internal pure returns (bytes memory) {
    return encodeVaaHeader(val.version, val.attestation);
  }

  function encodeVaaAttestationMultiSig(
    uint32 guardianSetIndex,
    GuardianSignature[] memory signatures
  ) internal pure returns (bytes memory) {
    bytes memory sigs;
    for (uint i = 0; i < signatures.length; ++i) {
      GuardianSignature memory sig = signatures[i];
      uint8 v = sig.v - SIGNATURE_RECOVERY_MAGIC; //deliberately checked
      sigs = bytes.concat(sigs, abi.encodePacked(sig.guardianIndex, sig.r, sig.s, v));
    }

    return abi.encodePacked(guardianSetIndex, uint8(signatures.length), sigs);
  }

  function encode(VaaAttestationMultiSig memory val) internal pure returns (bytes memory) {
    return encodeVaaAttestationMultiSig(val.guardianSetIndex, val.signatures);
  }

  function encodeVaaAttestationSchnorr(
    uint32 schnorrKeyIndex,
    bytes20 r,
    bytes32 s
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(schnorrKeyIndex, r, s);
  }

  function encode(VaaAttestationSchnorr memory val) internal pure returns (bytes memory) {
    return encodeVaaAttestationSchnorr(val.schnorrKeyIndex, val.r, val.s);
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

  function encode(VaaEnvelope memory val) internal pure returns (bytes memory) {
    return encodeVaaEnvelope(
      val.timestamp,
      val.nonce,
      val.emitterChainId,
      val.emitterAddress,
      val.sequence,
      val.consistencyLevel
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

  function encode(Vaa memory vaa) internal pure returns (bytes memory) {
    return abi.encodePacked(encode(vaa.header), encode(vaa.envelope), vaa.payload);
  }

  function encode(VaaMultiSig memory vaa) internal pure returns (bytes memory) {
    uint8 version = VERSION_MULTISIG;
    return abi.encodePacked(version, encode(vaa.attestation), encode(vaa.envelope), vaa.payload);
  }

  function encode(VaaSchnorr memory vaa) internal pure returns (bytes memory) {
    uint8 version = VERSION_SCHNORR;
    return abi.encodePacked(version, encode(vaa.attestation), encode(vaa.envelope), vaa.payload);
  }

  function encode(CoreBridgeVM memory vm) internal pure returns (bytes memory) {
    checkVaaVersion(vm.version, VERSION_MULTISIG);
    return abi.encodePacked(
      VERSION_MULTISIG,
      encodeVaaAttestationMultiSig(vm.guardianSetIndex, vm.signatures),
      vm.timestamp,
      vm.nonce,
      vm.emitterChainId,
      vm.emitterAddress,
      vm.sequence,
      vm.consistencyLevel,
      vm.payload
    );
  }

  // ------------ Private ------------

  function _getHeaderMetaCdUnchecked(
    bytes calldata encodedVaa
  ) private pure returns (
    uint8 version,
    uint attestationOffset,
    uint attestationSize
  ) { unchecked {
    (version, attestationOffset) = decodeVaaVersionCdUnchecked(encodedVaa);
    if (version == VERSION_MULTISIG) {
      uint offset = MULTISIG_SIGNATURE_COUNT_OFFSET;
      (uint sigCount, ) = encodedVaa.asUint8CdUnchecked(offset);
      attestationSize =
        MULTISIG_GUARDIAN_SET_INDEX_SIZE +
        MULTISIG_SIGNATURE_COUNT_SIZE +
        sigCount * MULTISIG_GUARDIAN_SIGNATURE_SIZE;
    }
    else if (version == VERSION_SCHNORR)
      attestationSize = SCHNORR_SIZE;
    else
      revert UnexpectedVersion(version);
  }}

  function _getHeaderMetaMemUnchecked(
    bytes memory encoded,
    uint headerOffset
  ) private pure returns (
    uint8 version,
    uint attestationOffset,
    uint attestationSize
  ) { unchecked {
    (version, attestationOffset) = decodeVaaVersionMemUnchecked(encoded, headerOffset);
    if (version == VERSION_MULTISIG) {
      uint offset = headerOffset + MULTISIG_SIGNATURE_COUNT_OFFSET;
      (uint sigCount, ) = encoded.asUint8MemUnchecked(offset);
      attestationSize =
        MULTISIG_GUARDIAN_SET_INDEX_SIZE +
        MULTISIG_SIGNATURE_COUNT_SIZE +
        sigCount * MULTISIG_GUARDIAN_SIGNATURE_SIZE;
    }
    else if (version == VERSION_SCHNORR)
      attestationSize = SCHNORR_SIZE;
    else
      revert UnexpectedVersion(version);
  }}

  //we use this function over encodedVaa[offset:] to consistently get BytesParsing errors
  //  (and because the native [] operator does a ton of pointless checks)
  function _decodeRemainderCd(
    bytes calldata encodedVaa,
    uint offset
  ) private pure returns (bytes calldata remainder) { unchecked {
    //check to avoid underflow in following subtraction
    offset.checkBound(encodedVaa.length);
    (remainder, ) = encodedVaa.sliceCdUnchecked(offset, encodedVaa.length - offset);
  }}
}

using VaaLib for Vaa global;
using VaaLib for VaaHeader global;
using VaaLib for VaaEnvelope global;
using VaaLib for VaaBody global;

using VaaLib for VaaAttestationMultiSig global;
using VaaLib for VaaAttestationSchnorr global;

using VaaLib for VaaMultiSig global;
using VaaLib for VaaSchnorr global;
