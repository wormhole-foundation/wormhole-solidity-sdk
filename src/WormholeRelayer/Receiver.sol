// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IWormholeReceiver} from "wormhole-sdk/interfaces/IWormholeRelayer.sol";
import {eagerAnd} from "wormhole-sdk/Utils.sol";

abstract contract WormholeRelayerReceiver is IWormholeReceiver {
  error InvalidDelivery();

  address private immutable _wormholeRelayer;

  constructor(address wormholeRelayer) {
    _wormholeRelayer = wormholeRelayer;
  }

  //contracts form a peer network across chains and only messages from peers can be trusted
  function _isPeer(uint16 chainId, bytes32 peerAddress) internal virtual view returns (bool);
  
  //note: be sure to check msg.value in your implementation
  //see AdditionalMessages.sol for how to handle additional messages if applicable
  function _handleDelivery(
    bytes   calldata payload,
    bytes[] calldata additionalMessages,
    uint16  peerChainId,
    bytes32 peerAddress,
    bytes32 deliveryHash //WormholeRelayer already handles replay protection!
  ) internal virtual;

  //prevents spoofing by ensuring that:
  // 1. the delivery is coming from the actual WormholeRelayer contract
  // 2. the content of the delivery was published by a (known) peer
  function receiveWormholeMessages(
    bytes   calldata payload,
    bytes[] calldata additionalMessages,
    bytes32 emitterAddress,
    uint16  emitterChainId,
    bytes32 deliveryHash
  ) external payable {
    if (eagerAnd(msg.sender == _wormholeRelayer, _isPeer(emitterChainId, emitterAddress)))
      _handleDelivery(payload, additionalMessages, emitterChainId, emitterAddress, deliveryHash);
    else
      revert InvalidDelivery();
  }
}
