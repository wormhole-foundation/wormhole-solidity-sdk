// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {WormholeSimulator} from "./WormholeSimulator.sol";
import {toWormholeFormat} from "../../Utils.sol";
import "../../interfaces/IWormholeRelayer.sol";
import "../../interfaces/IWormhole.sol";
import "forge-std/Vm.sol";
import "./DeliveryInstructionDecoder.sol";
import "./ExecutionParameters.sol";
import "./BytesParsing.sol";
using BytesParsing for bytes;


contract MockOffchainRelayer {

    IWormhole relayerWormhole;
    WormholeSimulator relayerWormholeSimulator;

    Vm public vm;

    mapping(uint16 => address) wormholeRelayerContracts;

    mapping(uint16 => uint) forks;

    mapping(uint => uint16) chainIdFromFork;

    mapping(bytes32 => bytes[]) pastEncodedVMs;

    mapping(bytes32 => bytes) pastEncodedDeliveryVAA;

    constructor(address _wormhole, address _wormholeSimulator, Vm vm_) {
        relayerWormhole = IWormhole(_wormhole);
        relayerWormholeSimulator = WormholeSimulator(_wormholeSimulator);
        vm = vm_;
    }

    function getPastEncodedVMs(
        uint16 chainId,
        uint64 deliveryVAASequence
    ) public view returns (bytes[] memory) {
        return pastEncodedVMs[keccak256(abi.encodePacked(chainId, deliveryVAASequence))];
    }

    function getPastDeliveryVAA(
        uint16 chainId,
        uint64 deliveryVAASequence
    ) public view returns (bytes memory) {
        return pastEncodedDeliveryVAA[keccak256(abi.encodePacked(chainId, deliveryVAASequence))];
    }

    function setInfo(
        uint16 chainId,
        uint64 deliveryVAASequence,
        bytes[] memory encodedVMs,
        bytes memory encodedDeliveryVAA
    ) internal {
        pastEncodedVMs[keccak256(abi.encodePacked(chainId, deliveryVAASequence))] = encodedVMs;
        pastEncodedDeliveryVAA[keccak256(abi.encodePacked(chainId, deliveryVAASequence))] =
            encodedDeliveryVAA;
    }

    function registerChain(uint16 chainId, address wormholeRelayerContractAddress, uint fork) public {
        wormholeRelayerContracts[chainId] = wormholeRelayerContractAddress;
        forks[chainId] = fork;
        chainIdFromFork[fork] = chainId;
    }

    function relay() public {
        relay(vm.getRecordedLogs());
    }

    function relay(Vm.Log[] memory logs) public {
        relay(logs, bytes(""));
    }

    function vaaKeyMatchesVAA(
        VaaKey memory vaaKey,
        bytes memory signedVaa
    ) internal view returns (bool) {
        IWormhole.VM memory parsedVaa = relayerWormhole.parseVM(signedVaa);
        return (vaaKey.chainId == parsedVaa.emitterChainId)
            && (vaaKey.emitterAddress == parsedVaa.emitterAddress)
            && (vaaKey.sequence == parsedVaa.sequence);
    }

    function relay(Vm.Log[] memory logs, bytes memory deliveryOverrides) public {
       
        uint16 chainId = chainIdFromFork[vm.activeFork()];
        require(wormholeRelayerContracts[chainId] != address(0), "Chain not registered with MockOffchainRelayer");
        Vm.Log[] memory entries = relayerWormholeSimulator.fetchWormholeMessageFromLog(logs);
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = relayerWormholeSimulator.fetchSignedMessageFromLogs(
                entries[i], chainId
            );
        }
        IWormhole.VM[] memory parsed = new IWormhole.VM[](encodedVMs.length);
        for (uint16 i = 0; i < encodedVMs.length; i++) {
            parsed[i] = relayerWormhole.parseVM(encodedVMs[i]);
        }
        for (uint16 i = 0; i < encodedVMs.length; i++) {
            if (
                parsed[i].emitterAddress == toWormholeFormat(wormholeRelayerContracts[chainId])
                    && (parsed[i].emitterChainId == chainId)
            ) {
                genericRelay(encodedVMs[i], encodedVMs, parsed[i], deliveryOverrides);
            }
        }

        vm.selectFork(forks[chainId]);
    }

    function relay(bytes memory deliveryOverrides) public {
        relay(vm.getRecordedLogs(), deliveryOverrides);
    }

    function genericRelay(
        bytes memory encodedDeliveryVAA,
        bytes[] memory encodedVMs,
        IWormhole.VM memory parsedDeliveryVAA,
        bytes memory deliveryOverrides
    ) internal {
        (uint8 payloadId,) = parsedDeliveryVAA.payload.asUint8Unchecked(0);
        if (payloadId == 1) {
            DeliveryInstruction memory instruction =
                decodeDeliveryInstruction(parsedDeliveryVAA.payload);
            
            bytes[] memory encodedVMsToBeDelivered = new bytes[](instruction.vaaKeys.length);

            for (uint8 i = 0; i < instruction.vaaKeys.length; i++) {
                for (uint8 j = 0; j < encodedVMs.length; j++) {
                    if (vaaKeyMatchesVAA(instruction.vaaKeys[i], encodedVMs[j])) {
                        encodedVMsToBeDelivered[i] = encodedVMs[j];
                        break;
                    }
                }
            }
            
            EvmExecutionInfoV1 memory executionInfo =
                decodeEvmExecutionInfoV1(instruction.encodedExecutionInfo);
               
            uint256 budget = executionInfo.gasLimit * executionInfo.targetChainRefundPerGasUnused
                + instruction.requestedReceiverValue  + instruction.extraReceiverValue;

            uint16 targetChain = instruction.targetChain;
            
            vm.selectFork(forks[targetChain]);
           
            vm.deal(address(this), budget);

            IWormholeRelayerDelivery(wormholeRelayerContracts[targetChain]).deliver{
                value: budget
            }(
                encodedVMsToBeDelivered,
                encodedDeliveryVAA,
                payable(address(this)),
                deliveryOverrides
            );
            
            setInfo(
                parsedDeliveryVAA.emitterChainId,
                parsedDeliveryVAA.sequence,
                encodedVMsToBeDelivered,
                encodedDeliveryVAA
            );
            
        } else if (payloadId == 2) {
            RedeliveryInstruction memory instruction =
                 decodeRedeliveryInstruction(parsedDeliveryVAA.payload);

            DeliveryOverride memory deliveryOverride = DeliveryOverride({
                newExecutionInfo: instruction.newEncodedExecutionInfo,
                newReceiverValue: instruction.newRequestedReceiverValue,
                redeliveryHash: parsedDeliveryVAA.hash
            });

            EvmExecutionInfoV1 memory executionInfo =
                decodeEvmExecutionInfoV1(instruction.newEncodedExecutionInfo);
            uint256 budget = executionInfo.gasLimit * executionInfo.targetChainRefundPerGasUnused
                + instruction.newRequestedReceiverValue;

            bytes memory oldEncodedDeliveryVAA = getPastDeliveryVAA(
                instruction.deliveryVaaKey.chainId, instruction.deliveryVaaKey.sequence
            );
            bytes[] memory oldEncodedVMs = getPastEncodedVMs(
                instruction.deliveryVaaKey.chainId, instruction.deliveryVaaKey.sequence
            );

            uint16 targetChain = decodeDeliveryInstruction(
                relayerWormhole.parseVM(oldEncodedDeliveryVAA).payload
            ).targetChain;

            vm.selectFork(forks[targetChain]);
            IWormholeRelayerDelivery(wormholeRelayerContracts[targetChain]).deliver{
                value: budget
            }(
                oldEncodedVMs,
                oldEncodedDeliveryVAA,
                payable(address(this)),
                encode(deliveryOverride)
            );
        }
    }

    receive() external payable {}
}

