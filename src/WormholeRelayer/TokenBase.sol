// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "wormhole-sdk/interfaces/IWormholeReceiver.sol";
import "wormhole-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-sdk/interfaces/ITokenBridge.sol";
import "wormhole-sdk/interfaces/token/IERC20.sol";
import "wormhole-sdk/Utils.sol";

import {Base} from "./Base.sol";

abstract contract TokenBase is Base {
    ITokenBridge public immutable tokenBridge;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole
    ) Base(_wormholeRelayer, _wormhole) {
        tokenBridge = ITokenBridge(_tokenBridge);
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
    function transferTokens(
        address token,
        uint256 amount,
        uint16 targetChain,
        address targetAddress
    ) internal returns (VaaKey memory) {
        return
            transferTokens(
                token,
                amount,
                targetChain,
                targetAddress,
                bytes("")
            );
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
        uint64 sequence = tokenBridge.transferTokensWithPayload{
            value: wormhole.messageFee()
        }(
            token,
            amount,
            targetChain,
            toUniversalAddress(targetAddress),
            0,
            payload
        );
        return
            VaaKey({
                emitterAddress: toUniversalAddress(address(tokenBridge)),
                chainId: wormhole.chainId(),
                sequence: sequence
            });
    }

    // Publishes a wormhole message representing a 'TokenBridge' transfer of 'amount' of 'token'
    // and requests a delivery of the transfer along with 'payload' to 'targetAddress' on 'targetChain'
    //
    // The second step is done by publishing a wormhole message representing a request
    // to call 'receiveWormholeMessages' on the address 'targetAddress' on chain 'targetChain'
    // with the payload 'payload'
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

        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            receiverValue,
            gasLimit
        );
        return
            wormholeRelayer.sendVaasToEvm{value: cost}(
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                vaaKeys
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

        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            receiverValue,
            gasLimit
        );
        return
            wormholeRelayer.sendVaasToEvm{value: cost}(
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
}

abstract contract TokenReceiver is TokenBase {
    struct TokenReceived {
        bytes32 tokenHomeAddress;
        uint16 tokenHomeChain;
        address tokenAddress; // wrapped address if tokenHomeChain !== this chain, else tokenHomeAddress (in evm address format)
        uint256 amount;
        uint256 amountNormalized; // if decimals > 8, normalized to 8 decimal places
    }

    function getDecimals(
        address tokenAddress
    ) internal view returns (uint8 decimals) {
        // query decimals
        (, bytes memory queriedDecimals) = address(tokenAddress).staticcall(
            abi.encodeWithSignature("decimals()")
        );
        decimals = abi.decode(queriedDecimals, (uint8));
    }

    function getTokenAddressOnThisChain(
        uint16 tokenHomeChain,
        bytes32 tokenHomeAddress
    ) internal view returns (address tokenAddressOnThisChain) {
        return
            tokenHomeChain == wormhole.chainId()
                ? fromUniversalAddress(tokenHomeAddress)
                : tokenBridge.wrappedAsset(tokenHomeChain, tokenHomeAddress);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        TokenReceived[] memory receivedTokens = new TokenReceived[](
            additionalVaas.length
        );

        for (uint256 i = 0; i < additionalVaas.length; ++i) {
            IWormhole.VM memory parsed = wormhole.parseVM(additionalVaas[i]);
            require(
                parsed.emitterAddress ==
                    tokenBridge.bridgeContracts(parsed.emitterChainId),
                "Not a Token Bridge VAA"
            );
            ITokenBridge.TransferWithPayload memory transfer = tokenBridge
                .parseTransferWithPayload(parsed.payload);
            require(
                transfer.to == toUniversalAddress(address(this)) &&
                    transfer.toChain == wormhole.chainId(),
                "Token was not sent to this address"
            );

            tokenBridge.completeTransferWithPayload(additionalVaas[i]);

            address thisChainTokenAddress = getTokenAddressOnThisChain(
                transfer.tokenChain,
                transfer.tokenAddress
            );
            uint8 decimals = getDecimals(thisChainTokenAddress);
            uint256 denormalizedAmount = transfer.amount;
            if (decimals > 8)
                denormalizedAmount *= uint256(10) ** (decimals - 8);

            receivedTokens[i] = TokenReceived({
                tokenHomeAddress: transfer.tokenAddress,
                tokenHomeChain: transfer.tokenChain,
                tokenAddress: thisChainTokenAddress,
                amount: denormalizedAmount,
                amountNormalized: transfer.amount
            });
        }

        // call into overriden method
        receivePayloadAndTokens(
            payload,
            receivedTokens,
            sourceAddress,
            sourceChain,
            deliveryHash
        );
    }

    // Implement this function to handle in-bound deliveries that include a TokenBridge transfer
    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}
}
