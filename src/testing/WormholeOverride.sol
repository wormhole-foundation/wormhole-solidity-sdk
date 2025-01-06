// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {WORD_SIZE, WORD_SIZE_MINUS_ONE}          from "wormhole-sdk/constants/Common.sol";
import {IWormhole}                               from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing}                            from "wormhole-sdk/libraries/BytesParsing.sol";
import {VaaLib}                                  from "wormhole-sdk/libraries/VaaLib.sol";
<<<<<<< HEAD
import {CoreBridgeLib}                           from "wormhole-sdk/libraries/CoreBridge.sol";
=======
import {minSigsForQuorum}                        from "wormhole-sdk/libraries/CoreBridge.sol";
>>>>>>> cb108db (improved, extended, and unified decoding, added CoreBridgeLib)
import {toUniversalAddress}                      from "wormhole-sdk/Utils.sol";
import {VM_ADDRESS, DEVNET_GUARDIAN_PRIVATE_KEY} from "wormhole-sdk/testing/Constants.sol";
import {LogUtils}                                from "wormhole-sdk/testing/LogUtils.sol";
import {
  VaaLib,
  GuardianSignature,
  Vaa,
  VaaEnvelope,
  VaaBody as PublishedMessage
} from "wormhole-sdk/libraries/VaaLib.sol";

//┌────────────────────────────────────────────────────────────────────────────────────────────────┐
//│ take control of the core bridge in forge fork tests to generate VAAs and test message emission │
//└────────────────────────────────────────────────────────────────────────────────────────────────┘

//simple version of the library - should be sufficient for most use cases
library WormholeOverride {
  using AdvancedWormholeOverride for IWormhole;

  //Transition to a new guardian set under our control and set up default values for
  //  sequence (0), nonce (0), and consistency level (1 = finalized).
  //
  //Note: Depending on the DEFAULT_TO_DEVNET_GUARDIAN environment variable:
  //  false (default): The current guardian set is superseded by a new set of the same size.
  //    Keeps in line with real world conditions. Useful for realistic gas costs and VAA sizes.
  //  true: The new guardian set is comprised of only one key: DEVNET_GUARDIAN_PRIVATE_KEY.
  //    This is useful to reduce the size of encoded VAAs and hence call traces when debugging.
  function setUpOverride(IWormhole wormhole) internal {
    wormhole.setUpOverride();
  }

  //convenience function:
  // 1. creates a PublishedMessage (= renamed VaaBody) struct with the current block.timestamp and
  //      the stored values for sequence (auto-incremented), nonce, and consistency level
  // 2. uses sign to turn it into a VAA
  // 3. encodes the VAA as bytes
  function craftVaa(
    IWormhole wormhole,
    uint16 emitterChain,
    bytes32 emitterAddress,
    bytes memory payload
  ) internal returns (bytes memory encodedVaa) {
    return wormhole.craftVaa(emitterChain, emitterAddress, payload);
  }

  //turns a PublishedMessage struct into a VAA by having a quorum of guardians sign it
  function sign(
    IWormhole wormhole,
    PublishedMessage memory pm
  ) internal view returns (Vaa memory vaa) {
    return wormhole.sign(pm);
  }

  //fetch all messages from the logs that were emitted by the core bridge
  function fetchPublishedMessages(
    IWormhole wormhole,
    Vm.Log[] memory logs
  ) internal view returns (PublishedMessage[] memory ret) {
    return wormhole.fetchPublishedMessages(logs);
  }

  //tests should ensure support of non-zero core bridge message fees
  function setMessageFee(IWormhole wormhole, uint256 msgFee) internal {
    wormhole.setMessageFee(msgFee);
  }

  //override the default consistency level used by craftVaa()
  function setConsistencyLevel(IWormhole wormhole, uint8 consistencyLevel) internal {
    wormhole.setConsistencyLevel(consistencyLevel);
  }
}

//──────────────────────────────────────────────────────────────────────────────────────────────────

//more complex superset of WormholeOverride for more advanced tests
library AdvancedWormholeOverride {
  using { toUniversalAddress } for address;
  using BytesParsing for bytes;
  using LogUtils for Vm.Log[];
  using VaaLib for Vaa;

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
  //  Slot │ Type    │ Name
  // ──────┼─────────┼────────────────────────────
  //     0 │ uint16  │ chainId
  //     0 │ uint16  │ governanceChainId
  //     1 │ bytes32 │ governanceContract
  //     2 │ mapping │ guardianSets
  //     3 │ uint32  │ guardianSetIndex
  //     3 │ uint32  │ guardianSetExpiry (this makes no sense and is unused)
  //     4 │ mapping │ sequences
  //     5 │ mapping │ consumedGovernanceActions
  //     6 │ mapping │ initializedImplementations
  //     7 │ uint256 │ messageFee
  //     8 │ uint256 │ evmChainId
  uint256 constant private _STORAGE_GUARDIAN_SETS_SLOT = 2;
  uint256 constant private _STORAGE_GUARDIAN_SET_INDEX_SLOT = 3;
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
  //We don't store this in a "local" struct in case tests use multiple forks and hence override
  //  multiple, different instances of the core bridge
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

  function getAndIncrementSequence(IWormhole wormhole) internal returns (uint64) { unchecked {
    uint64 sequence = getSequence(wormhole);
    setSequence(wormhole, sequence + 1);
    return sequence;
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
    uint8[] memory signingIndices
  ) internal { unchecked {
    vm.store(
      address(wormhole),
      bytes32(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET),
      bytes32(signingIndices.length)
    );

    //abi.encodePacked pads elements of arrays so we have to manually pack here
    bytes memory packedIndices = new bytes(signingIndices.length);
    for (uint i = 0; i < signingIndices.length; ++i) {
      uint8 curIdx = signingIndices[i];
      assembly ("memory-safe") { mstore8(add(add(packedIndices, WORD_SIZE), i), curIdx) }
    }

    uint fullSlots = packedIndices.length / WORD_SIZE;
    for (uint i = 0; i < fullSlots; ++i) {
      (bytes32 val,) = packedIndices.asBytes32MemUnchecked(i * WORD_SIZE);
      vm.store(
        address(wormhole),
        bytes32(_arraySlot(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET) + i),
        val
      );
    }

    uint remaining = packedIndices.length % WORD_SIZE;
    if (remaining > 0) {
      (uint256 val, ) = packedIndices.asUint256MemUnchecked(fullSlots * WORD_SIZE);
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
    bytes32[] memory individualSlots = new bytes32[]((len + WORD_SIZE_MINUS_ONE) / WORD_SIZE);
    for (uint i = 0; i < individualSlots.length; ++i)
      individualSlots[i] = vm.load(
        address(wormhole),
        bytes32(_arraySlot(_OVERRIDE_STATE_SLOT + _OR_SIGNING_INDICES_OFFSET) + i)
      );

    bytes memory packed = abi.encodePacked(individualSlots);
    assembly ("memory-safe") { mstore(packed, len) }
    return packed;
  }}

  function defaultGuardianLabel(uint256 index) internal pure returns (string memory) {
    return string.concat("guardian", vm.toString(index + 1));
  }

  function _guardianSetSlot(uint32 index) private pure returns (uint256) {
    //see https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html#mappings-and-dynamic-arrays
    return uint256(keccak256(abi.encode(index, _STORAGE_GUARDIAN_SETS_SLOT)));
  }

  function setUpOverride(IWormhole wormhole) internal {
    bool defaultToDevnetGuardian = vm.envOr("DEFAULT_TO_DEVNET_GUARDIAN", false);
    uint256[] memory guardianPrivateKeys;
    if (defaultToDevnetGuardian) {
      guardianPrivateKeys = new uint256[](1);
      guardianPrivateKeys[0] = DEVNET_GUARDIAN_PRIVATE_KEY;
    }
    else {
      guardianPrivateKeys =
        new uint256[](wormhole.getGuardianSet(wormhole.getCurrentGuardianSetIndex()).keys.length);

      for (uint i = 0; i < guardianPrivateKeys.length; ++i)
        (, guardianPrivateKeys[i]) = _makeAddrAndKey(defaultGuardianLabel(i));
    }
    setUpOverride(wormhole, guardianPrivateKeys);
  }

  function setUpOverride(
    IWormhole wormhole,
    uint256[] memory guardianPrivateKeys
  ) internal { unchecked {
    if (getGuardianPrivateKeys(wormhole).length != 0)
      revert ("already set up");

    if (guardianPrivateKeys.length == 0)
      revert ("no guardian private keys provided");

    if (guardianPrivateKeys.length > type(uint8).max)
      revert ("too many guardians, core bridge enforces upper bound of 255");

    //bring the core bridge under heel by introducing a new guardian set
    uint32 curGuardianSetIndex = wormhole.getCurrentGuardianSetIndex();
    uint256 curGuardianSetSlot = _guardianSetSlot(curGuardianSetIndex);

    //expire the current guardian set like a normal guardian set transition would
    vm.store(
      address(wormhole),
      bytes32(curGuardianSetSlot + _GUARDIAN_SET_STRUCT_EXPIRATION_OFFSET),
      bytes32(block.timestamp + 1 days)
    );

    uint32 newGuardianSetIndex = curGuardianSetIndex + 1;
    uint256 newGuardianSetSlot = _guardianSetSlot(newGuardianSetIndex);

    //update the guardian set index
    vm.store(
      address(wormhole),
      bytes32(_STORAGE_GUARDIAN_SET_INDEX_SLOT),
      bytes32(uint256(newGuardianSetIndex))
    );

    //dynamic storage arrays store their length in their assigned slot
    vm.store(address(wormhole), bytes32(newGuardianSetSlot), bytes32(guardianPrivateKeys.length));
    //initialize the new guardian set with the provided private keys
    for (uint256 i = 0; i < guardianPrivateKeys.length; ++i)
      vm.store(
        address(wormhole),
        bytes32(_arraySlot(newGuardianSetSlot) + i),
        bytes32(uint256(uint160(vm.addr(guardianPrivateKeys[i]))))
      );

    //initialize override state with default values
    setSequence(wormhole, 0);
    setNonce(wormhole, 0);
    setConsistencyLevel(wormhole, 1); //finalized
    _setGuardianPrivateKeys(wormhole, guardianPrivateKeys);
    uint quorum = CoreBridgeLib.minSigsForQuorum(guardianPrivateKeys.length);
    uint8[] memory signingIndices = new uint8[](quorum);
    for (uint i = 0; i < quorum; ++i)
      signingIndices[i] = uint8(i);

    setSigningIndices(wormhole, signingIndices);
  }}

  function setMessageFee(IWormhole wormhole, uint256 msgFee) internal {
    vm.store(address(wormhole), bytes32(_STORAGE_MESSAGE_FEE_SLOT), bytes32(msgFee));
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
      PublishedMessage memory pm = ret[i];
      VaaEnvelope memory envelope = pm.envelope;
      envelope.emitterAddress = pmLogs[i].topics[1];
      (envelope.sequence, envelope.nonce, pm.payload, envelope.consistencyLevel) =
        abi.decode(pmLogs[i].data, (uint64, uint32, bytes, uint8));
      envelope.timestamp = uint32(block.timestamp);
      envelope.emitterChainId = wormhole.chainId();
    }
  }}

  function sign(
    IWormhole wormhole,
    PublishedMessage memory pm
  ) internal view returns (Vaa memory vaa) {
    return sign(wormhole, pm, getSigningIndices(wormhole));
  }

  function sign(
    IWormhole wormhole,
    bytes32 hash
  ) internal view returns (GuardianSignature[] memory signatures) {
    return sign(wormhole, hash, getSigningIndices(wormhole));
  }

  function sign(
    IWormhole wormhole,
    PublishedMessage memory pm,
    bytes memory signingGuardianIndices //treated as a packed uint8 array
  ) internal view returns (Vaa memory vaa) {
    vaa.header.guardianSetIndex = wormhole.getCurrentGuardianSetIndex();
    vaa.header.signatures = sign(wormhole, VaaLib.calcDoubleHash(pm), signingGuardianIndices);
    vaa.envelope = pm.envelope;
    vaa.payload = pm.payload;
  }

  function sign(
    IWormhole wormhole,
    bytes32 hash,
    bytes memory signingGuardianIndices //treated as a packed uint8 array
  ) internal view returns (GuardianSignature[] memory signatures) { unchecked {
    signatures = new GuardianSignature[](signingGuardianIndices.length);
    uint256[] memory guardianPrivateKeys = getGuardianPrivateKeys(wormhole);
    for (uint i = 0; i < signingGuardianIndices.length; ++i) {
      (uint8 gi, ) = signingGuardianIndices.asUint8Mem(i);
      (signatures[i].v, signatures[i].r, signatures[i].s) =
        vm.sign(guardianPrivateKeys[gi], hash);
      signatures[i].guardianIndex = gi;
    }
  }}

  function craftVaa(
    IWormhole wormhole,
    uint16 emitterChain,
    bytes32 emitterAddress,
    bytes memory payload
  ) internal returns (bytes memory encodedVaa) {
    PublishedMessage memory pm = PublishedMessage(
      VaaEnvelope(
        uint32(block.timestamp),
        getNonce(wormhole),
        emitterChain,
        emitterAddress,
        getAndIncrementSequence(wormhole),
        getConsistencyLevel(wormhole)
      ),
      payload
    );

    return sign(wormhole, pm).encode();
  }

  function craftGovernancePublishedMessage(
    IWormhole wormhole,
    bytes32 module,
    uint8 action,
    uint16 targetChain,
    bytes memory decree
  ) internal returns (PublishedMessage memory) {
    return PublishedMessage(
      VaaEnvelope(
        uint32(block.timestamp),
        getNonce(wormhole),
        wormhole.governanceChainId(),
        wormhole.governanceContract(),
        getAndIncrementSequence(wormhole),
        getConsistencyLevel(wormhole)
      ),
      abi.encodePacked(module, action, targetChain, decree)
    );
  }
}
