// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/ITokenBridge.sol";
import "./interfaces/IERC20.sol";

import "./Utils.sol";

import "forge-std/console.sol";

abstract contract Base {
    IWormholeRelayer public immutable wormholeRelayer;

    mapping(bytes32 => bool) seenDeliveryVaaHashes;

    address owner;
    mapping(uint16 => bytes32) registeredSenders;

    constructor(address _wormholeRelayer) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        owner = msg.sender;
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
        require(msg.sender == owner, "Not allowed to set registered sender");
        registeredSenders[sourceChain] = sourceAddress;
    }
}

abstract contract TokenBase is Base {
    ITokenBridge public immutable tokenBridge;
    IWormhole public immutable wormhole;

    constructor(address _wormholeRelayer, address _tokenBridge, address _wormhole) Base(_wormholeRelayer) {
        tokenBridge = ITokenBridge(_tokenBridge);
        wormhole = IWormhole(_wormhole);
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
        uint256 cost,
        address token,
        uint256 amount
    ) internal returns (uint64) {
        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = transferTokens(token, amount, targetChain, targetAddress);

        return wormholeRelayer.sendVaasToEvm{value: cost}(
            targetChain,
            targetAddress,
            payload,
            receiverValue,
            gasLimit,
            vaaKeys
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
            targetChain,
            targetAddress,
            payload,
            receiverValue,
            gasLimit,
            vaaKeys
        );
    }
}

abstract contract TokenReceiver is TokenBase {
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        ITokenBridge.TransferWithPayload[] memory transfers =
            new ITokenBridge.TransferWithPayload[](additionalVaas.length);

        for (uint256 i = 0; i < additionalVaas.length; ++i) {
            IWormhole.VM memory parsed = wormhole.parseVM(additionalVaas[i]);
            require (parsed.emitterAddress == tokenBridge.bridgeContracts(parsed.emitterChainId), "Not a Token Bridge VAA");
            ITokenBridge.TransferWithPayload memory transfer = tokenBridge.parseTransferWithPayload(parsed.payload);
            require (transfer.to == toWormholeFormat(address(this)) && transfer.toChain == wormhole.chainId(), "Token was not sent to this address");   

            tokenBridge.completeTransferWithPayload(additionalVaas[i]);
            transfers[i] = transfer;
        }
        
        // call into overriden method 
        receivePayloadAndTokens(payload, transfers, sourceAddress, sourceChain, deliveryHash);
    }

    function receivePayloadAndTokens(
        bytes memory payload,
        ITokenBridge.TransferWithPayload[] memory transfers,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}

    function receivePayload(
        bytes memory payload,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}
}
