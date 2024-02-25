pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/ITokenBridge.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "./interfaces/CCTPInterfaces/ITokenMessenger.sol";
import "./interfaces/CCTPInterfaces/IMessageTransmitter.sol";

import "./Utils.sol";
import "./TokenBase.sol";
import "./CCTPBase.sol";

abstract contract CCTPAndTokenBase is CCTPBase {
    ITokenBridge public tokenBridge;

    enum Transfer {
        TOKEN_BRIDGE,
        CCTP
    }

    function _initCCTP(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address _circleMessageTransmitter,
        address _circleTokenMessenger,
        address _USDC
    )
    internal
    {
        _initCCTPBase(
            _wormholeRelayer,
            _wormhole,
            _circleMessageTransmitter,
            _circleTokenMessenger,
            _USDC
        );
        tokenBridge = ITokenBridge(_tokenBridge);
    }
}

abstract contract CCTPAndTokenSender is CCTPAndTokenBase {
    // CCTP Sender functions, taken from "./CCTPBase.sol"

    uint8 internal constant CONSISTENCY_LEVEL_FINALIZED = 15;

    using CCTPMessageLib for *;

    mapping(uint16 => uint32) public chainIdToCCTPDomain;

    /**
     * Sets the CCTP Domain corresponding to chain 'chain' to be 'cctpDomain'
     * So that transfers of USDC to chain 'chain' use the target CCTP domain 'cctpDomain'
     *
     * This action can only be performed by 'cctpConfigurationOwner', who is set to be the deployer
     *
     * Currently, cctp domains are:
     * Ethereum: Wormhole chain id 2, cctp domain 0
     * Avalanche: Wormhole chain id 6, cctp domain 1
     * Optimism: Wormhole chain id 24, cctp domain 2
     * Arbitrum: Wormhole chain id 23, cctp domain 3
     * Base: Wormhole chain id 30, cctp domain 6
     *
     * These can be set via:
     * setCCTPDomain(2, 0);
     * setCCTPDomain(6, 1);
     * setCCTPDomain(24, 2);
     * setCCTPDomain(23, 3);
     * setCCTPDomain(30, 6);
     */
    function setCCTPDomain(uint16 chain, uint32 cctpDomain) public {
        require(
            msg.sender == cctpConfigurationOwner,
            "Not allowed to set CCTP Domain"
        );
        chainIdToCCTPDomain[chain] = cctpDomain;
    }

    function getCCTPDomain(uint16 chain) internal view returns (uint32) {
        return chainIdToCCTPDomain[chain];
    }

    /**
     * transferUSDC wraps common boilerplate for sending tokens to another chain using IWormholeRelayer
     * - approves the Circle TokenMessenger contract to spend 'amount' of USDC
     * - calls Circle's 'depositForBurnWithCaller'
     * - returns key for inclusion in WormholeRelayer `additionalVaas` argument
     *
     * Note: this requires that only the targetAddress can redeem transfers.
     *
     */

    function transferUSDC(
        uint256 amount,
        uint16 targetChain,
        address targetAddress
    ) internal returns (MessageKey memory) {
        IERC20(USDC).approve(address(circleTokenMessenger), amount);
        bytes32 targetAddressBytes32 = addressToBytes32CCTP(targetAddress);
        uint64 nonce = circleTokenMessenger.depositForBurnWithCaller(
            amount,
            getCCTPDomain(targetChain),
            targetAddressBytes32,
            USDC,
            targetAddressBytes32
        );
        return
            MessageKey(
                CCTPMessageLib.CCTP_KEY_TYPE,
                abi.encodePacked(getCCTPDomain(wormhole.chainId()), nonce)
            );
    }

    // Publishes a CCTP transfer of 'amount' of USDC
    // and requests a delivery of the transfer along with 'payload' to 'targetAddress' on 'targetChain'
    //
    // The second step is done by publishing a wormhole message representing a request
    // to call 'receiveWormholeMessages' on the address 'targetAddress' on chain 'targetChain'
    // with the payload 'abi.encode(Transfer.CCTP, amount, payload)'
    // (we encode a Transfer enum to distinguish this from a TokenBridge transfer)
    // (and we encode the amount so it can be checked on the target chain)
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

        bytes memory userPayload = abi.encode(Transfer.CCTP, amount, payload);
        address defaultDeliveryProvider = wormholeRelayer
            .getDefaultDeliveryProvider();

        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            receiverValue,
            gasLimit
        );

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

    // TokenBridge Sender functions, taken from "./TokenBase.sol"

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
            toWormholeFormat(targetAddress),
            0,
            payload
        );
        return
            VaaKey({
                emitterAddress: toWormholeFormat(address(tokenBridge)),
                chainId: wormhole.chainId(),
                sequence: sequence
            });
    }

    // Publishes a wormhole message representing a 'TokenBridge' transfer of 'amount' of 'token'
    // and requests a delivery of the transfer along with 'payload' to 'targetAddress' on 'targetChain'
    //
    // The second step is done by publishing a wormhole message representing a request
    // to call 'receiveWormholeMessages' on the address 'targetAddress' on chain 'targetChain'
    // with the payload 'abi.encode(Transfer.TOKEN_BRIDGE, payload)'
    // (we encode a Transfer enum to distinguish this from a CCTP transfer)
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
                abi.encode(Transfer.TOKEN_BRIDGE, payload),
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
                abi.encode(Transfer.TOKEN_BRIDGE, payload),
                receiverValue,
                gasLimit,
                vaaKeys,
                refundChain,
                refundAddress
            );
    }
}

abstract contract CCTPAndTokenReceiver is CCTPAndTokenBase {
    function redeemUSDC(
        bytes memory cctpMessage
    ) internal returns (uint256 amount) {
        (bytes memory message, bytes memory signature) = abi.decode(
            cctpMessage,
            (bytes, bytes)
        );
        uint256 beforeBalance = IERC20(USDC).balanceOf(address(this));
        circleMessageTransmitter.receiveMessage(message, signature);
        return IERC20(USDC).balanceOf(address(this)) - beforeBalance;
    }

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
                ? fromWormholeFormat(tokenHomeAddress)
                : tokenBridge.wrappedAsset(tokenHomeChain, tokenHomeAddress);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        Transfer transferType = abi.decode(payload, (Transfer));
        if (transferType == Transfer.TOKEN_BRIDGE) {
            TokenReceived[] memory receivedTokens = new TokenReceived[](
                additionalMessages.length
            );

            for (uint256 i = 0; i < additionalMessages.length; ++i) {
                IWormhole.VM memory parsed = wormhole.parseVM(
                    additionalMessages[i]
                );
                require(
                    parsed.emitterAddress ==
                        tokenBridge.bridgeContracts(parsed.emitterChainId),
                    "Not a Token Bridge VAA"
                );
                ITokenBridge.TransferWithPayload memory transfer = tokenBridge
                    .parseTransferWithPayload(parsed.payload);
                require(
                    transfer.to == toWormholeFormat(address(this)) &&
                        transfer.toChain == wormhole.chainId(),
                    "Token was not sent to this address"
                );

                tokenBridge.completeTransferWithPayload(additionalMessages[i]);

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

            (, bytes memory userPayload) = abi.decode(
                payload,
                (Transfer, bytes)
            );

            // call into overriden method
            receivePayloadAndTokens(
                userPayload,
                receivedTokens,
                sourceAddress,
                sourceChain,
                deliveryHash
            );
        } else if (transferType == Transfer.CCTP) {
            // Currently, 'sendUSDCWithPayloadToEVM' only sends one CCTP transfer
            // That can be modified if the integrator desires to send multiple CCTP transfers
            // in which case the following code would have to be modified to support
            // redeeming these multiple transfers and checking that their 'amount's are accurate
            require(
                additionalMessages.length <= 1,
                "CCTP: At most one Message is supported"
            );

            uint256 amountUSDCReceived;
            if (additionalMessages.length == 1) {
                amountUSDCReceived = redeemUSDC(additionalMessages[0]);
            }

            (, uint256 amount, bytes memory userPayload) = abi.decode(
                payload,
                (Transfer, uint256, bytes)
            );

            // Check that the correct amount was received
            // It is important to verify that the 'USDC' sent in by the relayer is the same amount
            // that the sender sent in on the source chain
            require(amount == amountUSDCReceived, "Wrong amount received");

            receivePayloadAndUSDC(
                userPayload,
                amountUSDCReceived,
                sourceAddress,
                sourceChain,
                deliveryHash
            );
        } else {
            revert("Invalid transfer type");
        }
    }

    // Implement this function to handle in-bound deliveries that include a CCTP transfer
    function receivePayloadAndUSDC(
        bytes memory payload,
        uint256 amountUSDCReceived,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}

    // Implement this function to handle in-bound deliveries that include a TokenBridge transfer
    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal virtual {}
}
