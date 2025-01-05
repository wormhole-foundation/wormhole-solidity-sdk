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
  ) {
    //The following implementation looks better on the surface, but due to the extra external
    //  function calls and having to drag the large guardian set around, it is actually more
    //  expensive than using the suboptimal verifyVM call directly.
    //
    // IWormhole iwormhole = IWormhole(wormhole);
    // ( uint32 guardianSetIndex,
    //   GuardianSignature[] memory guardianSignatures,
    //   uint envelopeOffset
    // ) = encodedVaa.decodeVaaHeaderCdUnchecked();

    // IWormhole.Signature[] memory legacySigs = VaaLib.asIWormholeSignatures(guardianSignatures);
    // IWormhole.GuardianSet memory guardianSet = iwormhole.getGuardianSet(guardianSetIndex);
    // uint expirationTime = guardianSet.expirationTime;
    // if (eagerAnd(expirationTime != 0, expirationTime < block.timestamp))
    //   //if the specified guardian set is expired, we try using the current guardian set as an adhoc
    //   //  repair attempt (there's almost certainly never more than 2 valid guardian sets at a time)
    //   guardianSet = iwormhole.getGuardianSet(iwormhole.getCurrentGuardianSetIndex());

    // bytes32 vaaHash = encodedVaa.calcVaaDoubleHashCd(envelopeOffset);
    // //see https://github.com/wormhole-foundation/wormhole/blob/1dbe8459b96e182932d0dd5ae4b6bbce6f48cb09/ethereum/contracts/Messages.sol#L111
    // (bool valid, ) = iwormhole.verifySignatures(vaaHash, legacySigs, guardianSet);

    // if (eagerOr(legacySigs.length < minSigsForQuorum(guardianSet.keys.length), !valid))
    //   revert VerificationFailed();

    // return encodedVaa.decodeVaaBodyCd(envelopeOffset);

    IWormhole.VM memory vm = encodedVaa.decodeVmStructCd();
    (bool valid, ) = IWormhole(wormhole).verifyVM(vm);

    if (!valid)
      revert VerificationFailed();

    timestamp = vm.timestamp;
    nonce = vm.nonce;
    emitterChainId = vm.emitterChainId;
    emitterAddress = vm.emitterAddress;
    sequence = vm.sequence;
    consistencyLevel = vm.consistencyLevel;
    uint payloadOffset = encodedVaa.skipVaaHeaderCd() + VaaLib.ENVELOPE_SIZE;
    (payload, ) = encodedVaa.sliceCdUnchecked(payloadOffset, encodedVaa.length - payloadOffset);
  }

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
