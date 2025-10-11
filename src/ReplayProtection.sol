// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import {keccak256Word} from "wormhole-sdk/Utils.sol";
import {VaaLib} from "wormhole-sdk/libraries/VaaLib.sol";

//TODO
library ReplayProtectionLib {
  error AlreadyProcessed();

  //keccak256("WormholeReplayProtection")
  uint256 constant _REPLAY_PROTECTION_SALT =
    0x451e1cdd759c032e4b76c22f1e318ddd04a5b1d6ffcbd3f32c8e0770c6ecdf59;

  function replayProtectFinalized(
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence
  ) internal { unchecked {
    //using a hash of the chainId avoids potential collisions for chains where emitter addresses
    //  aren't hash based
    bytes32 chainIdHash = keccak256Word(bytes32(uint(emitterChainId)));
    uint baseSlot = uint(keccak256Word(bytes32(
      _REPLAY_PROTECTION_SALT ^ uint(chainIdHash) ^ uint(emitterAddress)
    )));
    uint bit = uint8(sequence);
    uint slotOffset = sequence >> 8;
    uint storageSlot = baseSlot + slotOffset;

    uint current;
    assembly ("memory-safe") { current := sload(storageSlot) }

    uint updated = current | (1 << bit);

    if (current == updated)
      revert AlreadyProcessed();

    assembly ("memory-safe") { sstore(storageSlot, updated) }
  }}

  //WARNING: The VAA hash here is the single-hashed envelope, which is the canonical VAA hash.
  //         The CoreBridge's VM.hash value is doubly hashed (see warning box in VaaLib.sol).
  function replayProtectNonFinalized(
    bytes calldata encodedVaa
  ) internal {
    bytes32 vaaSingleHash = VaaLib.calcVaaSingleHashCd(encodedVaa);
    uint storageSlot = _REPLAY_PROTECTION_SALT ^ uint(vaaSingleHash);
    uint slotContent;
    assembly ("memory-safe") { slotContent := sload(storageSlot) }

    if (slotContent != 0)
      revert AlreadyProcessed();

    assembly ("memory-safe") { sstore(storageSlot, 1) }
  }
}