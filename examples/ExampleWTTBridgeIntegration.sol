// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {IERC20} from "IERC20/IERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {ITokenBridge} from "wormhole-sdk/interfaces/ITokenBridge.sol";
import {CoreBridgeLib} from "wormhole-sdk/libraries/CoreBridge.sol";
import {TokenBridgeMessageLib, TokenBridgeTransferWithPayload} from "wormhole-sdk/libraries/TokenBridgeMessages.sol";
import {Percentage, PercentageLib} from "wormhole-sdk/libraries/Percentage.sol";
import {SequenceReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";
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

    // Fee amount (e.g., to(50, 2) = 0.50%)
    Percentage public feePercentage;

    constructor(
        address coreBridgeAddress,
        address tokenBridgeAddress,
        address ownerAddress,
        address feeRecipientAddress,
        uint16 feeMantissa,
        uint16 feeDigits
    ) {
        coreBridge = ICoreBridge(coreBridgeAddress);
        tokenBridge = ITokenBridge(tokenBridgeAddress);

        require(ownerAddress != address(0), "Invalid address");
        require(feeRecipientAddress != address(0), "Invalid address");

        owner = ownerAddress;
        feeRecipient = feeRecipientAddress;
        // Use PercentageLib.to() to create the Percentage type
        // Example: to(50, 2) = 0.50%, to(100, 2) = 1.00%, to(5, 1) = 0.5%
        feePercentage = PercentageLib.to(feeMantissa, feeDigits);
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
        uint256 feeAmount = calculateFee(sentAmount);

        payable(feeRecipient).transfer(feeAmount);

        // Calculate remaining amount
        uint256 remainingAmount = sentAmount - feeAmount;

        // Handle case where a potential refund might occur in https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L129-L144
        // We dont want the funds be stuck in the contract, so we refund to the caller
        // See https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L83

        uint wormholeFee = coreBridge.messageFee();
        require(
            wormholeFee < remainingAmount,
            "remaining amount is smaller than wormhole fee"
        );
        uint leftoverAmount = remainingAmount - wormholeFee;

        require(
            arbiterFee <= leftoverAmount,
            "arbiter fee is bigger than leftover amount minus wormhole fee"
        );
        uint normalizedAmount = normalizeAmount(leftoverAmount, 18);
        // refund dust
        uint dust = leftoverAmount - deNormalizeAmount(normalizedAmount, 18);
        if (dust > 0) {
            payable(msg.sender).transfer(dust);
        }

        tokenBridge.wrapAndTransferETH{value: remainingAmount - dust}(
            recipientChain,
            recipient,
            arbiterFee,
            nonce
        );
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
        uint256 feeAmount = calculateFee(sentAmount);

        payable(feeRecipient).transfer(feeAmount);

        // calculate remaining amount
        uint256 remainingAmount = sentAmount - feeAmount;

        // Handle case where a potential refund might occur in https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L129-L144
        // We dont want the funds be stuck in the contract, so we refund to the caller
        // See https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L115

        uint wormholeFee = coreBridge.messageFee();
        require(
            wormholeFee < remainingAmount,
            "remaining amount is smaller than wormhole fee"
        );
        uint leftoverAmount = remainingAmount - wormholeFee;
        uint normalizedAmount = normalizeAmount(leftoverAmount, 18);
        // refund dust
        uint dust = leftoverAmount - deNormalizeAmount(normalizedAmount, 18);
        if (dust > 0) {
            payable(msg.sender).transfer(dust);
        }

        tokenBridge.wrapAndTransferETHWithPayload{
            value: remainingAmount - dust
        }(recipientChain, recipient, nonce, payload);
    }

    // Entry point for transferring tokens without payload (i.e., a simple token transfer)
    // See https://wormhole.com/docs/products/token-transfers/wrapped-token-transfers/concepts/payload-structure/#transfer
    function transferTokensWithoutPayload(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable {
        // incur fees from the token
        uint256 feeAmount = calculateFee(amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeTransfer(feeRecipient, feeAmount);

        // calculate remaining amount
        uint256 remainingAmount = amount - feeAmount;
        IERC20(token).forceApprove(address(tokenBridge), remainingAmount);

        // send to WTT bridge
        tokenBridge.transferTokens{value: msg.value}(
            token,
            remainingAmount,
            recipientChain,
            recipient,
            arbiterFee,
            nonce
        );
    }

    // Entry point for transferring tokens with payload
    // Payloads are arbitrary data that can be attached to the transfer to perform designed operations in the destination chain (e.g., automatically swap tokens when received on the destination chain)
    // See https://wormhole.com/docs/products/token-transfers/wrapped-token-transfers/concepts/payload-structure/#transferwithpayload
    function transferTokensWithPayload(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce,
        bytes memory payload
    ) external payable {
        // incur fees from the token
        uint256 feeAmount = calculateFee(amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeTransfer(feeRecipient, feeAmount);

        // calculate remaining amount
        uint256 remainingAmount = amount - feeAmount;
        IERC20(token).forceApprove(address(tokenBridge), remainingAmount);

        // send to WTT bridge
        tokenBridge.transferTokensWithPayload{value: msg.value}(
            token,
            remainingAmount,
            recipientChain,
            recipient,
            nonce,
            payload
        );
    }

    // Owner update fee percentage via mantissa and fractional digits
    function updateFeePercentage(
        uint16 mantissa,
        uint16 fractionalDigits
    ) external onlyOwner {
        feePercentage = PercentageLib.to(mantissa, fractionalDigits);
    }

    // Owner update fee percentage via basis points (e.g, 1% = 100, 10% = 1000)
    function updateFeePercentageBasisPoints(
        uint16 basisPoints
    ) external onlyOwner {
        feePercentage = PercentageLib.to(basisPoints, 2);
    }

    // Owner update fee recipient address
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

    // Calculate fee amount
    function calculateFee(uint256 amount) public view returns (uint256) {
        return feePercentage.mulUnchecked(amount);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
