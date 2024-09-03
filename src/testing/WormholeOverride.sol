// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";

import {VM_ADDRESS, DEVNET_GUARDIAN_PRIVATE_KEY} from "./Constants.sol";
import "./LogUtils.sol";

struct PublishedMessage {
  uint32 timestamp;
  uint16 emitterChainId;
  bytes32 emitterAddress;
  uint64 sequence;
  uint32 nonce;
  uint8 consistencyLevel;
  bytes payload;
}

//create fake VAAs for forge tests
library WormholeOverride {
  using { toUniversalAddress } for address;
  using BytesParsing for bytes;
  using LogUtils for Vm.Log[];

  Vm constant vm = Vm(VM_ADDRESS);

  // keccak256("devnetGuardianPrivateKey") - 1
  bytes32 private constant _DEVNET_GUARDIAN_PK_SLOT =
    0x4c7087e9f1bf599f9f9fff4deb3ecae99b29adaab34a0f53d9fa9d61aeaecb63;

  uint32  constant DEFAULT_NONCE = 0xBBBBBBBB;
  uint8   constant DEFAULT_CONSISTENCY_LEVEL = 1;
  uint8   constant WORMHOLE_VAA_VERSION = 1;
  uint16  constant GOVERNANCE_CHAIN_ID = 1;
  bytes32 constant GOVERNANCE_CONTRACT = bytes32(uint256(4));

  function setUpOverride(IWormhole wormhole) internal {
    setUpOverride(wormhole, DEVNET_GUARDIAN_PRIVATE_KEY);
  }

  function setUpOverride(IWormhole wormhole, uint256 signer) internal { unchecked {
    if (guardianPrivateKey(wormhole) == signer)
      return;

    require(guardianPrivateKey(wormhole) == 0, "WormholeOverride: already set up");

    address devnetGuardian = vm.addr(signer);

    // Get slot for Guardian Set at the current index
    uint32 guardianSetIndex = wormhole.getCurrentGuardianSetIndex();
    bytes32 guardianSetSlot = keccak256(abi.encode(guardianSetIndex, 2));

    // Overwrite all but first guardian set to zero address. This isn't
    // necessary, but just in case we inadvertently access these slots
    // for any reason.
    uint256 numGuardians = uint256(vm.load(address(wormhole), guardianSetSlot));
    for (uint256 i = 1; i < numGuardians; ++i)
      vm.store(
        address(wormhole),
        bytes32(uint256(keccak256(abi.encodePacked(guardianSetSlot))) + i),
        0
      );

    // Now overwrite the first guardian key with the devnet key specified
    // in the function argument.
    vm.store(
      address(wormhole),
      bytes32(uint256(keccak256(abi.encodePacked(guardianSetSlot))) + 0), //just explicit w/ index 0
      devnetGuardian.toUniversalAddress()
    );

    // Change the length to 1 guardian
    vm.store(
        address(wormhole),
        guardianSetSlot,
        bytes32(uint256(1)) // length == 1
    );

    // Confirm guardian set override
    address[] memory guardians = wormhole.getGuardianSet(guardianSetIndex).keys;
    assert(guardians.length == 1 && guardians[0] == devnetGuardian);

    // Now do something crazy. Save the private key in a specific slot of Wormhole's storage for
    // retrieval later.
    vm.store(address(wormhole), _DEVNET_GUARDIAN_PK_SLOT, bytes32(signer));
  }}

  function guardianPrivateKey(IWormhole wormhole) internal view returns (uint256 pk) {
    pk = uint256(vm.load(address(wormhole), _DEVNET_GUARDIAN_PK_SLOT));
  }

  function fetchPublishedMessages(
    IWormhole wormhole,
    Vm.Log[] memory logs
  ) internal view returns (PublishedMessage[] memory ret) { unchecked {
    Vm.Log[] memory pmLogs = logs.filter(
      address(wormhole),
      keccak256("LogMessagePublished(address,uint64,uint32,bytes,uint8)")
    );

    ret = new PublishedMessage[](pmLogs.length);
    for (uint i; i < pmLogs.length; ++i) {
      ret[i].emitterAddress = pmLogs[i].topics[1];
      (ret[i].sequence, ret[i].nonce, ret[i].payload, ret[i].consistencyLevel) =
        abi.decode(pmLogs[i].data, (uint64, uint32, bytes, uint8));
      ret[i].timestamp = uint32(block.timestamp);
      ret[i].emitterChainId = wormhole.chainId();
    }
  }}

  function sign(
    IWormhole wormhole,
    PublishedMessage memory pm
  ) internal view returns (IWormhole.VM memory vaa, bytes memory encoded) {
    vaa.version = WORMHOLE_VAA_VERSION;
    vaa.timestamp = pm.timestamp;
    vaa.nonce = pm.nonce;
    vaa.emitterChainId = pm.emitterChainId;
    vaa.emitterAddress = pm.emitterAddress;
    vaa.sequence = pm.sequence;
    vaa.consistencyLevel = pm.consistencyLevel;
    vaa.payload = pm.payload;

    bytes memory encodedBody = abi.encodePacked(
      pm.timestamp,
      pm.nonce,
      pm.emitterChainId,
      pm.emitterAddress,
      pm.sequence,
      pm.consistencyLevel,
      pm.payload
    );
    vaa.hash = keccak256(abi.encodePacked(keccak256(encodedBody)));

    vaa.signatures = new IWormhole.Signature[](1);
    (vaa.signatures[0].v, vaa.signatures[0].r, vaa.signatures[0].s) =
      vm.sign(guardianPrivateKey(wormhole), vaa.hash);
    vaa.signatures[0].v -= 27;

    encoded = abi.encodePacked(
      vaa.version,
      wormhole.getCurrentGuardianSetIndex(),
      uint8(vaa.signatures.length),
      vaa.signatures[0].guardianIndex,
      vaa.signatures[0].r,
      vaa.signatures[0].s,
      vaa.signatures[0].v,
      encodedBody
    );
  }

  function craftVaa(
    IWormhole wormhole,
    uint16 emitterChain,
    bytes32 emitterAddress,
    uint64 sequence,
    bytes memory payload
  ) internal view returns (IWormhole.VM memory vaa, bytes memory encoded) {
    PublishedMessage memory pm = PublishedMessage({
      timestamp: uint32(block.timestamp),
      nonce: DEFAULT_NONCE,
      emitterChainId: emitterChain,
      emitterAddress: emitterAddress,
      sequence: sequence,
      consistencyLevel: DEFAULT_CONSISTENCY_LEVEL,
      payload: payload
    });

    (vaa, encoded) = sign(wormhole, pm);
  }

  function craftGovernanceVaa(
    IWormhole wormhole,
    bytes32 module,
    uint8 action,
    uint16 targetChain,
    uint64 sequence,
    bytes memory decree
  ) internal view returns (IWormhole.VM memory vaa, bytes memory encoded) {
    (vaa, encoded) = craftGovernanceVaa(
      wormhole,
      GOVERNANCE_CHAIN_ID,
      GOVERNANCE_CONTRACT,
      module,
      action,
      targetChain,
      sequence,
      decree
    );
  }

  function craftGovernanceVaa(
    IWormhole wormhole,
    uint16 governanceChain,
    bytes32 governanceContract,
    bytes32 module,
    uint8 action,
    uint16 targetChain,
    uint64 sequence,
    bytes memory decree
  ) internal view returns (IWormhole.VM memory vaa, bytes memory encoded) {
    (vaa, encoded) = craftVaa(
      wormhole,
      governanceChain,
      governanceContract,
      sequence,
      abi.encodePacked(module, action, targetChain, decree)
    );
  }
}
