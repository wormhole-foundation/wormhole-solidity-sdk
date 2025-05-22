// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

// ╭────────────────────────────────────────────────────╮
// │ For verification, consider using `CoreBridgeLib`   │
// │ For encoding and decoding, consider using `VaaLib` │
// ╰────────────────────────────────────────────────────╯

//slimmed down interface of the CoreBridge (aka the Wormhole contract)

struct GuardianSet {
  address[] keys;
  uint32 expirationTime;
}

struct GuardianSignature {
  bytes32 r;
  bytes32 s;
  uint8 v;
  uint8 guardianIndex;
}

//VM = Verified Message - legacy struct of the core bridge
//contains fields that are not relevant to the integrator:
// * version - always 1 regardless
// * signatures/guardianSetIndex - only the core bridge itself cares for verification
// * hash - _finalized_ VAAs should use the unique (emitterChainId, emitterAddress, sequence) triple
//           for cheaper replay protection
struct CoreBridgeVM {
  uint8 version;
  uint32 timestamp;
  uint32 nonce;
  uint16 emitterChainId;
  bytes32 emitterAddress;
  uint64 sequence;
  uint8 consistencyLevel;
  bytes payload;
  uint32 guardianSetIndex;
  GuardianSignature[] signatures;
  bytes32 hash;
}

interface ICoreBridge {
  event LogMessagePublished(
    address indexed sender,
    uint64 sequence,
    uint32 nonce,
    bytes payload,
    uint8 consistencyLevel
  );

  // -- publishing --

  function messageFee() external view returns (uint256);

  //Note: This function requires a msg.value equal to the message fee!
  function publishMessage(
    uint32 nonce,
    bytes memory payload,
    uint8 consistencyLevel
  ) external payable returns (uint64 sequence);

  // -- verification --

  //consider using `VaaLib` and `CoreBridgeLib` instead to save on gas
  //  (though at the expense of some code size)
  function parseAndVerifyVM(
    bytes calldata encodedVM
  ) external view returns (CoreBridgeVM memory vm, bool valid, string memory reason);

  // -- getters --

  function chainId() external view returns (uint16);
  function nextSequence(address emitter) external view returns (uint64);

  function getGuardianSet(uint32 index) external view returns (GuardianSet memory);
  function getCurrentGuardianSetIndex() external view returns (uint32);
}
