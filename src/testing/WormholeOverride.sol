// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";

import {VM_ADDRESS} from "./Constants.sol";
import "./LogUtils.sol";

//┌────────────────────────────────────────────────────────────────────────────────────────────────┐
//│ take control of the core bridge in forge fork tests to generate VAAs and test message emission │
//└────────────────────────────────────────────────────────────────────────────────────────────────┘

struct PublishedMessage {
  uint32 timestamp;
  uint16 emitterChainId;
  bytes32 emitterAddress;
  uint64 sequence;
  uint32 nonce;
  uint8 consistencyLevel;
  bytes payload;
}

//use `using { encode } for IWormhole.VM;` to convert VAAs to bytes via .encode()
function encode(IWormhole.VM memory vaa) pure returns (bytes memory) {
  bytes memory sigs;
  for (uint i = 0; i < vaa.signatures.length; ++i) {
    IWormhole.Signature memory sig = vaa.signatures[i];
    sigs = bytes.concat(sigs, abi.encodePacked(sig.guardianIndex, sig.r, sig.s, sig.v));
  }

  return abi.encodePacked(
    vaa.version,
    vaa.guardianSetIndex,
    uint8(vaa.signatures.length),
    sigs,
    vaa.timestamp,
    vaa.nonce,
    vaa.emitterChainId,
    vaa.emitterAddress,
    vaa.sequence,
    vaa.consistencyLevel,
    vaa.payload
  );
}

//simple version of the library - should be sufficient for most use cases
library WormholeOverride {
  using AdvancedWormholeOverride for IWormhole;

  //transition to a new guardian set of the same size with all keys under our control
  // sets up default values for sequence, nonce, and consistency level (finalized)
  function setUpOverride(IWormhole wormhole) internal {
    wormhole.setUpOverride();
  }

  //uses block.timestamp and stored values for sequence, nonce, and consistency level
  function craftVaa(
    IWormhole wormhole,
    uint16 emitterChain,
    bytes32 emitterAddress,
    bytes memory payload
  ) internal view returns (IWormhole.VM memory vaa) {
    return wormhole.craftVaa(emitterChain, emitterAddress, payload);
  }

  //convert a published message struct into a VAA
  function sign(
    IWormhole wormhole,
    PublishedMessage memory pm
  ) internal view returns (IWormhole.VM memory vaa) {
    return wormhole.sign(pm);
  }

  //fetch all messages emitted by the core bridge from the logs
  function fetchPublishedMessages(
    IWormhole wormhole,
    Vm.Log[] memory logs
  ) internal view returns (PublishedMessage[] memory ret) {
    return wormhole.fetchPublishedMessages(logs);
  }

  //tests should ensure support of non-zero core bridge message fees
  function setMessageFee(uint256 msgFee) internal {
    AdvancedWormholeOverride.setMessageFee(msgFee);
  }

  //override default values used for crafting VAAs:

  function setSequence(IWormhole wormhole, uint64 sequence) internal {
    wormhole.setSequence(sequence);
  }

  function setNonce(IWormhole wormhole, uint32 nonce) internal {
    wormhole.setNonce(nonce);
  }

  function setConsistencyLevel(IWormhole wormhole, uint8 consistencyLevel) internal {
    wormhole.setConsistencyLevel(consistencyLevel);
  }
}

//──────────────────────────────────────────────────────────────────────────────────────────────────

//more complex library for more advanced tests
library AdvancedWormholeOverride {  
  using { toUniversalAddress } for address;
  using BytesParsing for bytes;
  using LogUtils for Vm.Log[];

  Vm constant vm = Vm(VM_ADDRESS);

  //not nicely exported by forge, so we copy it here
  function _makeAddrAndKey(
    string memory name
  ) private returns (address addr, uint256 privateKey) {
    privateKey = uint256(keccak256(abi.encodePacked(name)));
    addr = vm.addr(privateKey);
    vm.label(addr, name);
  }
  //CoreBridge storage layout
  // (see: https://github.com/wormhole-foundation/wormhole/blob/24442309dc93aa771b71ab29155286dda3e5f884/ethereum/contracts/State.sol#L22-L47)
  // (and: https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html#layout-of-state-variables-in-storage-and-transient-storage)
  //
  //  slot │ type    │ name
  // ──────┼─────────┼────────────────────────────
  //     0 │ uint16  │ chainId
  //     0 │ uint16  │ governanceChainId
  //     1 │ bytes32 │ governanceContract
  //     2 │ mapping │ guardianSets
  //     3 │ uint32  │ guardianSetIndex
  //     3 │ uint32  │ guardianSetExpiry
  //     4 │ mapping │ sequences
  //     5 │ mapping │ consumedGovernanceActions
  //     6 │ mapping │ initializedImplementations
  //     7 │ uint256 │ messageFee
  //     8 │ uint256 │ evmChainId
  uint256 constant private _STORAGE_GUARDIAN_SETS_SLOT = 2;
  uint256 constant private _STORAGE_MESSAGE_FEE_SLOT = 7;

  //CoreBridge guardian set struct:
  // struct GuardianSet {
	//   address[] keys;        //slot +0
	//   uint32 expirationTime; //slot +1
	// }
  uint256 constant private _GUARDIAN_SET_STRUCT_EXPIRATION_OFFSET = 1;

  uint8 constant WORMHOLE_VAA_VERSION = 1;

  //We add additional data to the core bridge's storage so we can conveniently use it in our
  //  library functions and to expose it to the test suite:

  //We store our additional data at slot keccak256("OverrideState")-1 in the core bridge
  uint256 private constant _OVERRIDE_STATE_SLOT =
    0x2e44eb2c79e88410071ac52f3c0e5ab51396d9208c2c783cdb8e12f39b763de8;
  
  //extra data (ors = _OVERRIDE_STATE_SLOT):
  //   slot │ type      │ name
  // ───────┼───────────┼────────────────────────────
  //  ors+0 │ uint64    │ sequence
  //  ors+1 │ uint32    │ nonce
  //  ors+2 │ uint8     │ consistencyLevel
  //  ors+3 │ address[] │ guardianPrivateKeys
  //  ors+4 | bytes(*)  | signingIndices (* = never packed, slot always contains only length)
  uint256 constant private _OR_SEQUENCE_OFFSET = 0;
  uint256 constant private _OR_NONCE_OFFSET = 1;
  uint256 constant private _OR_CONSISTENCY_OFFSET = 2;
  uint256 constant private _OR_GUARDIANS_OFFSET = 3;
  uint256 constant private _OR_SIGNING_INDICES_OFFSET = 4;

  function setSequence(IWormhole wormhole, uint64 sequence) internal { unchecked {
    vm.store(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_SEQUENCE_OFFSET),
      bytes32(uint256(sequence))
    );
  }}

  function getSequence(IWormhole wormhole) internal view returns (uint64) { unchecked {
    return uint64(uint256(vm.load(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_SEQUENCE_OFFSET)
    )));
  }}

  function setNonce(IWormhole wormhole, uint32 nonce) internal { unchecked {
    vm.store(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_NONCE_OFFSET),
      bytes32(uint256(nonce))
    );
  }}

  function getNonce(IWormhole wormhole) internal view returns (uint32) { unchecked {
    return uint32(uint256(vm.load(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_NONCE_OFFSET)
    )));
  }}
  
  function setConsistencyLevel(IWormhole wormhole, uint8 consistencyLevel) internal {
    vm.store(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_CONSISTENCY_OFFSET),
      bytes32(uint256(consistencyLevel))
    );
  }

  function getConsistencyLevel(IWormhole wormhole) internal view returns (uint8) {
    return uint8(uint256(vm.load(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_CONSISTENCY_OFFSET)
    )));
  }

  function _arraySlot(uint256 slot) private pure returns (uint256) {
    //dynamic storage arrays store their data starting at keccak256(slot)
    return uint256(keccak256(abi.encode(slot)));
  }

  function _setGuardianPrivateKeys(
    IWormhole wormhole,
    uint256[] memory guardianPrivateKeys
  ) private { unchecked {
    vm.store(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_GUARDIANS_OFFSET),
      bytes32(guardianPrivateKeys.length)
    );
    for (uint i = 0; i < guardianPrivateKeys.length; ++i)
      vm.store(
        address(wormhole),
        bytes32(_arraySlot(_OVERRIDE_STATE_SLOT + _OR_GUARDIANS_OFFSET) + i),
        bytes32(guardianPrivateKeys[i])
      );
  }}

  function getGuardianPrivateKeysLength(
    IWormhole wormhole
  ) internal view returns (uint256) { unchecked {
    return uint256(vm.load(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_GUARDIANS_OFFSET)
    ));
  }}

  function getGuardianPrivateKeys(
    IWormhole wormhole
  ) internal view returns (uint256[] memory) { unchecked {
    uint len = getGuardianPrivateKeysLength(wormhole);
    uint256[] memory keys = new uint256[](len);
    for (uint i = 0; i < len; ++i)
      keys[i] = uint256(vm.load(
        address(wormhole),
        bytes32(_arraySlot(_OVERRIDE_STATE_SLOT + _OR_GUARDIANS_OFFSET) + i)
      ));

    return keys;
  }}

  function setSigningIndices(
    IWormhole wormhole,
    bytes memory signingIndices //treated as a packed uint8 array
  ) internal { unchecked {
    vm.store(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET),
      bytes32(signingIndices.length)
    );
    uint fullSlots = signingIndices.length / 32;
    for (uint i = 0; i < fullSlots; ++i) {
      (bytes32 val,) = signingIndices.asBytes32Unchecked(i * 32);
      vm.store(
        address(wormhole),
        bytes32(_arraySlot(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET) + i),
        val
      );
    }
    
    uint remaining = signingIndices.length % 32;
    if (remaining > 0) {
      (uint256 val, ) = signingIndices.asUint256Unchecked(fullSlots * 32);
      val &= ~(type(uint256).max >> (8 * remaining)); //clean unused bits to be safe
      vm.store(
        address(wormhole),
        bytes32(_arraySlot(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET) + fullSlots),
        bytes32(val)
      );
    }
  }}

  function _getSigningIndicesLength(
    IWormhole wormhole
  ) private view returns (uint256) { unchecked {
    return uint256(vm.load(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET)
    ));
  }}

  function getSigningIndices(
    IWormhole wormhole
  ) internal view returns (bytes memory) { unchecked {
    uint len = _getSigningIndicesLength(wormhole);
    bytes32[] memory individualSlots = new bytes32[]((len + 31) / 32);
    for (uint i = 0; i < individualSlots.length; ++i)
      individualSlots[i] = vm.load(
        address(wormhole),
        bytes32(_arraySlot(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET) + i)
      );
    
    bytes memory packed = abi.encodePacked(individualSlots);
    assembly ("memory-safe") { mstore(packed, len) }
    return packed;
  }}

  uint32 constant DEFAULT_NONCE = 0xCCCCCCCC;
  uint8  constant DEFAULT_CONSISTENCY_LEVEL = 1; //= finalized
  uint64 constant DEFAULT_SEQUENCE = 0x5555555555555555;

  function defaultGuardianLabel(uint256 index) internal pure returns (string memory) {
    return string.concat("guardian", vm.toString(index));
  }

  function _guardianSetSlot(uint32 index) private pure returns (uint256) {
    //see https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html#mappings-and-dynamic-arrays
    return uint256(keccak256(abi.encode(index, _STORAGE_GUARDIAN_SETS_SLOT)));
  }

  function setUpOverride(IWormhole wormhole) internal {
    uint256[] memory guardianPrivateKeys = 
      new uint256[](wormhole.getGuardianSet(wormhole.getCurrentGuardianSetIndex()).keys.length);

    for (uint i = 0; i < guardianPrivateKeys.length; ++i)
      (, guardianPrivateKeys[i]) = _makeAddrAndKey(defaultGuardianLabel(i));

    setUpOverride(wormhole, guardianPrivateKeys);
  }

  function setUpOverride(
    IWormhole wormhole,
    uint256[] memory guardianPrivateKeys
  ) internal { unchecked {
    // OverrideState storage state = overrideState();
    if (guardianPrivateKeys.length != 0)
      revert ("already set up");

    if (guardianPrivateKeys.length == 0)
      revert ("no guardian private keys provided");
    
    if (guardianPrivateKeys.length > type(uint8).max)
      revert ("too many guardians, core bridge enforces upper bound of 255");

    //bring the core bridge under heel by introducing a new guardian set
    uint32 currentGuardianSetIndex = wormhole.getCurrentGuardianSetIndex();
    uint256 currentGuardianSetSlot = _guardianSetSlot(currentGuardianSetIndex);

    //expire the current guardian set like a normal guardian set transition would
    vm.store(
      address(wormhole),
      bytes32(currentGuardianSetSlot + _GUARDIAN_SET_STRUCT_EXPIRATION_OFFSET),
      bytes32(block.timestamp + 1 days)
    );
    
    uint32 nextGuardianSetIndex = currentGuardianSetIndex + 1;
    uint256 nextGuardianSetSlot = _guardianSetSlot(nextGuardianSetIndex);

    //initialize the new guardian set with the provided private keys

    //dynamic storage arrays store their length in their assigned slot
    vm.store(address(wormhole), bytes32(nextGuardianSetSlot), bytes32(guardianPrivateKeys.length));
    for (uint256 i = 0; i < guardianPrivateKeys.length; ++i)
      vm.store(
        address(wormhole),
        bytes32(_arraySlot(nextGuardianSetSlot) + i),
        bytes32(uint256(uint160(vm.addr(guardianPrivateKeys[i]))))
      );
    
    //initialize override state with default values
    setSequence(wormhole, DEFAULT_SEQUENCE);
    setNonce(wormhole, DEFAULT_NONCE);
    setConsistencyLevel(wormhole, DEFAULT_CONSISTENCY_LEVEL);
    _setGuardianPrivateKeys(wormhole, guardianPrivateKeys);
    uint quorum = guardianPrivateKeys.length * 2 / 3 + 1;
    uint8[] memory signingIndices = new uint8[](quorum);
    for (uint i = 0; i < quorum; ++i)
      signingIndices[i] = uint8(i);
    setSigningIndices(wormhole, abi.encodePacked(signingIndices));
  }}

  function setMessageFee(uint256 msgFee) internal {
    vm.store(address(vm), bytes32(_STORAGE_MESSAGE_FEE_SLOT), bytes32(msgFee));
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
  ) internal view returns (IWormhole.VM memory vaa) {
    return sign(wormhole, pm, getSigningIndices(wormhole));
  }

  function sign(
    IWormhole wormhole,
    PublishedMessage memory pm,
    bytes memory signingGuardianIndices //treated as a packed uint8 array
  ) internal view returns (IWormhole.VM memory vaa) { unchecked {
    vaa.version = WORMHOLE_VAA_VERSION;
    vaa.timestamp = pm.timestamp;
    vaa.nonce = pm.nonce;
    vaa.emitterChainId = pm.emitterChainId;
    vaa.emitterAddress = pm.emitterAddress;
    vaa.sequence = pm.sequence;
    vaa.consistencyLevel = pm.consistencyLevel;
    vaa.payload = pm.payload;
    vaa.guardianSetIndex = wormhole.getCurrentGuardianSetIndex();

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

    vaa.signatures = new IWormhole.Signature[](signingGuardianIndices.length);
    uint256[] memory guardianPrivateKeys = getGuardianPrivateKeys(wormhole);
    for (uint i = 0; i < signingGuardianIndices.length; ++i) {
      (uint8 gi, ) = signingGuardianIndices.asUint8(i);
      (vaa.signatures[i].v, vaa.signatures[i].r, vaa.signatures[i].s) =
        vm.sign(guardianPrivateKeys[gi], vaa.hash);
      vaa.signatures[i].guardianIndex = gi;
      vaa.signatures[i].v -= 27;
    }
  }}

  function craftVaa(
    IWormhole wormhole,
    uint16 emitterChain,
    bytes32 emitterAddress,
    bytes memory payload
  ) internal view returns (IWormhole.VM memory vaa) {
    PublishedMessage memory pm = PublishedMessage({
      timestamp: uint32(block.timestamp),
      nonce: getNonce(wormhole),
      emitterChainId: emitterChain,
      emitterAddress: emitterAddress,
      sequence: getSequence(wormhole),
      consistencyLevel: getConsistencyLevel(wormhole),
      payload: payload
    });

    return sign(wormhole, pm);
  }

  function craftGovernancePublishedMessage(
    IWormhole wormhole,
    bytes32 module,
    uint8 action,
    uint16 targetChain,
    bytes memory decree
  ) internal view returns (PublishedMessage memory) {
    return PublishedMessage({
      timestamp: uint32(block.timestamp),
      nonce: getNonce(wormhole),
      emitterChainId: wormhole.governanceChainId(),
      emitterAddress: wormhole.governanceContract(),
      sequence: getSequence(wormhole),
      consistencyLevel: getConsistencyLevel(wormhole),
      payload: abi.encodePacked(module, action, targetChain, decree)
    });
  }
}
