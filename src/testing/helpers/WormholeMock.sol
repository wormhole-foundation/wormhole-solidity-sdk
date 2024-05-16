// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import { IWormhole } from '../../interfaces/IWormhole.sol';

contract WormholeMock is IWormhole {
 constructor() {}

 // INIT_SIGNERS=["0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe"]
 function publishMessage(
  uint32 nonce,
  bytes memory payload,
  uint8 consistencyLevel
 ) external payable virtual override returns (uint64 sequence) {}

 function initialize() external virtual override {}

 function parseAndVerifyVM(
  bytes calldata encodedVM
 ) external view virtual override returns (VM memory vm, bool valid, string memory reason) {}

 function verifyVM(
  VM memory vm
 ) external view virtual override returns (bool valid, string memory reason) {}

 function verifySignatures(
  bytes32 hash,
  Signature[] memory signatures,
  GuardianSet memory guardianSet
 ) external pure virtual override returns (bool valid, string memory reason) {
        uint8 lastIndex = 0;
        uint256 guardianCount = guardianSet.keys.length;
        for (uint i = 0; i < signatures.length; i++) {
            Signature memory sig = signatures[i];
            address signatory = ecrecover(hash, sig.v, sig.r, sig.s);
            // ecrecover returns 0 for invalid signatures. We explicitly require valid signatures to avoid unexpected
            // behaviour due to the default storage slot value also being 0.
            require(signatory != address(0), "ecrecover failed with signature");

            /// Ensure that provided signature indices are ascending only
            require(i == 0 || sig.guardianIndex > lastIndex, "signature indices must be ascending");
            lastIndex = sig.guardianIndex;

            /// @dev Ensure that the provided signature index is within the
            /// bounds of the guardianSet. This is implicitly checked by the array
            /// index operation below, so this check is technically redundant.
            /// However, reverting explicitly here ensures that a bug is not
            /// introduced accidentally later due to the nontrivial storage
            /// semantics of solidity.
            require(sig.guardianIndex < guardianCount, "guardian index out of bounds");

            /// Check to see if the signer of the signature does not match a specific Guardian key at the provided index
            if(signatory != guardianSet.keys[sig.guardianIndex]){
                return (false, "VM signature invalid");
            }
        }

        /// If we are here, we've validated that the provided signatures are valid for the provided guardianSet
        return (true, "");
    }

 function parseVM(bytes memory encodedVM) external pure override returns (VM memory vm) {}

 function quorum(
  uint numGuardians
 ) external pure override returns (uint numSignaturesRequiredForQuorum) {}

 function getGuardianSet(uint32 index) external pure override returns (GuardianSet memory) {
        index = 0;
        address[] memory keys = new address[](1);
        keys[0] = 0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe;

        GuardianSet memory gset = GuardianSet({
            keys: keys,
            expirationTime: 999999999
        });
        return gset;
    }

 function getCurrentGuardianSetIndex() external view virtual override returns (uint32) {}

 function getGuardianSetExpiry() external view virtual override returns (uint32) {}

 function governanceActionIsConsumed(bytes32 hash) external view virtual override returns (bool) {}

 function isInitialized(address impl) external view virtual override returns (bool) {}

 function chainId() external view virtual override returns (uint16) {}

 function isFork() external view virtual override returns (bool) {}

 function governanceChainId() external view virtual override returns (uint16) {}

 function governanceContract() external view virtual override returns (bytes32) {}

 function messageFee() external view virtual override returns (uint256) {}

 function evmChainId() external view virtual override returns (uint256) {}

 function nextSequence(address emitter) external view virtual override returns (uint64) {}

 function parseContractUpgrade(
  bytes memory encodedUpgrade
 ) external pure virtual override returns (ContractUpgrade memory cu) {}

 function parseGuardianSetUpgrade(
  bytes memory encodedUpgrade
 ) external pure virtual override returns (GuardianSetUpgrade memory gsu) {}

 function parseSetMessageFee(
  bytes memory encodedSetMessageFee
 ) external pure virtual override returns (SetMessageFee memory smf) {}

 function parseTransferFees(
  bytes memory encodedTransferFees
 ) external pure virtual override returns (TransferFees memory tf) {}

 function parseRecoverChainId(
  bytes memory encodedRecoverChainId
 ) external pure virtual override returns (RecoverChainId memory rci) {}

 function submitContractUpgrade(bytes memory _vm) external virtual override {}

 function submitSetMessageFee(bytes memory _vm) external virtual override {}

 function submitNewGuardianSet(bytes memory _vm) external virtual override {}

 function submitTransferFees(bytes memory _vm) external virtual override {}

 function submitRecoverChainId(bytes memory _vm) external virtual override {}
}
