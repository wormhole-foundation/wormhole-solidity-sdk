// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {ICoreBridge}               from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {IExecutor, IVaaV1Receiver} from "wormhole-sdk/interfaces/IExecutor.sol";
import {CoreBridgeLib}             from "wormhole-sdk/libraries/CoreBridge.sol";
import {RequestLib}                from "wormhole-sdk/Executor/Request.sol";
import {RelayInstructionLib}       from "wormhole-sdk/Executor/RelayInstruction.sol";
import {toUniversalAddress}        from "wormhole-sdk/Utils.sol";

//abstract base contracts for typical Executor integrations

abstract contract ExecutorSharedBase {
  error InvalidPeer();

  ICoreBridge internal immutable _coreBridge;

  constructor(address coreBridge) {
    _coreBridge = ICoreBridge(coreBridge);
  }

  //should return bytes32(0) if there is no peer on the given chain
  function _getPeer(uint16 chainId) internal view virtual returns (bytes32);

  function _getExistingPeer(uint16 chainId) internal view virtual returns (bytes32 peer) {
    peer = _getPeer(chainId);
    if (peer == bytes32(0))
      revert InvalidPeer();
  }
}

abstract contract ExecutorSend is ExecutorSharedBase {
  IExecutor   internal immutable _executor;
  uint16      internal immutable _chainId;

  constructor(address coreBridge, address executor) ExecutorSharedBase(coreBridge) {
    _executor = IExecutor(executor);
    _chainId = _coreBridge.chainId();
  }

  function _publishAndRelay(
    bytes memory payload,
    uint8 consistencyLevel,
    uint256 totalCost, //must equal execution cost + Wormhole message fee for publishing!
    uint16 peerChain,
    address refundAddress,
    bytes calldata signedQuote,
    uint128 gasLimit,
    uint128 msgVal,
    bytes memory extraRelayInstructions
  ) internal returns (uint64 sequence) { unchecked {
    uint messageFee = _coreBridge.messageFee();
    uint32 nonce = 0; //unused
    sequence = _coreBridge.publishMessage{value: messageFee}(nonce, payload, consistencyLevel);

    bytes memory relayInstructions = RelayInstructionLib.encodeGas(gasLimit, msgVal);
    if (extraRelayInstructions.length > 0)
      relayInstructions = abi.encodePacked(relayInstructions, extraRelayInstructions);

    bytes32 peerAddress = _getExistingPeer(peerChain);

    //value calculation is unchecked because call will fail on underflow anyway
    _executor.requestExecution{value: totalCost - messageFee}(
      peerChain,
      peerAddress,
      refundAddress,
      signedQuote,
      RequestLib.encodeVaaMultiSigRequest(_chainId, toUniversalAddress(address(this)), sequence),
      relayInstructions
    );
  }}
}

abstract contract ExecutorReceive is ExecutorSharedBase, IVaaV1Receiver {
  constructor(address coreBridge) ExecutorSharedBase(coreBridge) {}

  //impl via the appropriate replay protection library from ReplayProtectionLib.sol
  function _replayProtect(
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    bytes calldata encodedVaa
  ) internal virtual;

  //WARNING: must correctly handle non-zero msg.value (since invoking function is payable)
  function _executeVaa(
    bytes calldata payload,
    uint32  timestamp,
    uint16  peerChain,
    bytes32 peerAddress,
    uint64  sequence,
    uint8   consistencyLevel
  ) internal virtual;

  function _checkPeer(uint16 chainId, bytes32 peerAddress) internal view virtual {
    if (_getPeer(chainId) != peerAddress)
      revert InvalidPeer();
  }

  function executeVAAv1(bytes calldata multiSigVaa) external payable virtual {
    ( uint32  timestamp,
      , //nonce is ignored
      uint16  emitterChainId,
      bytes32 emitterAddress,
      uint64  sequence,
      uint8   consistencyLevel,
      bytes calldata payload
    ) = CoreBridgeLib.decodeAndVerifyVaaCd(address(_coreBridge), multiSigVaa);

    _checkPeer(emitterChainId, emitterAddress);
    _replayProtect(emitterChainId, emitterAddress, sequence, multiSigVaa);

    _executeVaa(
      payload,
      timestamp,
      emitterChainId,
      emitterAddress,
      sequence,
      consistencyLevel
    );
  }
}
