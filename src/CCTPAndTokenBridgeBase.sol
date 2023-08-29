// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/ITokenBridge.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "./interfaces/CCTPInterfaces/ITokenMessenger.sol";
import "./interfaces/CCTPInterfaces/IMessageTransmitter.sol";

import "./Utils.sol";
import "./Base.sol";



abstract contract CCTPAndTokenBridgeBase is Base {
    ITokenBridge immutable tokenBridge;
    ITokenMessenger immutable circleTokenMessenger;
    IMessageTransmitter immutable circleMessageTransmitter;

    constructor(address _wormholeRelayer, address _tokenBridge, address _wormhole, address _circleMessageTransmitter, address _circleTokenMessenger) Base(_wormholeRelayer, _wormhole) {
        tokenBridge = ITokenBridge(_tokenBridge);
        circleTokenMessenger = ITokenMessenger(_circleTokenMessenger);
        circleMessageTransmitter = IMessageTransmitter(_circleMessageTransmitter);
    }

    function getCCTPDomain(uint16 targetChain) internal pure returns (uint32) {
       if(targetChain == 2) {
          return 0;
       } else if(targetChain == 6) {
          return 1;
       } else { // TODO: Add arbitrum and optimism {
         revert("Wrong CCTP Domain");
       }
    }

}


abstract contract CCTPSender is CCTPAndTokenBridgeBase {
    uint8 internal constant CONSISTENCY_LEVEL_FINALIZED = 15;
    /**
     * transferTokens wraps common boilerplate for sending tokens to another chain using IWormholeRelayer
     * - approves tokenBridge to spend 'amount' of 'token'
     * - emits token transfer VAA
     * - returns VAA key for inclusion in WormholeRelayer `additionalVaas` argument
     *
     * Note: this requires that only the targetAddress can redeem transfers.
     *
     */
    function transferCircle(address token, uint256 amount, uint16 targetChain, address targetAddress)
        internal
        returns (MessageKey memory)
    {
        uint64 nonce = circleTokenMessenger.depositForBurnWithCaller(
            amount,
            getCCTPDomain(targetChain),
            toWormholeFormat(targetAddress),
            token,
            toWormholeFormat(targetAddress)
        );
        return MessageKey(
            2, abi.encodePacked(nonce, getCCTPDomain(wormhole.chainId())) // fix this encoding TODO!
        );
    }

    function sendCircleWithPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        address token,
        uint256 amount
    ) internal returns (uint64) {
        MessageKey[] memory messageKeys = new MessageKey[](1);
        messageKeys[0] = transferCircle(token, amount, targetChain, targetAddress);

        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
        return wormholeRelayer.sendToEvm{value: cost}(
            targetChain, targetAddress, payload, receiverValue, 0, gasLimit, targetChain, address(0x0), wormholeRelayer.getDefaultDeliveryProvider(), messageKeys, CONSISTENCY_LEVEL_FINALIZED
        );
    }
}

abstract contract CCTPReceiver is CCTPAndTokenBridgeBase {
    struct TokenReceived {
        bytes32 tokenHomeAddress;
        uint16 tokenHomeChain;
        address tokenAddress; // wrapped address if tokenHomeChain !== this chain, else tokenHomeAddress (in evm address format)
        uint256 amount;
        uint256 amountNormalized; // if decimals > 8, normalized to 8 decimal places
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
  
    }

    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}
}
