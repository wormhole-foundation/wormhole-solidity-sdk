// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "wormhole-sdk/testing/ForkTest.sol";
import "wormhole-sdk/testing/WormholeRelayerStructs.sol";

// abstract contract WormholeRelayerTest is ForkTest {
//   using { toUniversalAddress } for address;
//   using { fromUniversalAddress } for bytes32;

//   mapping(bytes32 => bytes[]) internal pastEncodedVaas;
//   mapping(bytes32 => bytes)   internal pastEncodedDeliveryVaa;


//   function getPastEncodedVaas(
//     uint16 chainId,
//     uint64 deliveryVaaSequence
//   ) public view returns (bytes[] memory) {
//     return pastEncodedVaas[keccak256(abi.encodePacked(chainId, deliveryVaaSequence))];
//   }

//   function getPastDeliveryVaa(
//     uint16 chainId,
//     uint64 deliveryVaaSequence
//   ) public view returns (bytes memory) {
//     return pastEncodedDeliveryVaa[keccak256(abi.encodePacked(chainId, deliveryVaaSequence))];
//   }

//   function cctpKeyMatchesCctpMessage(
//     CCTPKey memory cctpKey,
//     CctpMessage memory cctpMessage
//   ) internal pure returns (bool) {
//     (uint64 nonce,) = cctpMessage.message.asUint64Mem(12);
//     (uint32 domain,) = cctpMessage.message.asUint32Mem(4);
//     return nonce == cctpKey.nonce && domain == cctpKey.domain;
//   }

//   function relay(Vm.Log[] memory logs, bool debugLogging) public {
//     relay(logs, bytes(""), debugLogging);
//   }

//   function relay(
//     Vm.Log[] memory logs,
//     bytes memory deliveryOverrides,
//     bool debugLogging
//   ) public {
//     ICoreBridge emitterWormhole = getForkWormhole();
//     PublishedMessage[] memory pms = emitterWormhole.fetchPublishedMessages(logs);
//     if (debugLogging)
//       console.log(
//         "Found %s wormhole messages in logs from %s",
//         pms.length,
//         address(emitterWormhole)
//       );

//     Vaa[] memory vaas = new Vaa[](pms.length);
//     for (uint256 i = 0; i < pms.length; ++i)
//       vaas[i] = emitterWormhole.sign(pms[i]);

//     CCTPMessageLib.CCTPMessage[] memory cctpSignedMsgs = new CCTPMessageLib.CCTPMessage[](0);
//     IMessageTransmitter emitterMessageTransmitter = getForkMessageTransmitter();
//     if (address(emitterMessageTransmitter) != address(0)) {
//       CctpTokenBurnMessage[] memory burnMsgs =
//         emitterMessageTransmitter.fetchBurnMessages(logs);
//       if (debugLogging)
//         console.log(
//             "Found %s circle messages in logs from %s",
//             burnMsgs.length,
//             address(emitterMessageTransmitter)
//         );

//       cctpSignedMsgs = new CCTPMessageLib.CCTPMessage[](burnMsgs.length);
//       for (uint256 i = 0; i < cctpSignedMsgs.length; ++i) {
//         cctpSignedMsgs[i].message = burnMsgs[i].encode();
//         cctpSignedMsgs[i].signature = emitterMessageTransmitter.sign(burnMsgs[i]);
//       }
//     }

//     for (uint16 i = 0; i < vaas.length; ++i) {
//       uint16 chain = vaas[i].envelope.emitterChainId;
//       address emitter = vaas[i].envelope.emitterAddress.fromUniversalAddress();
//       if (debugLogging)
//         console.log("Found VAA from chain %s emitted from %s", chain, emitter);

//       if (emitter == address(wormholeRelayerContracts[chain])) {
//         if (debugLogging)
//           console.log("Relaying VAA to chain %s", chain);

//         genericRelay(
//           vaas[i],
//           vaas,
//           cctpSignedMsgs,
//           deliveryOverrides
//         );
//       }
//     }
//   }

//   function storeDelivery(
//     uint16 chainId,
//     uint64 deliveryVaaSequence,
//     bytes[] memory encodedVaas,
//     bytes memory encodedDeliveryVaa
//   ) internal {
//     bytes32 key = keccak256(abi.encodePacked(chainId, deliveryVaaSequence));
//     pastEncodedVaas[key] = encodedVaas;
//     pastEncodedDeliveryVaa[key] = encodedDeliveryVaa;
//   }

//   function genericRelay(
//     Vaa memory deliveryVaa,
//     Vaa[] memory allVaas,
//     CCTPMessageLib.CCTPMessage[] memory cctpMsgs,
//     bytes memory deliveryOverrides
//   ) internal {
//     uint currentFork = vm.activeFork();

//     (uint8 payloadId, ) = deliveryVaa.payload.asUint8MemUnchecked(0);
//     if (payloadId == PAYLOAD_ID_DELIVERY_INSTRUCTION) {
//       DeliveryInstruction memory instruction =
//         decodeDeliveryInstruction(deliveryVaa.payload);

//       bytes[] memory additionalMessages = new bytes[](instruction.messageKeys.length);
//       for (uint8 i = 0; i < instruction.messageKeys.length; ++i) {
//         if (instruction.messageKeys[i].keyType == VAA_KEY_TYPE) {
//           (VaaKey memory vaaKey, ) =
//             decodeVaaKey(instruction.messageKeys[i].encodedKey, 0);
//           for (uint8 j = 0; j < allVaas.length; ++j)
//             if (
//               (vaaKey.chainId        == allVaas[j].envelope.emitterChainId) &&
//               (vaaKey.emitterAddress == allVaas[j].envelope.emitterAddress) &&
//               (vaaKey.sequence       == allVaas[j].envelope.sequence)
//             ) {
//               additionalMessages[i] = allVaas[j].encode();
//               break;
//             }
//         }
//         else if (instruction.messageKeys[i].keyType == CCTP_KEY_TYPE) {
//           (CCTPMessageLib.CCTPKey memory key,) =
//             decodeCCTPKey(instruction.messageKeys[i].encodedKey, 0);
//           for (uint8 j = 0; j < cctpMsgs.length; ++j)
//             if (cctpKeyMatchesCCTPMessage(key, cctpMsgs[j])) {
//               additionalMessages[i] = abi.encode(cctpMsgs[j].message, cctpMsgs[j].signature);
//               break;
//             }
//         }
//         if (additionalMessages[i].length == 0)
//           revert("Additional Message not found");
//       }

//       EvmExecutionInfoV1 memory executionInfo =
//         decodeEvmExecutionInfoV1(instruction.encodedExecutionInfo);

//       uint256 budget = executionInfo.gasLimit *
//         executionInfo.targetChainRefundPerGasUnused +
//         instruction.requestedReceiverValue +
//         instruction.extraReceiverValue;

//       uint16 targetChain = instruction.targetChain;

//       vm.selectFork(forks[targetChain]);

//       vm.deal(address(this), budget);

//       vm.recordLogs();
//       bytes memory encodedDeliveryVaa = deliveryVaa.encode();
//       getForkWormholeRelayer().deliver{value: budget}(
//         additionalMessages,
//         encodedDeliveryVaa,
//         payable(address(this)),
//         deliveryOverrides
//       );

//       storeDelivery(
//         deliveryVaa.envelope.emitterChainId,
//         deliveryVaa.envelope.sequence,
//         additionalMessages,
//         encodedDeliveryVaa
//       );
//     }
//     else if (payloadId == PAYLOAD_ID_REDELIVERY_INSTRUCTION) {
//       RedeliveryInstruction memory instruction =
//         decodeRedeliveryInstruction(deliveryVaa.payload);

//       DeliveryOverride memory deliveryOverride = DeliveryOverride({
//         newExecutionInfo: instruction.newEncodedExecutionInfo,
//         newReceiverValue: instruction.newRequestedReceiverValue,
//         redeliveryHash: VaaLib.calcDoubleHash(deliveryVaa)
//       });

//       EvmExecutionInfoV1 memory executionInfo =
//         decodeEvmExecutionInfoV1(instruction.newEncodedExecutionInfo);

//       uint256 budget = executionInfo.gasLimit *
//         executionInfo.targetChainRefundPerGasUnused +
//         instruction.newRequestedReceiverValue;

//       bytes memory oldEncodedDeliveryVaa = getPastDeliveryVaa(
//         instruction.deliveryVaaKey.chainId,
//         instruction.deliveryVaaKey.sequence
//       );

//       bytes[] memory oldEncodedVaas = getPastEncodedVaas(
//         instruction.deliveryVaaKey.chainId,
//         instruction.deliveryVaaKey.sequence
//       );

//       uint16 targetChain = decodeDeliveryInstruction(
//         getForkWormhole().parseVM(oldEncodedDeliveryVaa).payload
//       ).targetChain;

//       vm.selectFork(forks[targetChain]);
//       getForkWormholeRelayer().deliver{value: budget}(
//         oldEncodedVaas,
//         oldEncodedDeliveryVaa,
//         payable(address(this)),
//         encode(deliveryOverride)
//       );
//     }
//     vm.selectFork(currentFork);
//   }

//   function performDelivery() public {
//     performDelivery(vm.getRecordedLogs(), false);
//   }

//   function performDelivery(bool debugLogging) public {
//     performDelivery(vm.getRecordedLogs(), debugLogging);
//   }

//   function performDelivery(Vm.Log[] memory logs) public {
//     performDelivery(logs, false);
//   }

//   function performDelivery(Vm.Log[] memory logs, bool debugLogging) public {
//     require(logs.length > 0, "no events recorded");
//     relay(logs, debugLogging);
//   }

//   receive() external payable {}
// }
