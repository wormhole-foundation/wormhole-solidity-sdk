// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {IERC20} from "IERC20/IERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {ITokenBridge} from "wormhole-sdk/interfaces/ITokenBridge.sol";
import {TokenBridgeMessageLib, TokenBridgeTransferWithPayload} from "wormhole-sdk/libraries/TokenBridgeMessages.sol";
import {Percentage, PercentageLib} from "wormhole-sdk/libraries/Percentage.sol";
import "src/utils/DecimalNormalization.sol";

// Example contract to interact with Wormhole WTT Bridge contract
// See more in https://wormhole.com/docs/products/token-transfers/wrapped-token-transfers/overview/
contract ExampleWTTBridgeIntegration {
    using SafeERC20 for IERC20;
    using TokenBridgeMessageLib for bytes;

    // Wormhole core bridge contract
    ICoreBridge public coreBridge;

    // WTT bridge contract
    // Source code: https://github.com/wormhole-foundation/wormhole/blob/tree/ethereum/contracts/bridge/Bridge.sol
    ITokenBridge public tokenBridge;

    // Owner of the contract
    address public owner;

    // Fee recipient address
    address public feeRecipient;

    // Map of whitelisted senders that is exempted from the inbound fees
    mapping(uint16 => bytes32) public whitelistedSenders;

    // Fee amount charged when sending messages outbound
    Percentage public outboundFeePercentage;

    // Fee amount charged when receiving inbound messages
    Percentage public inboundFeePercentage;

    constructor(
        address coreBridgeAddress,
        address tokenBridgeAddress,
        address ownerAddress,
        address feeRecipientAddress,
        uint16 outboundFeeMantissa,
        uint16 outboundFeeDigits,
        uint16 inboundFeeMantissa,
        uint16 inboundFeeDigits
    ) {
        coreBridge = ICoreBridge(coreBridgeAddress);
        tokenBridge = ITokenBridge(tokenBridgeAddress);

        require(ownerAddress != address(0), "Invalid address");
        require(feeRecipientAddress != address(0), "Invalid address");

        owner = ownerAddress;
        feeRecipient = feeRecipientAddress;

        // Use PercentageLib.to() to create the Percentage type
        // Example: to(50, 2) = 0.50%, to(100, 2) = 1.00%, to(5, 1) = 0.5%
        outboundFeePercentage = PercentageLib.to(
            outboundFeeMantissa,
            outboundFeeDigits
        );
        inboundFeePercentage = PercentageLib.to(
            inboundFeeMantissa,
            inboundFeeDigits
        );
    }

    // Entry point for transferring ETH without payload (i.e., a simple ETH transfer)
    // See https://wormhole.com/docs/products/token-transfers/wrapped-token-transfers/concepts/payload-structure/#transfer
    function transferETHWithoutPayload(
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable {
        // incur fees from ETH
        uint256 sentAmount = msg.value;
        uint256 feeAmount = calculateOutboundFee(sentAmount);

        (bool success, ) = feeRecipient.call{value: feeAmount}("");
        require(success);

        // Calculate remaining amount
        uint256 remainingAmount = sentAmount - feeAmount;

        tokenBridge.wrapAndTransferETH{value: remainingAmount}(
            recipientChain,
            recipient,
            arbiterFee,
            nonce
        );

        // Refund potential dust to caller
        // see https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L129-L144 and https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L83
        uint balance = address(this).balance;
        if (balance > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: balance}("");
            require(refundSuccess);
        }
    }

    // Entry point for transferring ETH with payload
    // Payloads are arbitrary data that can be attached to the transfer to perform designed operations in the destination chain (e.g., automatically swap tokens when received on the destination chain)
    // See https://wormhole.com/docs/products/token-transfers/wrapped-token-transfers/concepts/payload-structure/#transferwithpayload
    function transferETHWithPayload(
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce,
        bytes memory payload
    ) external payable {
        // incur fees from ETH
        uint256 sentAmount = msg.value;
        uint256 feeAmount = calculateOutboundFee(sentAmount);

        (bool success, ) = feeRecipient.call{value: feeAmount}("");
        require(success);

        // calculate remaining amount
        uint256 remainingAmount = sentAmount - feeAmount;

        tokenBridge.wrapAndTransferETHWithPayload{value: remainingAmount}(
            recipientChain,
            recipient,
            nonce,
            payload
        );

        // Refund potential dust to caller
        // see https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L129-L144 and https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L115
        uint balance = address(this).balance;
        if (balance > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: balance}("");
            require(refundSuccess);
        }
    }

    // Entry point to receive cross-chain messages from the source chain
    // Since the message was dispatched as payload ID 3 using the `wrapAndTransferETHWithPayload` entry point, only the specified `recipient` address can withdraw the funds from the WTT bridge contract (see https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/ethereum/contracts/bridge/Bridge.sol#L505-L507). This ensures that no one can manually redeem the funds on behalf on this contract.
    function receiveETHWithPayload(bytes memory encodedVm) external {
        bytes memory encodedVM = tokenBridge
            .completeTransferAndUnwrapETHWithPayload(encodedVm);
        TokenBridgeTransferWithPayload memory twp = TokenBridgeMessageLib
            .decodeTransferWithPayloadStructMem(encodedVM);

        // Note: since we are building on top of WTT bridge, we do not need to verify whether the `emitterAddress` is a legitimate WTT bridge from the source chain, as the bridge already validates it in https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L499 and https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L592

        bytes32 expectedSender = whitelistedSenders[twp.tokenChainId];

        // ETH transfers are 18 decimals, see https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/ethereum/contracts/bridge/Bridge.sol#L137
        uint256 receiveAmount = deNormalizeAmount(twp.normalizedAmount, 18);

        // Require inbound fees to be paid if the sender from the source chain is not whitelisted
        if (twp.fromAddress != expectedSender) {
            uint256 feeAmount = calculateInboundFee(receiveAmount);

            (bool feeTransferSuccess, ) = feeRecipient.call{value: feeAmount}(
                ""
            );
            require(feeTransferSuccess);

            uint256 remainingAmount = receiveAmount - feeAmount;

            (bool success, ) = owner.call{value: remainingAmount}("");
            require(success);
        } else {
            // sender is whitelisted, no need to pay fees
            (bool success, ) = owner.call{value: receiveAmount}("");
            require(success);
        }
    }

    // Owner update fee percentage via mantissa and fractional digits
    // Example: to(50, 2) = 0.50%, to(100, 2) = 1.00%, to(5, 1) = 0.5%
    function updateFeePercentage(
        bool isInBound,
        uint16 mantissa,
        uint16 fractionalDigits
    ) external onlyOwner {
        if (isInBound) {
            inboundFeePercentage = PercentageLib.to(mantissa, fractionalDigits);
        } else {
            outboundFeePercentage = PercentageLib.to(
                mantissa,
                fractionalDigits
            );
        }
    }

    // Owner update fee percentage via basis points
    // Example: 1% = 100, 10% = 1000
    function updateFeePercentageBasisPoints(
        bool isInBound,
        uint16 basisPoints
    ) external onlyOwner {
        if (isInBound) {
            inboundFeePercentage = PercentageLib.to(basisPoints, 2);
        } else {
            outboundFeePercentage = PercentageLib.to(basisPoints, 2);
        }
    }

    // Owner sets whitelisted senders from various chains
    // Whitelisted senders will be exempted from paying the inbound fees when receiving cross-chain messages from `receiveETHWithPayload`
    function setWhitelistedSenders(
        uint16 chainId,
        bytes32 whitelistedAddress
    ) external onlyOwner {
        whitelistedSenders[chainId] = whitelistedAddress;
    }

    // Owner updates fee recipient address
    function updateFeeRecipientAddress(
        address newFeeCollector
    ) external onlyOwner {
        require(newFeeCollector != address(0), "Invalid address");
        feeRecipient = newFeeCollector;
    }

    // Update owner address
    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    // Calculate outbound fee amount
    function calculateOutboundFee(
        uint256 amount
    ) public view returns (uint256) {
        return outboundFeePercentage.mulUnchecked(amount);
    }

    // Calculate inbound fee amount
    function calculateInboundFee(uint256 amount) public view returns (uint256) {
        return inboundFeePercentage.mulUnchecked(amount);
    }
}
