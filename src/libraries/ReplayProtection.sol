// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import {keccak256Word} from "wormhole-sdk/Utils.sol";
import {VaaLib} from "wormhole-sdk/libraries/VaaLib.sol";

// ╭──────────────────────────────────────────────────────╮
// │ Libraries for implementing replay protection of VAAs │
// ╰──────────────────────────────────────────────────────╯

//Two approaches to replay protection:
// 1. Sequence-based (per chain+emitter combination)
//    Must only be used for VAAs published with the finalized consistency level (the default case)
//    Implemented via a bitmap. Reduces gas cost of replay protection by almost 75 %
//      (writing to a clean storage slot = 20k gas, writing to a dirty one = 5k gas)
// 2. Hash-based
//    Can be used for all consistency levels. Less efficient because it always writes to a clean
//      storage slot.
//    The hash-based implementation here uses the canonical VAA hash, which is _NOT_ what the
//      CoreBridge returns in VM.hash. See WARNING box at the top of VaaLib.sol for details.
//
//Both libraries use assembly to directly access contract storage.

//keccak256("WormholeReplayProtection")
uint256 constant _REPLAY_PROTECTION_SALT =
  0x451e1cdd759c032e4b76c22f1e318ddd04a5b1d6ffcbd3f32c8e0770c6ecdf59;

error AlreadyProcessed();

//WARNING: Only use for VAAs with finalized consistency level!
library SequenceReplayProtectionLib {
  function replayProtect(
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence
  ) internal {
    (uint storageSlot, uint slotContent, uint bitMask) =
      _get(emitterChainId, emitterAddress, sequence);

    uint updated = slotContent | bitMask;

    if (slotContent == updated)
      revert AlreadyProcessed();

    assembly ("memory-safe") { sstore(storageSlot, updated) }
  }

  function isReplayProtected(
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence
  ) internal view returns (bool) {
    (, uint slotContent, uint bitMask) = _get(emitterChainId, emitterAddress, sequence);
    return slotContent & bitMask != 0;
  }

  function _get(
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence
  ) private view returns (uint storageSlot, uint slotContent, uint bitMask) { unchecked {
    //using a hash of the chainId avoids potential collisions for chains where emitter addresses
    //  aren't hash based
    bytes32 chainIdHash = keccak256Word(bytes32(uint(emitterChainId)));
    uint baseSlot = uint(keccak256Word(bytes32(
      _REPLAY_PROTECTION_SALT ^ uint(chainIdHash) ^ uint(emitterAddress)
    )));
    uint slotOffset = sequence >> 8;
    storageSlot = baseSlot + slotOffset;
    bitMask = 1 << uint(uint8(sequence));
    assembly ("memory-safe") { slotContent := sload(storageSlot) }
  }}
}

library HashReplayProtectionLib {
  //WARNING:
  //The VAA hash used here is the single-hashed envelope, which is the canonical VAA hash.
  //The CoreBridge's VM.hash value is doubly hashed (hash of hash) (see warning box in VaaLib.sol).

  function replayProtect(bytes32 vaaHash) internal {
    (uint storageSlot, uint slotContent) = _get(vaaHash);

    if (slotContent != 0)
      revert AlreadyProcessed();

    assembly ("memory-safe") { sstore(storageSlot, 1) }
  }

  function isReplayProtected(bytes32 vaaHash) internal view returns (bool) {
    (, uint slotContent) = _get(vaaHash);
    return slotContent != 0;
  }

  function replayProtect(bytes calldata encodedVaa) internal {
    replayProtect(VaaLib.calcVaaSingleHashCd(encodedVaa));
  }

  function isReplayProtected(bytes calldata encodedVaa) internal view returns (bool) {
    return isReplayProtected(VaaLib.calcVaaSingleHashCd(encodedVaa));
  }

  function _get(bytes32 vaaHash) private view returns (uint storageSlot, uint slotContent) {
    storageSlot = _REPLAY_PROTECTION_SALT ^ uint(vaaHash);
    assembly ("memory-safe") { slotContent := sload(storageSlot) }
  }
}
