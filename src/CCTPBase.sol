// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/ITokenBridge.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "./interfaces/CCTPInterfaces/ITokenMessenger.sol";
import "./interfaces/CCTPInterfaces/IMessageTransmitter.sol";

import "./Utils.sol";
import "./TokenBase.sol";

library CCTPMessageLib {
    uint8 constant CCTP_KEY_TYPE = 2;

    // encoded using abi.encodePacked(domain, nonce)
    struct CCTPKey {
        uint32 domain;
        uint64 nonce;
    }

    // encoded using abi.encode(message, signature)
    struct CCTPMessage {
        bytes message;
        bytes signature;
    }
}

abstract contract CCTPBase is TokenBase {
    ITokenMessenger immutable circleTokenMessenger;
    IMessageTransmitter immutable circleMessageTransmitter;
    address immutable USDC;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address _circleMessageTransmitter,
        address _circleTokenMessenger,
        address _USDC
    ) TokenBase(_wormholeRelayer, _tokenBridge, _wormhole) {
        circleTokenMessenger = ITokenMessenger(_circleTokenMessenger);
        circleMessageTransmitter = IMessageTransmitter(_circleMessageTransmitter);
        USDC = _USDC;
    }

    function getCCTPDomain(uint16 targetChain) internal pure returns (uint32) {
        if (targetChain == 2) {
            return 0;
        } else if (targetChain == 6) {
            return 1;
        } else if (targetChain == 23) {
            return 3;
        } else if (targetChain == 24) {
            return 2;
        } else {
            revert("Wrong CCTP Domain");
        }
    }

    function redeemUSDC(bytes memory cctpMessage) internal returns (uint256 amount) {
        (bytes memory message, bytes memory signature) = abi.decode(cctpMessage, (bytes, bytes));
        uint256 beforeBalance = IERC20(USDC).balanceOf(address(this));
        circleMessageTransmitter.receiveMessage(message, signature);
        return IERC20(USDC).balanceOf(address(this)) - beforeBalance;
    }
}

abstract contract CCTPSender is CCTPBase {
    uint8 internal constant CONSISTENCY_LEVEL_FINALIZED = 15;

    using CCTPMessageLib for *;

    /**
     * transferTokens wraps common boilerplate for sending tokens to another chain using IWormholeRelayer
     * - approves tokenBridge to spend 'amount' of 'token'
     * - emits token transfer VAA
     * - returns VAA key for inclusion in WormholeRelayer `additionalVaas` argument
     *
     * Note: this requires that only the targetAddress can redeem transfers.
     *
     */

    function transferUSDC(uint256 amount, uint16 targetChain, address targetAddress)
        internal
        returns (MessageKey memory)
    {
        IERC20(USDC).approve(address(circleTokenMessenger), amount);
        uint64 nonce = circleTokenMessenger.depositForBurnWithCaller(
            amount,
            getCCTPDomain(targetChain),
            addressToBytes32CCTP(targetAddress),
            USDC,
            addressToBytes32CCTP(targetAddress)
        );
        return MessageKey(
            CCTPMessageLib.CCTP_KEY_TYPE, abi.encodePacked(getCCTPDomain(targetChain), nonce)
        );
    }

    function sendUSDCWithPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint256 amount
    ) internal returns (uint64 sequence) {
        MessageKey[] memory messageKeys = new MessageKey[](1);
        messageKeys[0] = transferUSDC(amount, targetChain, targetAddress);

        bytes memory userPayload = abi.encode(amount, payload);
        address defaultDeliveryProvider = wormholeRelayer.getDefaultDeliveryProvider();

        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
        
        sequence = wormholeRelayer.sendToEvm{value: cost}(
            targetChain,
            targetAddress,
            userPayload,
            receiverValue,
            0,
            gasLimit,
            targetChain,
            address(0x0),
            defaultDeliveryProvider,
            messageKeys,
            CONSISTENCY_LEVEL_FINALIZED
        );
    }

    function addressToBytes32CCTP(address addr) private pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}

abstract contract CCTPReceiver is CCTPBase {
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        require(additionalMessages.length <= 1, "CCTP: At most one Message is supported");

        uint256 amountUSDCReceived;
        if (additionalMessages.length == 1) {
            amountUSDCReceived = redeemUSDC(additionalMessages[0]);
        }

        (uint256 amount, bytes memory userPayload) = abi.decode(payload, (uint256, bytes));

        // Check that the correct amount was received
        // It is important to verify that the 'USDC' received is
        require(amount == amountUSDCReceived, "Wrong amount received");

        receivePayloadAndUSDC(userPayload, amountUSDCReceived, sourceAddress, sourceChain, deliveryHash);
    }

    function receivePayloadAndUSDC(
        bytes memory payload,
        uint256 amountUSDCReceived,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}
}
