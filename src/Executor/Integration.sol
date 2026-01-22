// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {ICoreBridge}            from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {IExecutor,
        IExecutorQuoterRouter,
        IVaaV1Receiver}         from "wormhole-sdk/interfaces/IExecutor.sol";
import {CoreBridgeLib}          from "wormhole-sdk/libraries/CoreBridge.sol";
import {RequestLib}             from "wormhole-sdk/Executor/Request.sol";
import {RelayInstructionLib}    from "wormhole-sdk/Executor/RelayInstruction.sol";
import {toUniversalAddress}     from "wormhole-sdk/Utils.sol";

//abstract base contracts for typical Executor integrations
//
//executor supports off-chain and on-chain quoting so there are two flavors of send contracts.
//
//send-only contracts should inherit from exactly one of:
// * ExecutorSendQuoteOffChain
// * ExecutorSendQuoteOnChain
// * ExecutorSendQuoteBoth
//
//receive-only contracts should inherit from:
// * ExecutorReceive
//
//send-and-receive contracts should inherit from exactly one of:
// * ExecutorSendReceiveQuoteOffChain
// * ExecutorSendReceiveQuoteOnChain
// * ExecutorSendReceiveQuoteBoth
//
//note: The Impl contracts are a nuisance to deal with the diamond inheritance pattern and
//      the "Base constructor arguments given twice" error that comes with it.

// ╭─────────────────────────────╮
// │   WARNING: Receiving VAAs   │
// ╰─────────────────────────────╯
//
// When reciving a VAA, you must ensure:
//   1. The VAA was emitted by a known peer to prevent spoofing - see _checkPeer
//   2. The VAA was intended for this chain - see _checkDestination
//
// Emitter information is part of the VAA itself, but due to Wormhole's design as an attestion
//   mechanism, there is no destination chain in the VAA header itself.
// It is therefore up to the integrator to include such a field in message payloads of messages
//   with an intended target.

error InvalidPeer();
error DestinationMismatch();

abstract contract ExecutorSharedBase {
  ICoreBridge internal immutable _coreBridge;
  uint16      internal immutable _chainId;

  constructor(address coreBridge) {
    _coreBridge = ICoreBridge(coreBridge);
    _chainId = _coreBridge.chainId();
  }

  //should return bytes32(0) if there is no peer on the given chain
  function _getPeer(uint16 chainId) internal view virtual returns (bytes32);

  function _getExistingPeer(uint16 chainId) internal view virtual returns (bytes32 peer) {
    peer = _getPeer(chainId);
    if (peer == bytes32(0))
      revert InvalidPeer();
  }
}

abstract contract ExecutorSendBase is ExecutorSharedBase {
  function _publishAndCompose(
    bytes memory payload,
    uint8        consistencyLevel,
    uint256      totalCost, //must equal execution cost + Wormhole message fee for publishing!
    uint16       peerChain,
    uint128      gasLimit,
    uint128      msgVal,
    bytes memory extraRelayInstructions
  ) internal returns (
    uint64       sequence,
    bytes32      peerAddress,
    bytes memory relayInstructions,
    bytes memory requestBytes,
    uint256      executorFee
  ) {
    uint messageFee = _coreBridge.messageFee();
    uint32 nonce = 0; //unused
    sequence = _coreBridge.publishMessage{value: messageFee}(nonce, payload, consistencyLevel);

    relayInstructions = RelayInstructionLib.encodeGas(gasLimit, msgVal);
    if (extraRelayInstructions.length > 0)
      relayInstructions = abi.encodePacked(relayInstructions, extraRelayInstructions);

    peerAddress = _getExistingPeer(peerChain);
    requestBytes =
      RequestLib.encodeVaaMultiSigRequest(_chainId, toUniversalAddress(address(this)), sequence);

    //value calculation is unchecked because executor call will fail on underflow anyway
    unchecked { executorFee = totalCost - messageFee; }
  }
}

abstract contract ExecutorSendQuoteOffChainImpl is ExecutorSendBase {
  IExecutor internal immutable _executor;

  constructor(address executor) {
    _executor = IExecutor(executor);
  }

  function _publishAndRelay(
    bytes memory   payload,
    uint8          consistencyLevel,
    uint256        totalCost, //must equal execution cost + Wormhole message fee for publishing!
    uint16         peerChain,
    address        refundAddress,
    bytes calldata signedQuote,
    uint128        gasLimit,
    uint128        msgVal,
    bytes memory   extraRelayInstructions
  ) internal returns (uint64 sequence) { unchecked {
    ( uint64 sequence_,
      bytes32 peerAddress,
      bytes memory relayInstructions,
      bytes memory requestBytes,
      uint256 executorFee
    ) = _publishAndCompose(
      payload,
      consistencyLevel,
      totalCost, peerChain,
      gasLimit,
      msgVal,
      extraRelayInstructions
    );

    _executor.requestExecution{value: executorFee}(
      peerChain,
      peerAddress,
      refundAddress,
      signedQuote,
      requestBytes,
      relayInstructions
    );

    sequence = sequence_;
  }}
}

abstract contract ExecutorSendQuoteOnChainImpl is ExecutorSendBase {
  IExecutorQuoterRouter internal immutable _executorQuoterRouter;

  constructor(address executorQuoterRouter) {
    _executorQuoterRouter = IExecutorQuoterRouter(executorQuoterRouter);
  }

  function _publishAndRelay(
    bytes memory payload,
    uint8        consistencyLevel,
    uint256      totalCost, //must equal execution cost + Wormhole message fee for publishing!
    uint16       peerChain,
    address      refundAddress,
    address      quoterAddress,
    uint128      gasLimit,
    uint128      msgVal,
    bytes memory extraRelayInstructions
  ) internal returns (uint64 sequence) { unchecked {
    ( uint64 sequence_,
      bytes32 peerAddress,
      bytes memory relayInstructions,
      bytes memory requestBytes,
      uint256 executorFee
    ) = _publishAndCompose(
      payload,
      consistencyLevel,
      totalCost, peerChain,
      gasLimit,
      msgVal,
      extraRelayInstructions
    );

    _executorQuoterRouter.requestExecution{value: executorFee}(
      peerChain,
      peerAddress,
      refundAddress,
      quoterAddress,
      requestBytes,
      relayInstructions
    );

    sequence = sequence_;
  }}
}

abstract contract ExecutorReceiveImpl is ExecutorSharedBase, IVaaV1Receiver {
  //default impl as safeguard - integrators should override this with an empty impl and perform
  //  appropriate check in their impl of _executeVaa instead, if they allow for non-zero msg.value
  function _executeVaaDefaultMsgValueCheck() internal virtual {
    require(msg.value == 0);
  }

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

  //ATTENTION: You typically want to ensure that a VAA is intended for this chain
  //             to protect against VAA submission on other chains.
  function _checkDestination(uint16 destinationChainId) internal view virtual {
    if (destinationChainId != _chainId)
      revert DestinationMismatch();
  }

  //ATTENTION: You must ensure that the emitter of the VAA does indeed match a known
  //             peer to prevent spoofing.
  function _checkPeer(uint16 chainId, bytes32 peerAddress) internal view virtual {
    if (_getPeer(chainId) != peerAddress)
      revert InvalidPeer();
  }

  function executeVAAv1(bytes calldata multiSigVaa) external payable virtual {
    _executeVaaDefaultMsgValueCheck();

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

abstract contract ExecutorSendQuoteOffChain is ExecutorSharedBase, ExecutorSendQuoteOffChainImpl {
  constructor(address coreBridge, address executor)
    ExecutorSharedBase(coreBridge)
    ExecutorSendQuoteOffChainImpl(executor) {}
}

abstract contract ExecutorSendQuoteOnChain is ExecutorSharedBase, ExecutorSendQuoteOnChainImpl {
  constructor(address coreBridge, address executorQuoterRouter)
    ExecutorSharedBase(coreBridge)
    ExecutorSendQuoteOnChainImpl(executorQuoterRouter) {}
}

abstract contract ExecutorSendQuoteBoth is
  ExecutorSharedBase, ExecutorSendQuoteOffChainImpl, ExecutorSendQuoteOnChainImpl {
  constructor(address coreBridge, address executor, address executorQuoterRouter)
    ExecutorSharedBase(coreBridge)
    ExecutorSendQuoteOffChainImpl(executor)
    ExecutorSendQuoteOnChainImpl(executorQuoterRouter) {}
}

abstract contract ExecutorReceive is ExecutorSharedBase, ExecutorReceiveImpl {
  constructor(address coreBridge)
    ExecutorSharedBase(coreBridge) {}
}

abstract contract ExecutorSendReceiveQuoteOffChain is
    ExecutorSharedBase, ExecutorSendQuoteOffChainImpl, ExecutorReceiveImpl {
  constructor(address coreBridge, address executor)
    ExecutorSharedBase(coreBridge)
    ExecutorSendQuoteOffChainImpl(executor) {}
}

abstract contract ExecutorSendReceiveQuoteOnChain is
    ExecutorSharedBase, ExecutorSendQuoteOnChainImpl, ExecutorReceiveImpl {
  constructor(address coreBridge, address executorQuoterRouter)
    ExecutorSharedBase(coreBridge)
    ExecutorSendQuoteOnChainImpl(executorQuoterRouter) {}
}

abstract contract ExecutorSendReceiveQuoteBoth is ExecutorReceiveImpl, ExecutorSendQuoteBoth {
  constructor(address coreBridge, address executor, address executorQuoterRouter)
    ExecutorSendQuoteBoth(coreBridge, executor, executorQuoterRouter) {}
}
