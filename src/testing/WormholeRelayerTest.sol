// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "wormhole-sdk/libraries/BytesParsing.sol";
import "wormhole-sdk/libraries/VaaLib.sol";
import "wormhole-sdk/libraries/CctpMessages.sol";
import "wormhole-sdk/testing/WormholeForkTest.sol";
import "wormhole-sdk/testing/WormholeRelayer/Structs.sol";

//everything is stored without signatures and only gets signed before delivery
struct Delivery {
  PublishedMessage deliveryPm;
  bytes[] additionalMessages; //stored as pointers to the structs
}

abstract contract WormholeRelayerTest is WormholeForkTest {
  using BytesParsing for bytes;
  using AdvancedWormholeOverride for ICoreBridge;
  using CctpOverride for IMessageTransmitter;
  using VaaLib for bytes;
  using CctpMessageLib for bytes;
  using WormholeRelayerStructsLib for bytes;

  using { toUniversalAddress } for address;

  //Right shifted ascii encoding of "WormholeRelayer"
  bytes32 private constant WORMHOLE_RELAYER_GOVERNANCE_MODULE =
    0x0000000000000000000000000000000000576f726d686f6c6552656c61796572;
  uint8 private constant WORMHOLE_RELAYER_GOVERNANCE_ACTION_UPDATE_DEFAULT_PROVIDER = 3;

  uint8 internal constant KEY_TYPE_VAA  = WormholeRelayerKeysLib.KEY_TYPE_VAA;
  uint8 internal constant KEY_TYPE_CCTP = WormholeRelayerKeysLib.KEY_TYPE_CCTP;

  //source chain -> sequence number -> delivery
  mapping(uint16 => mapping(uint64 => Delivery)) private _pastDeliveries;

  function deliver() internal {
    deliver(vm.getRecordedLogs());
  }

  function deliver(Vm.Log[] memory logs) internal {
    (Delivery[] memory deliveries, RedeliveryInstruction[] memory redeliveries) =
      logsToDeliveries(logs);

    for (uint i = 0; i < deliveries.length; ++i)
      deliver(deliveries[i]);

    for (uint i = 0; i < redeliveries.length; ++i)
      deliver(redeliveries[i]);
  }

  function deliver(Delivery memory delivery) internal {
    ( DeliveryInstruction memory deliveryIx,
      bytes memory deliveryVaa,
      bytes[] memory attestedMessages
    ) = _signDelivery(delivery);

    EvmExecutionInfoV1 memory executionInfo =
      deliveryIx.encodedExecutionInfo.decodeEvmExecutionInfoV1();

    uint256 deliverValue = deliveryIx.requestedReceiverValue + deliveryIx.extraReceiverValue +
      executionInfo.gasLimit * executionInfo.targetChainRefundPerGasUnused;

    _deliver(deliveryIx, delivery, deliveryVaa, attestedMessages, deliverValue, "");
  }

  function deliver(RedeliveryInstruction memory redelivery) internal {
    Delivery memory delivery =
      _pastDeliveries[redelivery.deliveryVaaKey.emitterChainId][redelivery.deliveryVaaKey.sequence];
    require(delivery.deliveryPm.envelope.timestamp != 0, "Delivery not found");

    EvmExecutionInfoV1 memory executionInfo =
      redelivery.newEncodedExecutionInfo.decodeEvmExecutionInfoV1();

    deliver(
      delivery,
      redelivery.newRequestedReceiverValue,
      executionInfo.gasLimit,
      executionInfo.targetChainRefundPerGasUnused
    );
  }

  function deliver(
    Delivery memory delivery,
    uint newReceiverValue,
    uint newGasLimit,
    uint newTargetChainRefundPerGasUnused
  ) internal {
    ( DeliveryInstruction memory deliveryIx,
      bytes memory deliveryVaa,
      bytes[] memory attestedMessages
    ) = _signDelivery(delivery);

    uint256 deliverValue = newReceiverValue + newGasLimit * newTargetChainRefundPerGasUnused;

    bytes memory encodedOverrides = DeliveryOverride({
      newExecutionInfo: EvmExecutionInfoV1(newGasLimit, newTargetChainRefundPerGasUnused).encode(),
      newReceiverValue: newReceiverValue,
      redeliveryHash: bytes32(uint(1)) //normally the hash of the redelivery vaa but irrelevant here
    }).encode();

    _deliver(deliveryIx, delivery, deliveryVaa, attestedMessages, deliverValue, encodedOverrides);
  }

  function logsToDeliveries(Vm.Log[] memory logs) internal view returns (
    Delivery[] memory deliveries,
    RedeliveryInstruction[] memory redeliveries
  ) {
    PublishedMessage[] memory pms = coreBridge().fetchPublishedMessages(logs);

    //count the number of deliveries and redeliveries
    uint deliveryCount = 0;
    uint redeliveryCount = 0;
    for (uint i = 0; i < pms.length; ++i) {
      if (pms[i].envelope.emitterAddress != address(wormholeRelayer()).toUniversalAddress())
        continue;

      bytes memory payload = pms[i].payload;
      (uint8 payloadId, ) = payload.asUint8MemUnchecked(0);
      if (payloadId == WormholeRelayerStructsLib.PAYLOAD_ID_DELIVERY_INSTRUCTION)
        ++deliveryCount;
      else
        ++redeliveryCount;
    }

    //allocate the arrays
    deliveries = new Delivery[](deliveryCount);
    redeliveries = new RedeliveryInstruction[](redeliveryCount);

    CctpTokenBurnMessage[] memory burnMsgs = cctpMessageTransmitter().fetchBurnMessages(logs);

    //populate the arrays
    uint deliveryIndex = 0;
    uint redeliveryIndex = 0;
    for (uint i = 0; i < pms.length; ++i) {
      if (pms[i].envelope.emitterAddress != address(wormholeRelayer()).toUniversalAddress())
        continue;

      bytes memory payload = pms[i].payload;
      (uint8 payloadId, ) = payload.asUint8MemUnchecked(0);
      if (payloadId == WormholeRelayerStructsLib.PAYLOAD_ID_DELIVERY_INSTRUCTION) {
        DeliveryInstruction memory deliveryIx = payload.decodeDeliveryInstruction();
        bytes[] memory additionalMessages = new bytes[](deliveryIx.messageKeys.length);
        uint additionalMessagesIndex = 0;
        for (uint j = 0; j < deliveryIx.messageKeys.length; ++j) {
          MessageKey memory messageKey = deliveryIx.messageKeys[j];
          require(
            messageKey.keyType == KEY_TYPE_VAA || messageKey.keyType == KEY_TYPE_CCTP,
            "Unknown message key type"
          );
          additionalMessages[additionalMessagesIndex++] =
            messageKey.keyType == KEY_TYPE_VAA
              ? _asPtr(_findPublishedMessage(messageKey.encodedKey.decodeVaaKey(), pms))
              : _asPtr(_findCctpMessage(messageKey.encodedKey.decodeCctpKey(), burnMsgs));
        }
        deliveries[deliveryIndex++] = Delivery({
          deliveryPm: pms[i],
          additionalMessages: additionalMessages
        });
      }
      else
        redeliveries[redeliveryIndex++] = payload.decodeRedeliveryInstruction();
    }
  }

  function updateDefaultDeliveryProvider(
    uint16 chain,
    address newDefaultDeliveryProvider
  ) internal preserveFork {
    selectFork(chain);
    (bool success, ) = address(wormholeRelayer()).call(abi.encodeWithSignature(
      "setDefaultDeliveryProvider(bytes)",
      coreBridge().sign(coreBridge().craftGovernancePublishedMessage(
        WORMHOLE_RELAYER_GOVERNANCE_MODULE,
        WORMHOLE_RELAYER_GOVERNANCE_ACTION_UPDATE_DEFAULT_PROVIDER,
        chain,
        abi.encodePacked(newDefaultDeliveryProvider.toUniversalAddress())
      )).encode()
    ));
    require(success, "Failed to update default provider");
  }

  //our contract acts as the delivery provider's relayer and also doubles as the refund address
  receive() external payable {}

  // ---- Private ----

  function _asPtr(PublishedMessage memory pm) private pure returns (bytes memory ret) {
    assembly ("memory-safe") { ret := pm }
  }

  function _asPtr(CctpTokenBurnMessage memory cctpMsg) private pure returns (bytes memory ret) {
    assembly ("memory-safe") { ret := cctpMsg }
  }

  function _asPublishedMessage(
    bytes memory ptr
  ) private pure returns (PublishedMessage memory pm) {
    assembly ("memory-safe") { pm := ptr }
  }

  function _asCctpTokenBurnMessage(
    bytes memory ptr
  ) private pure returns (CctpTokenBurnMessage memory cctpMsg) {
    assembly ("memory-safe") { cctpMsg := ptr }
  }

  function _findPublishedMessage(
    VaaKey memory vaaKey,
    PublishedMessage[] memory pms
  ) private pure returns (PublishedMessage memory) {
    for (uint k = 0; k < pms.length; ++k)
      if (_vaaKeyMatchesPublishedMessage(vaaKey, pms[k]))
        return pms[k];

    revert("Failed to find VAA");
  }

  function _vaaKeyMatchesPublishedMessage(
    VaaKey memory vaaKey,
    PublishedMessage memory pm
  ) private pure returns (bool) {
    return
      (vaaKey.emitterChainId == pm.envelope.emitterChainId) &&
      (vaaKey.emitterAddress == pm.envelope.emitterAddress) &&
      (vaaKey.sequence == pm.envelope.sequence);
  }

  function _findCctpMessage(
    CctpKey memory cctpKey,
    CctpTokenBurnMessage[] memory cctpMessages
  ) private pure returns (CctpTokenBurnMessage memory) {
    for (uint k = 0; k < cctpMessages.length; ++k)
      if (_cctpKeyMatchesCctpMessage(cctpKey, cctpMessages[k]))
        return cctpMessages[k];

    revert("Failed to find CCTP Message");
  }

  function _cctpKeyMatchesCctpMessage(
    CctpKey memory cctpKey,
    CctpTokenBurnMessage memory cctpMessage
  ) private pure returns (bool) {
    return
      (cctpKey.domain == cctpMessage.header.sourceDomain) &&
      (cctpKey.nonce  == cctpMessage.header.nonce);
  }

  function _signDelivery(Delivery memory delivery) private view returns (
    DeliveryInstruction memory deliveryIx,
    bytes memory deliveryVaa,
    bytes[] memory attestedMessages
  ) {
    deliveryIx = delivery.deliveryPm.payload.decodeDeliveryInstruction();
    deliveryVaa = coreBridge().sign(delivery.deliveryPm).encode();
    attestedMessages = new bytes[](deliveryIx.messageKeys.length);
    for (uint i = 0; i < deliveryIx.messageKeys.length; ++i) {
      MessageKey memory messageKey = deliveryIx.messageKeys[i];
      if (messageKey.keyType == KEY_TYPE_VAA)
        attestedMessages[i] =
          coreBridge().sign(_asPublishedMessage(delivery.additionalMessages[i])).encode();
      else {
        CctpTokenBurnMessage memory burnMsg =
          _asCctpTokenBurnMessage(delivery.additionalMessages[i]);
        bytes memory attestation = cctpMessageTransmitter().sign(burnMsg);
        attestedMessages[i] = abi.encode(burnMsg.encode(), attestation);
      }
    }
  }

  function _deliver(
    DeliveryInstruction memory deliveryIx,
    Delivery memory delivery,
    bytes memory deliveryVaa,
    bytes[] memory attestedMessages,
    uint256 deliverValue,
    bytes memory deliveryOverrides
  ) private preserveFork() {
    selectFork(deliveryIx.targetChain);
    wormholeRelayer().deliver{value: deliverValue}(
      attestedMessages,
      deliveryVaa,
      payable(address(this)),
      deliveryOverrides
    );
    _pastDeliveries[deliveryIx.targetChain][delivery.deliveryPm.envelope.sequence] = delivery;
  }
}
