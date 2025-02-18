// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {
  IWormholeRelayerSend,
  VaaKey,
  MessageKey
} from "wormhole-sdk/interfaces/IWormholeRelayer.sol";

//This library should be used by integrators of WormholeRelayer to send messages, i.e.
//  initiate deliveries.
//
//Since WormholeRelayer only supports EVM for the foreseeable future, this library hides the
//  the more generic aspects that could some day be used to send messages to and receive deliveries
//  from non-EVM platforms.
//
//Writing a fully future-proof on-chain integration that will work for any platform that might be
//  added later on should be possible, but is quite tricky, exposes a lot more complexity, and
//  is hence generally not recommended. If you want to pursue this route regardless, you should
//  consider the more generic functions of IWormholeRelayer.

library WormholeRelayerSend {
  function quoteDeliveryPrice(
    address wormholeRelayer,
    uint16  targetChain,
    uint256 receiverValue,
    uint256 gasLimit
  ) internal view returns (
    uint256 nativePriceQuote,
    uint256 targetChainRefundPerGasUnused
  ) {
    return IWormholeRelayerSend(wormholeRelayer)
      .quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
  }

  function quoteDeliveryPrice(
    address wormholeRelayer,
    uint16  targetChain,
    uint256 receiverValue,
    uint256 gasLimit,
    address deliveryProvider
  ) internal view returns (
    uint256 nativePriceQuote,
    uint256 targetChainRefundPerGasUnused
  ) {
    return IWormholeRelayerSend(wormholeRelayer)
      .quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit, deliveryProvider);
  }

  function sendPayload(
    address wormholeRelayer,
    uint16  targetChain,
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 gasLimit
  ) internal returns (uint64 sequence) {
    return IWormholeRelayerSend(wormholeRelayer)
      .sendPayloadToEvm(targetChain, targetAddress, payload, receiverValue, gasLimit);
  }

  function send(
    address wormholeRelayer,
    uint16  targetChain,
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 gasLimit,
    uint16  refundChain,
    address refundAddress
  ) internal returns (uint64 sequence) {
    return IWormholeRelayerSend(wormholeRelayer)
      .sendPayloadToEvm(
        targetChain,
        targetAddress,
        payload,
        receiverValue,
        gasLimit,
        refundChain,
        refundAddress
      );
  }

  function send(
    address wormholeRelayer,
    uint16  targetChain,
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 gasLimit,
    VaaKey[] memory vaaKeys
  ) internal returns (uint64 sequence) {
    return IWormholeRelayerSend(wormholeRelayer)
      .sendVaasToEvm(targetChain, targetAddress, payload, receiverValue, gasLimit, vaaKeys);
  }

  function send(
    address wormholeRelayer,
    uint16  targetChain,
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 gasLimit,
    VaaKey[] memory vaaKeys,
    uint16  refundChain,
    address refundAddress
  ) internal returns (uint64 sequence) {
    return IWormholeRelayerSend(wormholeRelayer)
      .sendVaasToEvm(
        targetChain,
        targetAddress,
        payload,
        receiverValue,
        gasLimit,
        vaaKeys,
        refundChain,
        refundAddress
      );
  }

  function send(
    address wormholeRelayer,
    uint16  targetChain,
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 paymentForExtraReceiverValue,
    uint256 gasLimit,
    uint16  refundChain,
    address refundAddress,
    address deliveryProvider,
    VaaKey[] memory vaaKeys,
    uint8 consistencyLevel
  ) internal returns (uint64 sequence) {
    return IWormholeRelayerSend(wormholeRelayer).sendToEvm(
      targetChain,
      targetAddress,
      payload,
      receiverValue,
      paymentForExtraReceiverValue,
      gasLimit,
      refundChain,
      refundAddress,
      deliveryProvider,
      vaaKeys,
      consistencyLevel
    );
  }

  function send(
    address wormholeRelayer,
    uint16  targetChain,
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 paymentForExtraReceiverValue,
    uint256 gasLimit,
    uint16  refundChain,
    address refundAddress,
    address deliveryProvider,
    MessageKey[] memory messageKeys,
    uint8 consistencyLevel
  ) internal returns (uint64 sequence) {
    return IWormholeRelayerSend(wormholeRelayer).sendToEvm(
      targetChain,
      targetAddress,
      payload,
      receiverValue,
      paymentForExtraReceiverValue,
      gasLimit,
      refundChain,
      refundAddress,
      deliveryProvider,
      messageKeys,
      consistencyLevel
    );
  }
}
