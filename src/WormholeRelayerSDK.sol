// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/ITokenBridge.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import "./Utils.sol";

import "forge-std/console.sol";

abstract contract Base {
    IWormholeRelayer public immutable wormholeRelayer;
    IWormhole public immutable wormhole;

    mapping(bytes32 => bool) seenDeliveryVaaHashes;

    address registrationOwner;
    mapping(uint16 => bytes32) registeredSenders;

    constructor(address _wormholeRelayer, address _wormhole) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        wormhole = IWormhole(_wormhole);
        registrationOwner = msg.sender;
    }

    modifier onlyWormholeRelayer() {
        require(msg.sender == address(wormholeRelayer), "Msg.sender is not Wormhole Relayer");
        _;
    }

    modifier replayProtect(bytes32 deliveryHash) {
        require(!seenDeliveryVaaHashes[deliveryHash], "Message already processed");
        seenDeliveryVaaHashes[deliveryHash] = true;
        _;
    }

    modifier isRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) {
        require(registeredSenders[sourceChain] == sourceAddress, "Not registered sender");
        _;
    }

    /**
     * Sets the registered address for 'sourceChain' to 'sourceAddress'
     * So that for messages from 'sourceChain', only ones from 'sourceAddress' are valid
     *
     * Assumes only one sender per chain is valid
     * Sender is the address that called 'send' on the Wormhole Relayer contract on the source chain)
     */
    function setRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) public {
        require(msg.sender == registrationOwner, "Not allowed to set registered sender");
        registeredSenders[sourceChain] = sourceAddress;
    }
}

abstract contract TokenBase is Base {
    ITokenBridge public immutable tokenBridge;

    constructor(address _wormholeRelayer, address _tokenBridge, address _wormhole) Base(_wormholeRelayer, _wormhole) {
        tokenBridge = ITokenBridge(_tokenBridge);
    }

    function getDecimals(address tokenAddress) internal view returns (uint8 decimals) {
        // query decimals
        (, bytes memory queriedDecimals) = address(tokenAddress).staticcall(abi.encodeWithSignature("decimals()"));
        decimals = abi.decode(queriedDecimals, (uint8));
    }

    function getTokenAddressOnThisChain(uint16 tokenHomeChain, bytes32 tokenHomeAddress)
        internal
        view
        returns (address tokenAddressOnThisChain)
    {
        return tokenHomeChain == wormhole.chainId()
            ? fromWormholeFormat(tokenHomeAddress)
            : tokenBridge.wrappedAsset(tokenHomeChain, tokenHomeAddress);
    }
}

abstract contract TokenSender is TokenBase {
    /**
     * transferTokens wraps common boilerplate for sending tokens to another chain using IWormholeRelayer
     * - approves tokenBridge to spend 'amount' of 'token'
     * - emits token transfer VAA
     * - returns VAA key for inclusion in WormholeRelayer `additionalVaas` argument
     *
     * Note: this function uses transferTokensWithPayload instead of transferTokens since the former requires that only the targetAddress
     *       can redeem transfers. Otherwise it's possible for another address to redeem the transfer before the targetContract is invoked by
     *       the offchain relayer and the target contract would have to be hardened against this.
     *
     */
    function transferTokens(address token, uint256 amount, uint16 targetChain, address targetAddress)
        internal
        returns (VaaKey memory)
    {
        return transferTokens(token, amount, targetChain, targetAddress, bytes(""));
    }

    /**
     * transferTokens wraps common boilerplate for sending tokens to another chain using IWormholeRelayer.
     * A payload can be included in the transfer vaa. By including a payload here instead of the deliveryVaa,
     * fewer trust assumptions are placed on the WormholeRelayer contract.
     *
     * - approves tokenBridge to spend 'amount' of 'token'
     * - emits token transfer VAA
     * - returns VAA key for inclusion in WormholeRelayer `additionalVaas` argument
     *
     * Note: this function uses transferTokensWithPayload instead of transferTokens since the former requires that only the targetAddress
     *       can redeem transfers. Otherwise it's possible for another address to redeem the transfer before the targetContract is invoked by
     *       the offchain relayer and the target contract would have to be hardened against this.
     */
    function transferTokens(
        address token,
        uint256 amount,
        uint16 targetChain,
        address targetAddress,
        bytes memory payload
    ) internal returns (VaaKey memory) {
        IERC20(token).approve(address(tokenBridge), amount);
        uint64 sequence = tokenBridge.transferTokensWithPayload{value: wormhole.messageFee()}(
            token, amount, targetChain, toWormholeFormat(targetAddress), 0, payload
        );
        return VaaKey({
            emitterAddress: toWormholeFormat(address(tokenBridge)),
            chainId: wormhole.chainId(),
            sequence: sequence
        });
    }

    function sendTokenWithPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        address token,
        uint256 amount
    ) internal returns (uint64) {
        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = transferTokens(token, amount, targetChain, targetAddress);

        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
        return wormholeRelayer.sendVaasToEvm{value: cost}(
            targetChain, targetAddress, payload, receiverValue, gasLimit, vaaKeys
        );
    }

    function sendTokenWithPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        address token,
        uint256 amount,
        uint16 refundChain,
        address refundAddress
    ) internal returns (uint64) {
        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = transferTokens(token, amount, targetChain, targetAddress);

        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
        return wormholeRelayer.sendVaasToEvm{value: cost}(
            targetChain, targetAddress, payload, receiverValue, gasLimit, vaaKeys, refundChain, refundAddress
        );
    }

    function forwardTokenWithPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint256 forwardMsgValue,
        address token,
        uint256 amount
    ) internal {
        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = transferTokens(token, amount, targetChain, targetAddress);

        wormholeRelayer.forwardVaasToEvm{value: forwardMsgValue}(
            targetChain, targetAddress, payload, receiverValue, gasLimit, vaaKeys
        );
    }
}

abstract contract TokenReceiver is TokenBase {
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
        TokenReceived[] memory receivedTokens = new TokenReceived[](additionalVaas.length);

        for (uint256 i = 0; i < additionalVaas.length; ++i) {
            IWormhole.VM memory parsed = wormhole.parseVM(additionalVaas[i]);
            require(
                parsed.emitterAddress == tokenBridge.bridgeContracts(parsed.emitterChainId), "Not a Token Bridge VAA"
            );
            ITokenBridge.TransferWithPayload memory transfer = tokenBridge.parseTransferWithPayload(parsed.payload);
            require(
                transfer.to == toWormholeFormat(address(this)) && transfer.toChain == wormhole.chainId(),
                "Token was not sent to this address"
            );

            tokenBridge.completeTransferWithPayload(additionalVaas[i]);

            address thisChainTokenAddress = getTokenAddressOnThisChain(transfer.tokenChain, transfer.tokenAddress);
            uint8 decimals = getDecimals(thisChainTokenAddress);
            uint256 denormalizedAmount = transfer.amount;
            if (decimals > 8) denormalizedAmount *= uint256(10) ** (decimals - 8);

            receivedTokens[i] = TokenReceived({
                tokenHomeAddress: transfer.tokenAddress,
                tokenHomeChain: transfer.tokenChain,
                tokenAddress: thisChainTokenAddress,
                amount: denormalizedAmount,
                amountNormalized: transfer.amount
            });
        }

        // call into overriden method
        receivePayloadAndTokens(payload, receivedTokens, sourceAddress, sourceChain, deliveryHash);
    }

    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}
}
