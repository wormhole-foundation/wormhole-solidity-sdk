// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import {
  ICoreBridge,
  GuardianSignature,
  GuardianSet}             from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {WORD_SIZE}         from "wormhole-sdk/constants/Common.sol";
import {BytesParsing}      from "wormhole-sdk/libraries/BytesParsing.sol";
import {UncheckedIndexing} from "wormhole-sdk/libraries/UncheckedIndexing.sol";
import {VaaBody, VaaLib}   from "wormhole-sdk/libraries/VaaLib.sol";
import {eagerAnd, eagerOr} from "wormhole-sdk/Utils.sol";

// ╭────────────────────────────────────────────────────────────────────────────────────────╮
// │ Library for "client-side" parsing and verification of VAAs / Guardian signed messages. │
// ╰────────────────────────────────────────────────────────────────────────────────────────╯
//
// Offers significant gas savings over calling the CoreBridge due to:
//  * its much more efficient implementation
//  * by avoiding external call encoding and decoding overheads
// Comes at the expense of larger contract bytecode.
//
// When verifying a single VAA, decodeAndVerifyVaaCd is maximally gas efficient.
// However, when verifying multiple VAAs/signed messages, the most gas efficient choice is to do
//   some manual parsing (e.g. by directly using VaaLib) and to explicitly fetch the guardian set
//   (which is very likely to be the same for all messages) via `getGuardiansOrEmpty` or
//   `getGuardiansOrLatest` and reuse it, rather than to look it up again and again, as a call
//   to decodeAndVerifyVaaCd would do.
//
// Function Overview:
//  * decodeAndVerifyVaa: Cd and Mem variants for verifying a VAA and decoding/returning its body
//  * isVerifiedByQuorum: 2x2=4 variants for verifying a hash (directly passed to ecrecover):
//    * Cd <> Mem
//    * guardianSetIndex:
//      - fetches the guardian set from the CoreBridge with a fallback to the latest guardian set
//          if the specified one is expired as an ad-hoc repair attempt
//    * guardianAddresses:
//      - only tries to verify against the provided guardian addresses, no fallback
//  * readUnchecked: Cd and Mem variants for unchecked index access into a GuardianSignature array
//  * minSigsForQuorum

library CoreBridgeLib {
  using UncheckedIndexing for address[];
  using BytesParsing for bytes;
  using VaaLib for bytes;

  //avoid solc error:
  //Only direct number constants and references to such constants are supported by inline assembly.
  uint internal constant GUARDIAN_SIGNATURE_STRUCT_SIZE = 128; //4 * WORD_SIZE;

  error VerificationFailed();

  function minSigsForQuorum(uint numGuardians) internal pure returns (uint) { unchecked {
    return numGuardians * 2 / 3 + 1;
  }}

  //skip out-of-bounds checks by using assembly
  function readUncheckedCd(
    GuardianSignature[] calldata arr,
    uint i
  ) internal pure returns (GuardianSignature calldata ret) {
    assembly ("memory-safe") {
      ret := add(arr.offset, mul(i, GUARDIAN_SIGNATURE_STRUCT_SIZE))
    }
  }

  function readUncheckedMem(
    GuardianSignature[] memory arr,
    uint i
  ) internal pure returns (GuardianSignature memory ret) {
    assembly ("memory-safe") {
      ret := mload(add(add(arr, WORD_SIZE), mul(i, WORD_SIZE)))
    }
  }

  //this function is the most efficient choice when verifying multiple messages because it allows
  //  library users to reuse the same guardian set for multiple messages (thus avoiding redundant
  //  external calls and the associated allocations and checks)
  function isVerifiedByQuorumCd(
    bytes32 hash,
    GuardianSignature[] calldata guardianSignatures,
    address[] memory guardians
  ) internal pure returns (bool) { unchecked {
    uint guardianCount = guardians.length;
    uint signatureCount = guardianSignatures.length; //optimization puts var on stack
    if (signatureCount < minSigsForQuorum(guardianCount))
      return false;

    bool isFirstSignature = true; //optimization instead of always checking i == 0
    uint prevGuardianIndex;
    for (uint i = 0; i < signatureCount; ++i) {
      GuardianSignature memory sig = readUncheckedCd(guardianSignatures, i);
      uint guardianIndex = sig.guardianIndex;
      if (_failsVerification(
        hash,
        guardianIndex,
        sig.r, sig.s, sig.v,
        guardians,
        guardianCount,
        prevGuardianIndex,
        isFirstSignature
      ))
        return false;

      prevGuardianIndex = guardianIndex;
      isFirstSignature = false;
    }
    return true;
  }}

  function isVerifiedByQuorumMem(
    bytes32 hash,
    GuardianSignature[] memory guardianSignatures,
    address[] memory guardians
  ) internal pure returns (bool) { unchecked {
    uint guardianCount = guardians.length;
    uint signatureCount = guardianSignatures.length; //optimization puts var on stack
    if (signatureCount < minSigsForQuorum(guardianCount))
      return false;

    bool isFirstSignature = true; //optimization instead of always checking i == 0
    uint prevGuardianIndex;
    for (uint i = 0; i < signatureCount; ++i) {
      GuardianSignature memory sig = readUncheckedMem(guardianSignatures, i);
      uint guardianIndex = sig.guardianIndex;
      if (_failsVerification(
        hash,
        guardianIndex,
        sig.r, sig.s, sig.v,
        guardians,
        guardianCount,
        prevGuardianIndex,
        isFirstSignature
      ))
        return false;

      prevGuardianIndex = guardianIndex;
      isFirstSignature = false;
    }
    return true;
  }}

  function decodeAndVerifyVaaCd(
    address coreBridge,
    bytes calldata encodedVaa
  ) internal view returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes calldata payload
  ) { unchecked {
    uint offset = VaaLib.checkVaaVersionCdUnchecked(VaaLib.VERSION_MULTISIG, encodedVaa);

    uint32 guardianSetIndex;
    (guardianSetIndex, offset) = encodedVaa.asUint32CdUnchecked(offset);

    address[] memory guardians = getGuardiansOrLatest(coreBridge, guardianSetIndex);
    uint guardianCount = guardians.length; //optimization puts var on stack thus avoids mload
    uint signatureCount;
    (signatureCount, offset) = encodedVaa.asUint8CdUnchecked(offset);
    //this check will also handle empty guardian sets, because minSigsForQuorum(0) is 1 and so
    //  subsequent signature verification will fail
    if (signatureCount < minSigsForQuorum(guardianCount))
      revert VerificationFailed();

    uint envelopeOffset = offset + signatureCount * VaaLib.MULTISIG_GUARDIAN_SIGNATURE_SIZE;
    bytes32 vaaHash = encodedVaa.calcVaaDoubleHashCd(envelopeOffset);

    bool isFirstSignature = true; //optimization instead of always checking i == 0
    uint prevGuardianIndex;
    for (uint i = 0; i < signatureCount; ++i) {
      uint guardianIndex; bytes32 r; bytes32 s; uint8 v;
      (guardianIndex, r, s, v, offset) = encodedVaa.decodeGuardianSignatureCdUnchecked(offset);
      if (_failsVerification(
        vaaHash,
        guardianIndex,
        r, s, v,
        guardians,
        guardianCount,
        prevGuardianIndex,
        isFirstSignature
      ))
        revert VerificationFailed();

      prevGuardianIndex = guardianIndex;
      isFirstSignature = false;
    }

    return encodedVaa.decodeVaaBodyCd(envelopeOffset);
  }}

  function decodeAndVerifyVaaMem(
    address coreBridge,
    bytes memory encodedVaa
  ) internal view returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes memory payload
  ) {
    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payload, ) =
      decodeAndVerifyVaaMem(coreBridge, encodedVaa, 0, encodedVaa.length);
  }

  function decodeAndVerifyVaaMem(
    address coreBridge,
    bytes memory encodedVaa,
    uint offset,
    uint vaaLength
  ) internal view returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes memory payload,
    uint    newOffset
  ) { unchecked {
    offset = VaaLib.checkVaaVersionMemUnchecked(VaaLib.VERSION_MULTISIG, encodedVaa, offset);

    uint32 guardianSetIndex;
    (guardianSetIndex, offset) = encodedVaa.asUint32MemUnchecked(offset);

    address[] memory guardians = getGuardiansOrLatest(coreBridge, guardianSetIndex);
    uint guardianCount = guardians.length;

    uint signatureCount;
    (signatureCount, offset) = encodedVaa.asUint8MemUnchecked(offset);
    //this check will also handle empty guardian sets, because minSigsForQuorum(0) is 1 and so
    //  subsequent signature verification will fail
    if (signatureCount < minSigsForQuorum(guardianCount))
      revert VerificationFailed();

    uint envelopeOffset = offset + signatureCount * VaaLib.MULTISIG_GUARDIAN_SIGNATURE_SIZE;
    bytes32 vaaHash = encodedVaa.calcVaaDoubleHashMem(envelopeOffset, vaaLength);

    bool isFirstSignature = true; //optimization instead of always checking i == 0
    uint prevGuardianIndex;
    for (uint i = 0; i < signatureCount; ++i) {
      uint guardianIndex; bytes32 r; bytes32 s; uint8 v;
      (guardianIndex, r, s, v, offset) = encodedVaa.decodeGuardianSignatureMemUnchecked(offset);
      if (_failsVerification(
        vaaHash,
        guardianIndex,
        r, s, v,
        guardians,
        guardianCount,
        prevGuardianIndex,
        isFirstSignature
      ))
        revert VerificationFailed();

      prevGuardianIndex = guardianIndex;
      isFirstSignature = false;
    }

    ( timestamp,
      nonce,
      emitterChainId,
      emitterAddress,
      sequence,
      consistencyLevel,
      payload,
      newOffset
    ) = encodedVaa.decodeVaaBodyMemUnchecked(envelopeOffset, vaaLength);
  }}

  function isVerifiedByQuorumCd(
    address coreBridge,
    bytes32 hash,
    GuardianSignature[] calldata guardianSignatures,
    uint32 guardianSetIndex
  ) internal view returns (bool) {
    address[] memory guardians = getGuardiansOrLatest(coreBridge, guardianSetIndex);
    return isVerifiedByQuorumCd(hash, guardianSignatures, guardians);
  }

  function isVerifiedByQuorumMem(
    address coreBridge,
    bytes32 hash,
    GuardianSignature[] memory guardianSignatures,
    uint32 guardianSetIndex
  ) internal view returns (bool) {
    address[] memory guardians = getGuardiansOrLatest(coreBridge, guardianSetIndex);
    return isVerifiedByQuorumMem(hash, guardianSignatures, guardians);
  }

  //returns empty array if the guardian set is expired or does not exist
  //has more predictable gas costs (guaranteed to only do one external call)
  function getGuardiansOrEmpty(
    address coreBridge,
    uint32 guardianSetIndex
  ) internal view returns (address[] memory guardians) {
    GuardianSet memory guardianSet = ICoreBridge(coreBridge).getGuardianSet(guardianSetIndex);
    if (!_isExpired(guardianSet))
      guardians = guardianSet.keys;
  }

  //returns associated guardian set or latest guardian set if the specified one is expired
  //returns empty array if the guardian set does not exist
  //has more variable gas costs but has a chance of doing an ad-hoc "repair" of the VAA in case
  //  the specified signatures are valid for the latest guardian set as well (about a 30 % chance
  //  for the typical guardian set rotation where one guardian address gets replaced).
  function getGuardiansOrLatest(
    address coreBridge,
    uint32 guardianSetIndex
  ) internal view returns (address[] memory guardians) {
    GuardianSet memory guardianSet = ICoreBridge(coreBridge).getGuardianSet(guardianSetIndex);
    if (_isExpired(guardianSet))
      //if the specified guardian set is expired, we try using the current guardian set as an adhoc
      //  repair attempt (there's almost certainly never more than 2 valid guardian sets at a time)
      guardianSet = ICoreBridge(coreBridge).getGuardianSet(
        ICoreBridge(coreBridge).getCurrentGuardianSetIndex()
      );

    guardians = guardianSet.keys;
  }

  //negated for optimization because we always want to act on incorrect signatures and so save a NOT
  function _failsVerification(
    bytes32 hash,
    uint guardianIndex,
    bytes32 r,
    bytes32 s,
    uint8 v,
    address[] memory guardians,
    uint guardianCount,
    uint prevGuardianIndex,
    bool isFirstSignature
  ) private pure returns (bool) {
    address signatory = ecrecover(hash, v, r, s);
    address guardian = guardians.readUnchecked(guardianIndex);
    //check that:
    // * the guardian indicies are in strictly ascending order (only after the first signature)
    //     this is itself an optimization to efficiently prevent having the same guardian signature
    //     included twice
    // * that the guardian index is not out of bounds
    // * that the signatory is the guardian
    //
    // the core bridge also includes a separate check that signatory is not the zero address
    //   but this is already covered by comparing that the signatory matches the guardian which
    //   [can never be the zero address](https://github.com/wormhole-foundation/wormhole/blob/1dbe8459b96e182932d0dd5ae4b6bbce6f48cb09/ethereum/contracts/Setters.sol#L20)
    return eagerOr(
      eagerOr(
        !eagerOr(isFirstSignature, guardianIndex > prevGuardianIndex),
        guardianIndex >= guardianCount
      ),
      signatory != guardian
    );
  }

  function _isExpired(GuardianSet memory guardianSet) private view returns (bool) {
    uint expirationTime = guardianSet.expirationTime;
    return eagerAnd(expirationTime != 0, expirationTime < block.timestamp);
  }
}
