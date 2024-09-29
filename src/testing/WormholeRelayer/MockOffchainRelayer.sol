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
  using VaaEncoding for IWormhole.VM;
  using { toUniversalAddress } for address;
  using { fromUniversalAddress } for bytes32;

  Vm constant vm = Vm(VM_ADDRESS);

  mapping(uint16  => IWormhole)           wormholeContracts;
  mapping(uint16  => IMessageTransmitter) messageTransmitterContracts;
  mapping(uint16  => IWormholeRelayer)    wormholeRelayerContracts;
  mapping(uint16  => uint256)             forks;
  mapping(uint256 => uint16)              chainIdFromFork;
  mapping(bytes32 => bytes[])             pastEncodedVaas;
  mapping(bytes32 => bytes)               pastEncodedDeliveryVaa;

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

  function getPastEncodedVaas(
    uint16 chainId,
    uint64 deliveryVaaSequence
  ) public view returns (bytes[] memory) {
    return pastEncodedVaas[keccak256(abi.encodePacked(chainId, deliveryVaaSequence))];
  }

  function getPastDeliveryVaa(
    uint16 chainId,
    uint64 deliveryVaaSequence
  ) public view returns (bytes memory) {
    return pastEncodedDeliveryVaa[keccak256(abi.encodePacked(chainId, deliveryVaaSequence))];
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

  function cctpKeyMatchesCCTPMessage(
    CCTPMessageLib.CCTPKey memory cctpKey,
    CCTPMessageLib.CCTPMessage memory cctpMessage
  ) internal pure returns (bool) {
    (uint64 nonce,) = cctpMessage.message.asUint64(12);
    (uint32 domain,) = cctpMessage.message.asUint32(4);
    return nonce == cctpKey.nonce && domain == cctpKey.domain;
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
    for (uint256 i = 0; i < pms.length; ++i)
      vaas[i] = emitterWormhole.sign(pms[i]);

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
      if (debugLogging)
        console.log(
          "Found VAA from chain %s emitted from %s",
          vaas[i].emitterChainId,
          vaas[i].emitterAddress.fromUniversalAddress()
        );
      
      genericRelay(
        vaas[i],
        vaas,
        cctpSignedMsgs,
        deliveryOverrides
      );
    }
  }

  function storeDelivery(
    uint16 chainId,
    uint64 deliveryVaaSequence,
    bytes[] memory encodedVaas,
    bytes memory encodedDeliveryVaa
  ) internal {
    bytes32 key = keccak256(abi.encodePacked(chainId, deliveryVaaSequence));
    pastEncodedVaas[key] = encodedVaas;
    pastEncodedDeliveryVaa[key] = encodedDeliveryVaa;
  }

  function genericRelay(
    IWormhole.VM memory deliveryVaa,
    IWormhole.VM[] memory allVaas,
    CCTPMessageLib.CCTPMessage[] memory cctpMsgs,
    bytes memory deliveryOverrides
  ) internal {
    uint currentFork = vm.activeFork();

    (uint8 payloadId, ) = deliveryVaa.payload.asUint8Unchecked(0);
    if (payloadId == PAYLOAD_ID_DELIVERY_INSTRUCTION) {
      DeliveryInstruction memory instruction =
        decodeDeliveryInstruction(deliveryVaa.payload);

      bytes[] memory additionalMessages = new bytes[](instruction.messageKeys.length);
      for (uint8 i = 0; i < instruction.messageKeys.length; ++i) {
        if (instruction.messageKeys[i].keyType == VAA_KEY_TYPE) {
          (VaaKey memory vaaKey, ) =
            decodeVaaKey(instruction.messageKeys[i].encodedKey, 0);
          for (uint8 j = 0; j < allVaas.length; ++j)
            if (
              (vaaKey.chainId        == allVaas[j].emitterChainId) &&
              (vaaKey.emitterAddress == allVaas[j].emitterAddress) &&
              (vaaKey.sequence       == allVaas[j].sequence)
            ) {
              additionalMessages[i] = allVaas[j].encode();
              break;
            }
        }
        else if (instruction.messageKeys[i].keyType == CCTP_KEY_TYPE) {
          (CCTPMessageLib.CCTPKey memory key,) =
            decodeCCTPKey(instruction.messageKeys[i].encodedKey, 0);
          for (uint8 j = 0; j < cctpMsgs.length; ++j)
            if (cctpKeyMatchesCCTPMessage(key, cctpMsgs[j])) {
              additionalMessages[i] = abi.encode(cctpMsgs[j].message, cctpMsgs[j].signature);
              break;
            }
        }
        if (additionalMessages[i].length == 0)
          revert("Additional Message not found");
      }

      EvmExecutionInfoV1 memory executionInfo =
        decodeEvmExecutionInfoV1(instruction.encodedExecutionInfo);

      uint256 budget = executionInfo.gasLimit *
        executionInfo.targetChainRefundPerGasUnused +
        instruction.requestedReceiverValue +
        instruction.extraReceiverValue;

      uint16 targetChain = instruction.targetChain;

      vm.selectFork(forks[targetChain]);

      vm.deal(address(this), budget);

      vm.recordLogs();
      bytes memory encodedDeliveryVaa = deliveryVaa.encode();
      getForkWormholeRelayer().deliver{value: budget}(
        additionalMessages,
        encodedDeliveryVaa,
        payable(address(this)),
        deliveryOverrides
      );

      storeDelivery(
        deliveryVaa.emitterChainId,
        deliveryVaa.sequence,
        additionalMessages,
        encodedDeliveryVaa
      );
    }
    else if (payloadId == PAYLOAD_ID_REDELIVERY_INSTRUCTION) {
      RedeliveryInstruction memory instruction =
        decodeRedeliveryInstruction(deliveryVaa.payload);

      DeliveryOverride memory deliveryOverride = DeliveryOverride({
        newExecutionInfo: instruction.newEncodedExecutionInfo,
        newReceiverValue: instruction.newRequestedReceiverValue,
        redeliveryHash: deliveryVaa.hash
      });

      EvmExecutionInfoV1 memory executionInfo =
        decodeEvmExecutionInfoV1(instruction.newEncodedExecutionInfo);

      uint256 budget = executionInfo.gasLimit *
        executionInfo.targetChainRefundPerGasUnused +
        instruction.newRequestedReceiverValue;

      bytes memory oldEncodedDeliveryVaa = getPastDeliveryVaa(
        instruction.deliveryVaaKey.chainId,
        instruction.deliveryVaaKey.sequence
      );

      bytes[] memory oldEncodedVaas = getPastEncodedVaas(
        instruction.deliveryVaaKey.chainId,
        instruction.deliveryVaaKey.sequence
      );

      uint16 targetChain = decodeDeliveryInstruction(
        getForkWormhole().parseVM(oldEncodedDeliveryVaa).payload
      ).targetChain;

      vm.selectFork(forks[targetChain]);
      getForkWormholeRelayer().deliver{value: budget}(
        oldEncodedVaas,
        oldEncodedDeliveryVaa,
        payable(address(this)),
        encode(deliveryOverride)
      );
    }
    vm.selectFork(currentFork);
  }

  receive() external payable {}
}
