// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {GuardianSignature, VaaBody, VaaLib} from "wormhole-sdk/libraries/VaaLib.sol";
import {minSigsForQuorum, eagerAnd, eagerOr} from "wormhole-sdk/Utils.sol";

library CoreBridgeLib {
  using BytesParsing for bytes;
  using VaaLib for bytes;

  error VerificationFailed();

  function parseAndVerifyVaa(
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
    IWormhole iwormhole = IWormhole(wormhole);

    uint offset = VaaLib.checkVaaVersionCd(encodedVaa);
    uint32 guardianSetIndex;
    (guardianSetIndex, offset) = encodedVaa.asUint32CdUnchecked(offset);

    IWormhole.GuardianSet memory guardianSet = iwormhole.getGuardianSet(guardianSetIndex);
    uint expirationTime = guardianSet.expirationTime;
    if (eagerAnd(expirationTime != 0, expirationTime < block.timestamp))
      //if the specified guardian set is expired, we try using the current guardian set as an adhoc
      //  repair attempt (there's almost certainly never more than 2 valid guardian sets at a time)
      guardianSet = iwormhole.getGuardianSet(iwormhole.getCurrentGuardianSetIndex());

    uint signatureCount;
    (signatureCount, offset) = encodedVaa.asUint8CdUnchecked(offset);
    //this check will also handle empty guardian sets, because minSigsForQuorum(0) is 1 and so
    //  subsequent signature verification will fail
    if (signatureCount < minSigsForQuorum(guardianSet.keys.length))
      revert VerificationFailed();

    uint envelopeOffset = offset + signatureCount * VaaLib.GUARDIAN_SIGNATURE_SIZE;
    bytes32 vaaHash = encodedVaa.calcVaaDoubleHashCd(envelopeOffset);
    uint prevGuardianIndex = 0;
    uint guardianCount = guardianSet.keys.length;
    for (uint i = 0; i < signatureCount; ++i) {
      uint guardianIndex; bytes32 r; bytes32 s; uint8 v;
      (guardianIndex, r, s, v, offset) = encodedVaa.decodedGuardianSignatureCdUnchecked(offset);
      address signatory = ecrecover(vaaHash, v, r, s);
      if (eagerOr(
            eagerOr(
              !eagerOr(i == 0, guardianIndex > prevGuardianIndex),
              guardianIndex >= guardianCount
            ),
          signatory != guardianSet.keys[guardianIndex]
        ))
        revert VerificationFailed();
      prevGuardianIndex = guardianIndex;
    }

    return encodedVaa.decodeVaaBodyCd(envelopeOffset);
  }}

  function verifyHashIsGuardianSigned(
    address wormhole,
    bytes32 hash,
    GuardianSignature[] memory guardianSignatures
  ) internal view {
    IWormhole iwormhole = IWormhole(wormhole);
    IWormhole.Signature[] memory legacySigs = VaaLib.asIWormholeSignatures(guardianSignatures);
    uint32 guardianSetIndex = iwormhole.getCurrentGuardianSetIndex();
    IWormhole.GuardianSet memory guardianSet = iwormhole.getGuardianSet(guardianSetIndex);

    while (true) {
      if (legacySigs.length >= minSigsForQuorum(guardianSet.keys.length)) {
        (bool valid, ) = iwormhole.verifySignatures(hash, legacySigs, guardianSet);
        if (valid)
          return;
      }

      //check if the previous guardian set is still valid and if yes, try with that
      if (guardianSetIndex > 0) {
        guardianSet = iwormhole.getGuardianSet(--guardianSetIndex);
        if (guardianSet.expirationTime < block.timestamp)
          revert VerificationFailed();
      }
      else
        revert VerificationFailed();
    }
  }
}
