// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {WormholeSimulator} from "./WormholeSimulator.sol";
import {CircleMessageTransmitterSimulator} from "./CircleCCTPSimulator.sol";
import {toWormholeFormat, fromWormholeFormat} from "../../Utils.sol";
import "../../interfaces/IWormholeRelayer.sol";
import "../../interfaces/IWormhole.sol";
import "forge-std/Vm.sol";
import "./DeliveryInstructionDecoder.sol";
import {CCTPMessageLib} from "../../CCTPBase.sol";
import "./ExecutionParameters.sol";
import "./BytesParsing.sol";
import "forge-std/console.sol";

using BytesParsing for bytes;

contract MockOffchainRelayer {

    uint16 chainIdOfWormholeAndGuardianUtilities;
    IWormhole relayerWormhole;
    WormholeSimulator relayerWormholeSimulator;
    CircleMessageTransmitterSimulator relayerCircleSimulator;


    // Taken from forge-std/Script.sol
    address private constant VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm public constant vm = Vm(VM_ADDRESS);

    mapping(uint16 => address) wormholeRelayerContracts;

    mapping(uint16 => uint256) forks;

    mapping(uint256 => uint16) chainIdFromFork;

    mapping(bytes32 => bytes[]) pastEncodedSignedVaas;

    mapping(bytes32 => bytes) pastEncodedDeliveryVAA;

    constructor(address _wormhole, address _wormholeSimulator, address _circleSimulator) {
        relayerWormhole = IWormhole(_wormhole);
        relayerWormholeSimulator = WormholeSimulator(_wormholeSimulator);
        relayerCircleSimulator = CircleMessageTransmitterSimulator(_circleSimulator);
        chainIdOfWormholeAndGuardianUtilities = relayerWormhole.chainId();
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
        address wormholeRelayerContractAddress,
        uint256 fork
    ) public {
        wormholeRelayerContracts[chainId] = wormholeRelayerContractAddress;
        forks[chainId] = fork;
        chainIdFromFork[fork] = chainId;
    }

    function relay() public {
        relay(vm.getRecordedLogs());
    }

    function relay(Vm.Log[] memory logs, bool debugLogging) public {
        relay(logs, bytes(""), debugLogging);
    }

    function relay(Vm.Log[] memory logs) public {
        relay(logs, bytes(""), false);
    }

    function vaaKeyMatchesVAA(
        VaaKey memory vaaKey,
        bytes memory signedVaa
    ) internal view returns (bool) {
        IWormhole.VM memory parsedVaa = relayerWormhole.parseVM(signedVaa);
        return
            (vaaKey.chainId == parsedVaa.emitterChainId) &&
            (vaaKey.emitterAddress == parsedVaa.emitterAddress) &&
            (vaaKey.sequence == parsedVaa.sequence);
    }

    function cctpKeyMatchesCCTPMessage(
        CCTPMessageLib.CCTPKey memory cctpKey,
        CCTPMessageLib.CCTPMessage memory cctpMessage
    ) internal view returns (bool) {
        (uint64 nonce,) = cctpMessage.message.asUint64(12);
        (uint32 domain,) = cctpMessage.message.asUint32(8);
        return
           nonce == cctpKey.nonce && domain == cctpKey.domain;
    }

    function relay(
        Vm.Log[] memory logs,
        bytes memory deliveryOverrides,
        bool debugLogging
    ) public {
        uint16 chainId = chainIdFromFork[vm.activeFork()];
        require(
            wormholeRelayerContracts[chainId] != address(0),
            "Chain not registered with MockOffchainRelayer"
        );

        vm.selectFork(forks[chainIdOfWormholeAndGuardianUtilities]);

        Vm.Log[] memory entries = relayerWormholeSimulator
            .fetchWormholeMessageFromLog(logs);

        if (debugLogging) {
            console.log("Found %s wormhole messages in logs", entries.length);
        }

        bytes[] memory encodedSignedVaas = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedSignedVaas.length; i++) {
            encodedSignedVaas[i] = relayerWormholeSimulator.fetchSignedMessageFromLogs(
                entries[i],
                chainId
            );
        }

        bool checkCCTP = relayerCircleSimulator.valid();
        Vm.Log[] memory cctpEntries = new Vm.Log[](0);
        if(checkCCTP) {
            cctpEntries = relayerCircleSimulator
            .fetchMessageTransmitterLogsFromLogs(logs);
        }

        if (debugLogging) {
            console.log("Found %s circle messages in logs", cctpEntries.length);
        }

        CCTPMessageLib.CCTPMessage[] memory circleSignedMessages = new CCTPMessageLib.CCTPMessage[](cctpEntries.length);
        for (uint256 i = 0; i < cctpEntries.length; i++) {
            circleSignedMessages[i] = relayerCircleSimulator.fetchSignedMessageFromLog(
                cctpEntries[i]
            );
        }

        IWormhole.VM[] memory parsed = new IWormhole.VM[](encodedSignedVaas.length);
        for (uint16 i = 0; i < encodedSignedVaas.length; i++) {
            parsed[i] = relayerWormhole.parseVM(encodedSignedVaas[i]);
        }
        for (uint16 i = 0; i < encodedSignedVaas.length; i++) {
            if (debugLogging) {
                console.log(
                    "Found VAA from chain %s emitted from %s",
                    parsed[i].emitterChainId,
                    fromWormholeFormat(parsed[i].emitterAddress)
                );
            }

            if (
                parsed[i].emitterAddress ==
                toWormholeFormat(wormholeRelayerContracts[chainId]) &&
                (parsed[i].emitterChainId == chainId)
            ) {
                if (debugLogging) {
                    console.log("Relaying VAA to chain %s", chainId);
                }
                vm.selectFork(forks[chainIdOfWormholeAndGuardianUtilities]);
                genericRelay(
                    encodedSignedVaas[i],
                    encodedSignedVaas,
                    circleSignedMessages,
                    parsed[i],
                    deliveryOverrides
                );
            }
        }

        vm.selectFork(forks[chainId]);
    }

    function relay(bytes memory deliveryOverrides) public {
        relay(vm.getRecordedLogs(), deliveryOverrides, false);
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
                    // clean this up
                    CCTPMessageLib.CCTPKey memory key = abi.decode(instruction.messageKeys[i].encodedKey, (CCTPMessageLib.CCTPKey));
                    for (uint8 j = 0; j < cctpMessages.length; j++) {
                        if (cctpKeyMatchesCCTPMessage(key, cctpMessages[j])) {
                            encodedSignedVaasToBeDelivered[i] = abi.encode(cctpMessages[j]);
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
            IWormholeRelayerDelivery(wormholeRelayerContracts[targetChain])
                .deliver{value: budget}(
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
                relayerWormhole.parseVM(oldEncodedDeliveryVAA).payload
            ).targetChain;

            vm.selectFork(forks[targetChain]);
            IWormholeRelayerDelivery(wormholeRelayerContracts[targetChain])
                .deliver{value: budget}(
                oldEncodedSignedVaas,
                oldEncodedDeliveryVAA,
                payable(address(this)),
                encode(deliveryOverride)
            );
        }
    }

    receive() external payable {}
}
