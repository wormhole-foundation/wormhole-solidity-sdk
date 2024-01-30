// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "wormhole-sdk/interfaces/IWormhole.sol";
import "wormhole-sdk/interfaces/IWormholeRelayer.sol";
import {toUniversalAddress, fromUniversalAddress} from "wormhole-sdk/Utils.sol";
import "wormhole-sdk/libraries/BytesParsing.sol";
import {CCTPMessageLib} from "wormhole-sdk/WormholeRelayer/CCTPBase.sol";

import {VM_ADDRESS} from "../Constants.sol";
import "../WormholeOverride.sol";
import "../CctpOverride.sol";
import "./DeliveryInstructionDecoder.sol";
import "./ExecutionParameters.sol";

using BytesParsing for bytes;

contract MockOffchainRelayer {
    using WormholeOverride for IWormhole;
    using CctpOverride for IMessageTransmitter;
    using CctpMessages for CctpTokenBurnMessage;
    using { toUniversalAddress } for address;
    using { fromUniversalAddress } for bytes32;

    Vm public constant vm = Vm(VM_ADDRESS);

    mapping(uint16 => IWormhole) wormholeContracts;
    mapping(uint16 => IMessageTransmitter) messageTransmitterContracts;
    mapping(uint16 => IWormholeRelayer) wormholeRelayerContracts;
    mapping(uint16 => uint256) forks;

    mapping(uint256 => uint16) chainIdFromFork;

    mapping(bytes32 => bytes[]) pastEncodedSignedVaas;

    mapping(bytes32 => bytes) pastEncodedDeliveryVAA;

    function getForkChainId() internal view returns (uint16) {
        uint16 chainId = chainIdFromFork[vm.activeFork()];
        require(chainId != 0, "Chain not registered with MockOffchainRelayer");
        return chainId;
    }

    function getForkWormhole() internal view returns (IWormhole) {
        return wormholeContracts[getForkChainId()];
    }

    function getForkMessageTransmitter() internal view returns (IMessageTransmitter) {
        return messageTransmitterContracts[getForkChainId()];
    }

    function getForkWormholeRelayer() internal view returns (IWormholeRelayer) {
        return wormholeRelayerContracts[getForkChainId()];
    }

    function getPastEncodedSignedVaas(
        uint16 chainId,
        uint64 deliveryVAASequence
    ) public view returns (bytes[] memory) {
        return
            pastEncodedSignedVaas[
                keccak256(abi.encodePacked(chainId, deliveryVAASequence))
            ];
    }

    function getPastDeliveryVAA(
        uint16 chainId,
        uint64 deliveryVAASequence
    ) public view returns (bytes memory) {
        return
            pastEncodedDeliveryVAA[
                keccak256(abi.encodePacked(chainId, deliveryVAASequence))
            ];
    }

    function registerChain(
        uint16 chainId,
        IWormhole wormholeContractAddress,
        IMessageTransmitter messageTransmitterContractAddress,
        IWormholeRelayer wormholeRelayerContractAddress,
        uint256 fork
    ) public {
        wormholeContracts[chainId] = wormholeContractAddress;
        messageTransmitterContracts[chainId] = messageTransmitterContractAddress;
        wormholeRelayerContracts[chainId] = wormholeRelayerContractAddress;
        forks[chainId] = fork;
        chainIdFromFork[fork] = chainId;
    }

    function vaaKeyMatchesVAA(
        VaaKey memory vaaKey,
        bytes memory signedVaa
    ) internal view returns (bool) {
        IWormhole.VM memory parsedVaa = getForkWormhole().parseVM(signedVaa);
        return
            (vaaKey.chainId == parsedVaa.emitterChainId) &&
            (vaaKey.emitterAddress == parsedVaa.emitterAddress) &&
            (vaaKey.sequence == parsedVaa.sequence);
    }

    function cctpKeyMatchesCCTPMessage(
        CCTPMessageLib.CCTPKey memory cctpKey,
        CCTPMessageLib.CCTPMessage memory cctpMessage
    ) internal pure returns (bool) {
        (uint64 nonce,) = cctpMessage.message.asUint64(12);
        (uint32 domain,) = cctpMessage.message.asUint32(4);
        return
           nonce == cctpKey.nonce && domain == cctpKey.domain;
    }

    function relay(Vm.Log[] memory logs, bool debugLogging) public {
        relay(logs, bytes(""), debugLogging);
    }

    function relay(
        Vm.Log[] memory logs,
        bytes memory deliveryOverrides,
        bool debugLogging
    ) public {
        IWormhole emitterWormhole = getForkWormhole();
        PublishedMessage[] memory pms = emitterWormhole.fetchPublishedMessages(logs);
        if (debugLogging)
            console.log(
                "Found %s wormhole messages in logs from %s",
                pms.length,
                address(emitterWormhole)
            );

        IWormhole.VM[] memory vaas = new IWormhole.VM[](pms.length);
        bytes[] memory encodedSignedVaas = new bytes[](pms.length);
        for (uint256 i = 0; i < encodedSignedVaas.length; ++i)
            (vaas[i], encodedSignedVaas[i]) = emitterWormhole.sign(pms[i]);
        
        CCTPMessageLib.CCTPMessage[] memory cctpSignedMsgs = new CCTPMessageLib.CCTPMessage[](0);
        IMessageTransmitter emitterMessageTransmitter = getForkMessageTransmitter();
        if (address(emitterMessageTransmitter) != address(0)) {
            CctpTokenBurnMessage[] memory burnMsgs =
                emitterMessageTransmitter.fetchBurnMessages(logs);
            if (debugLogging)
                console.log(
                    "Found %s circle messages in logs from %s",
                    burnMsgs.length,
                    address(emitterMessageTransmitter)
                );

            cctpSignedMsgs = new CCTPMessageLib.CCTPMessage[](burnMsgs.length);
            for (uint256 i = 0; i < cctpSignedMsgs.length; ++i) {
                cctpSignedMsgs[i].message = burnMsgs[i].encode();
                cctpSignedMsgs[i].signature = emitterMessageTransmitter.sign(burnMsgs[i]);
            }
        }

        for (uint16 i = 0; i < vaas.length; ++i) {
            if (debugLogging) {
                console.log(
                    "Found VAA from chain %s emitted from %s",
                    vaas[i].emitterChainId,
                    vaas[i].emitterAddress.fromUniversalAddress()
                );
            }

            // if (
            //     vaas[i].emitterAddress ==
            //     wormholeRelayerContracts[chainId].toUniversalAddress() &&
            //     (vaas[i].emitterChainId == chainId)
            // ) {
            //     if (debugLogging) {
            //         console.log("Relaying VAA to chain %s", chainId);
            //     }
            //     //vm.selectFork(forks[chainIdOfWormholeAndGuardianUtilities]);
                genericRelay(
                    encodedSignedVaas[i],
                    encodedSignedVaas,
                    cctpSignedMsgs,
                    vaas[i],
                    deliveryOverrides
                );
            // }
        }
    }

    function setInfo(
        uint16 chainId,
        uint64 deliveryVAASequence,
        bytes[] memory encodedSignedVaas,
        bytes memory encodedDeliveryVAA
    ) internal {
        bytes32 key = keccak256(abi.encodePacked(chainId, deliveryVAASequence));
        pastEncodedSignedVaas[key] = encodedSignedVaas;
        pastEncodedDeliveryVAA[key] = encodedDeliveryVAA;
    }

    function genericRelay(
        bytes memory encodedDeliveryVAA,
        bytes[] memory encodedSignedVaas,
        CCTPMessageLib.CCTPMessage[] memory cctpMessages,
        IWormhole.VM memory parsedDeliveryVAA,
        bytes memory deliveryOverrides
    ) internal {
        uint currentFork = vm.activeFork();

        (uint8 payloadId, ) = parsedDeliveryVAA.payload.asUint8Unchecked(0);
        if (payloadId == 1) {
            DeliveryInstruction memory instruction = decodeDeliveryInstruction(
                parsedDeliveryVAA.payload
            );

            bytes[] memory encodedSignedVaasToBeDelivered = new bytes[](
                instruction.messageKeys.length
            );

            for (uint8 i = 0; i < instruction.messageKeys.length; i++) {
                if (instruction.messageKeys[i].keyType == 1) {
                    // VaaKey
                    (VaaKey memory vaaKey, ) = decodeVaaKey(
                        instruction.messageKeys[i].encodedKey,
                        0
                    );
                    for (uint8 j = 0; j < encodedSignedVaas.length; j++) {
                        if (vaaKeyMatchesVAA(vaaKey, encodedSignedVaas[j])) {
                            encodedSignedVaasToBeDelivered[i] = encodedSignedVaas[j];
                            break;
                        }
                    }
                } else if (instruction.messageKeys[i].keyType == 2) {
                    // CCTP Key
                    (CCTPMessageLib.CCTPKey memory key,) = decodeCCTPKey(instruction.messageKeys[i].encodedKey, 0);                    
                    for (uint8 j = 0; j < cctpMessages.length; j++) {
                        if (cctpKeyMatchesCCTPMessage(key, cctpMessages[j])) {
                            encodedSignedVaasToBeDelivered[i] = abi.encode(cctpMessages[j].message, cctpMessages[j].signature);
                            break;
                        }
                    }
                }
            }

            EvmExecutionInfoV1 memory executionInfo = decodeEvmExecutionInfoV1(
                instruction.encodedExecutionInfo
            );

            uint256 budget = executionInfo.gasLimit *
                executionInfo.targetChainRefundPerGasUnused +
                instruction.requestedReceiverValue +
                instruction.extraReceiverValue;

            uint16 targetChain = instruction.targetChain;

            vm.selectFork(forks[targetChain]);

            vm.deal(address(this), budget);

            vm.recordLogs();
            getForkWormholeRelayer().deliver{value: budget}(
                encodedSignedVaasToBeDelivered,
                encodedDeliveryVAA,
                payable(address(this)),
                deliveryOverrides
            );

            setInfo(
                parsedDeliveryVAA.emitterChainId,
                parsedDeliveryVAA.sequence,
                encodedSignedVaasToBeDelivered,
                encodedDeliveryVAA
            );
        } else if (payloadId == 2) {
            RedeliveryInstruction
                memory instruction = decodeRedeliveryInstruction(
                    parsedDeliveryVAA.payload
                );

            DeliveryOverride memory deliveryOverride = DeliveryOverride({
                newExecutionInfo: instruction.newEncodedExecutionInfo,
                newReceiverValue: instruction.newRequestedReceiverValue,
                redeliveryHash: parsedDeliveryVAA.hash
            });

            EvmExecutionInfoV1 memory executionInfo = decodeEvmExecutionInfoV1(
                instruction.newEncodedExecutionInfo
            );
            uint256 budget = executionInfo.gasLimit *
                executionInfo.targetChainRefundPerGasUnused +
                instruction.newRequestedReceiverValue;

            bytes memory oldEncodedDeliveryVAA = getPastDeliveryVAA(
                instruction.deliveryVaaKey.chainId,
                instruction.deliveryVaaKey.sequence
            );
            bytes[] memory oldEncodedSignedVaas = getPastEncodedSignedVaas(
                instruction.deliveryVaaKey.chainId,
                instruction.deliveryVaaKey.sequence
            );

            uint16 targetChain = decodeDeliveryInstruction(
                getForkWormhole().parseVM(oldEncodedDeliveryVAA).payload
            ).targetChain;

            vm.selectFork(forks[targetChain]);
            getForkWormholeRelayer().deliver{value: budget}(
                oldEncodedSignedVaas,
                oldEncodedDeliveryVAA,
                payable(address(this)),
                encode(deliveryOverride)
            );
        }
        vm.selectFork(currentFork);
    }

    receive() external payable {}
}
