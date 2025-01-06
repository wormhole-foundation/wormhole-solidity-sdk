// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {GuardianSignature, VaaBody, VaaLib} from "wormhole-sdk/libraries/VaaLib.sol";
import {eagerAnd, eagerOr} from "wormhole-sdk/Utils.sol";

function minSigsForQuorum(uint numGuardians) pure returns (uint) { unchecked {
  return numGuardians * 2 / 3 + 1;
}}

//TODO there's further potential for gas optimization here by using assembly to skip all the
//     superflous out-of-bounds checks when accessing Solidity arrays (signatures, guardian sets)
library CoreBridgeLib {
  using BytesParsing for bytes;
  using VaaLib for bytes;

  error VerificationFailed();

  function decodeAndVerifyVaaCd(
    address wormhole,
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
    uint offset = VaaLib.checkVaaVersionCd(encodedVaa);
    uint32 guardianSetIndex;
    (guardianSetIndex, offset) = encodedVaa.asUint32CdUnchecked(offset);

    IWormhole.GuardianSet memory guardianSet = IWormhole(wormhole).getGuardianSet(guardianSetIndex);
    uint expirationTime = guardianSet.expirationTime;
    if (eagerAnd(expirationTime != 0, expirationTime < block.timestamp))
      //if the specified guardian set is expired, we try using the current guardian set as an adhoc
      //  repair attempt (there's almost certainly never more than 2 valid guardian sets at a time)
      guardianSet = IWormhole(wormhole).getGuardianSet(
        IWormhole(wormhole).getCurrentGuardianSetIndex()
      );

    uint guardianCount = guardianSet.keys.length;

    uint signatureCount;
    (signatureCount, offset) = encodedVaa.asUint8CdUnchecked(offset);
    //this check will also handle empty guardian sets, because minSigsForQuorum(0) is 1 and so
    //  subsequent signature verification will fail
    if (signatureCount < minSigsForQuorum(guardianCount))
      revert VerificationFailed();

    uint envelopeOffset = offset + signatureCount * VaaLib.GUARDIAN_SIGNATURE_SIZE;
    bytes32 vaaHash = encodedVaa.calcVaaDoubleHashCd(envelopeOffset);

    bool isFirstSignature = true; //optimization instead of always checking i == 0
    uint prevGuardianIndex;
    for (uint i = 0; i < signatureCount; ++i) {
      uint guardianIndex; bytes32 r; bytes32 s; uint8 v;
      (guardianIndex, r, s, v, offset) = encodedVaa.decodeGuardianSignatureCdUnchecked(offset);
      if (_failsVerification(
        vaaHash,
        guardianIndex,
        r,
        s,
        v,
        guardianSet.keys[guardianIndex],
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
    address wormhole,
    bytes memory encodedVaa
  ) internal view returns (
    uint32  timestamp,
    uint32  nonce,
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    uint8   consistencyLevel,
    bytes memory payload
  ) { unchecked {
    uint offset = VaaLib.checkVaaVersionMemUnchecked(encodedVaa, 0);
    uint32 guardianSetIndex;
    (guardianSetIndex, offset) = encodedVaa.asUint32MemUnchecked(offset);

    IWormhole.GuardianSet memory guardianSet = IWormhole(wormhole).getGuardianSet(guardianSetIndex);
    uint expirationTime = guardianSet.expirationTime;
    if (eagerAnd(expirationTime != 0, expirationTime < block.timestamp))
      //if the specified guardian set is expired, we try using the current guardian set as an adhoc
      //  repair attempt (there's almost certainly never more than 2 valid guardian sets at a time)
      guardianSet = IWormhole(wormhole).getGuardianSet(
        IWormhole(wormhole).getCurrentGuardianSetIndex()
      );

    uint guardianCount = guardianSet.keys.length;

    uint signatureCount;
    (signatureCount, offset) = encodedVaa.asUint8MemUnchecked(offset);
    //this check will also handle empty guardian sets, because minSigsForQuorum(0) is 1 and so
    //  subsequent signature verification will fail
    if (signatureCount < minSigsForQuorum(guardianCount))
      revert VerificationFailed();

    uint envelopeOffset = offset + signatureCount * VaaLib.GUARDIAN_SIGNATURE_SIZE;
    bytes32 vaaHash = encodedVaa.calcVaaDoubleHashMem(envelopeOffset, encodedVaa.length);

    bool isFirstSignature = true; //optimization instead of always checking i == 0
    uint prevGuardianIndex;
    for (uint i = 0; i < signatureCount; ++i) {
      uint guardianIndex; bytes32 r; bytes32 s; uint8 v;
      (guardianIndex, r, s, v, offset) = encodedVaa.decodeGuardianSignatureMemUnchecked(offset);
      if (_failsVerification(
        vaaHash,
        guardianIndex,
        r,
        s,
        v,
        guardianSet.keys[guardianIndex],
        guardianCount,
        prevGuardianIndex,
        isFirstSignature
      ))
        revert VerificationFailed();

      prevGuardianIndex = guardianIndex;
      isFirstSignature = false;
    }

    (timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payload, ) =
      encodedVaa.decodeVaaBodyMemUnchecked(envelopeOffset, encodedVaa.length);
  }}

  function isVerifiedByQuorum(
    address wormhole,
    bytes32 hash,
    GuardianSignature[] memory guardianSignatures
  ) internal view returns (bool) { unchecked {
    IWormhole.Signature[] memory legacySigs = VaaLib.asIWormholeSignatures(guardianSignatures);
    uint signatureCount = legacySigs.length; //optimization
    uint32 guardianSetIndex = IWormhole(wormhole).getCurrentGuardianSetIndex();
    IWormhole.GuardianSet memory guardianSet = IWormhole(wormhole).getGuardianSet(guardianSetIndex);
    while (true) {
      address[] memory guardians = guardianSet.keys; //optimization puts pointer on stack
      uint guardianCount = guardians.length; //optimization puts var on stack
      bool isFirstSignature = true; //optimization instead of always checking i == 0
      uint prevGuardianIndex;
      if (signatureCount >= minSigsForQuorum(guardianCount)) {
        bool valid = true;
        for (uint i = 0; i < signatureCount; ++i) {
          IWormhole.Signature memory sig = legacySigs[i];
          if (_failsVerification(
            hash,
            sig.guardianIndex,
            sig.r,
            sig.s,
            sig.v,
            guardians[sig.guardianIndex],
            guardianCount,
            prevGuardianIndex,
            isFirstSignature
          )) {
            valid = false;
            break;
          }

          prevGuardianIndex = sig.guardianIndex;
          isFirstSignature = false;
        }
        if (valid)
          return true;
      }

      if (guardianSetIndex == 0)
        break;

      //check if the previous guardian set is still valid and if yes, try with that
      guardianSet = IWormhole(wormhole).getGuardianSet(--guardianSetIndex);
      if (guardianSet.expirationTime < block.timestamp)
        break;
    }
    return false;
  }}

  //negated for optimization because we always want to act on incorrect signatures and so save a NOT
  function _failsVerification(
    bytes32 hash,
    uint guardianIndex,
    bytes32 r,
    bytes32 s,
    uint8 v,
    address guardian,
    uint guardianCount,
    uint prevGuardianIndex,
    bool isFirstSignature
  ) private pure returns (bool) {
    address signatory = ecrecover(hash, v, r, s);
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
}
