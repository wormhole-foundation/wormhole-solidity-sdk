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

    // Peer on destination chain
    // This will be our contract address deployed on the destination chain
    bytes32 public peerInDestinationChain;

    // Map of whitelisted senders that are exempt from the inbound fees
    // Key: source chain ID => whitelisted senders
    mapping(uint16 => bytes32[]) public whitelistedSenders;

    // Fee amount charged when sending messages outbound
    Percentage public outboundFeePercentage;

    // Fee amount charged when receiving inbound messages
    Percentage public inboundFeePercentage;

    constructor(
        address coreBridgeAddress,
        address tokenBridgeAddress,
        address ownerAddress,
        address feeRecipientAddress,
        bytes32 _peerInDestinationChain,
        uint16 outboundFeeMantissa,
        uint16 outboundFeeDigits,
        uint16 inboundFeeMantissa,
        uint16 inboundFeeDigits
    ) {
        require(coreBridgeAddress != address(0), "Invalid address");
        require(tokenBridgeAddress != address(0), "Invalid address");
        require(ownerAddress != address(0), "Invalid address");
        require(feeRecipientAddress != address(0), "Invalid address");

        coreBridge = ICoreBridge(coreBridgeAddress);
        tokenBridge = ITokenBridge(tokenBridgeAddress);
        owner = ownerAddress;
        feeRecipient = feeRecipientAddress;
        peerInDestinationChain = _peerInDestinationChain;

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

    // Entry point for transferring ETH with payload
    // Payloads are arbitrary data that can be attached to the transfer to perform designed operations in the destination chain (e.g., automatically swap tokens when received on the destination chain)
    // See https://wormhole.com/docs/products/token-transfers/wrapped-token-transfers/concepts/payload-structure/#transferwithpayload
    function transferETHWithPayload(
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce
    ) external payable {
        // incur fees from ETH
        uint256 sentAmount = msg.value;
        uint256 feeAmount = calculateOutboundFee(sentAmount);

        // distribute fees to fee recipient
        (bool success, ) = feeRecipient.call{value: feeAmount}("");
        require(success);

        // calculate remaining amount
        uint256 remainingAmount = sentAmount - feeAmount;

        // encode recipient address in destination chain
        bytes memory payload = abi.encodePacked(bytes32(recipient));

        tokenBridge.wrapAndTransferETHWithPayload{value: remainingAmount}(
            recipientChain,
            peerInDestinationChain,
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

    // Entry point to receive custom cross-chain messages from the source chain
    function receiveETHWithPayload(bytes calldata encodedVm) external {
        
        // Since the message was dispatched as payload ID 3 using the `wrapAndTransferETHWithPayload` entry point, only the specified `recipient` address can withdraw the funds from the WTT bridge contract (see https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/ethereum/contracts/bridge/Bridge.sol#L505-L507).
        // This ensures that no one can manually redeem the funds on behalf on this contract.
        bytes memory wttPayload = tokenBridge
            .completeTransferAndUnwrapETHWithPayload(encodedVm);
        TokenBridgeTransferWithPayload memory twp = TokenBridgeMessageLib
            .decodeTransferWithPayloadStructMem(wttPayload);

        // Note: since we are building on top of WTT bridge, we do not need to verify whether the `emitterAddress` is a legitimate WTT bridge from the source chain, as the bridge already validates it in https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L499 and https://github.com/wormhole-foundation/wormhole/blob/c3301db8978fedf1f8ea2819d076871e435e2492/ethereum/contracts/bridge/Bridge.sol#L592

        // ETH transfers are 18 decimals, see https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/ethereum/contracts/bridge/Bridge.sol#L137
        uint256 receiveAmount = deNormalizeAmount(twp.normalizedAmount, 18);

        // Extract the recipient address from the custom `payload` field
        bytes memory payload = twp.payload;
        address finalRecipient = address(uint160(uint256(bytes32(payload))));

        bool isSenderWhitelisted = isWhitelisted(twp.tokenChainId, twp.fromAddress);

        // Require inbound fees to be paid if the sender from the source chain is not whitelisted
        if (!isSenderWhitelisted) {
            uint256 feeAmount = calculateInboundFee(receiveAmount);

            (bool feeTransferSuccess, ) = feeRecipient.call{value: feeAmount}(
                ""
            );
            require(feeTransferSuccess);

            uint256 remainingAmount = receiveAmount - feeAmount;

            (bool success, ) = finalRecipient.call{value: remainingAmount}("");
            require(success);
        } else {
            // sender is whitelisted, no need to pay fees
            (bool success, ) = finalRecipient.call{value: receiveAmount}("");
            require(success);
        }
    }

    // Owner update fee percentage via mantissa and fractional digits
    // Example: to(50, 2) = 0.50%, to(100, 2) = 1.00%, to(5, 1) = 0.5%
    function updateFeePercentage(
        bool isInbound,
        uint16 mantissa,
        uint16 fractionalDigits
    ) external onlyOwner {
        if (isInbound) {
            inboundFeePercentage = PercentageLib.to(mantissa, fractionalDigits);
        } else {
            outboundFeePercentage = PercentageLib.to(
                mantissa,
                fractionalDigits
            );
        }
    }

    // Owner sets whitelisted senders from various chains
    // Whitelisted senders will be exempted from paying the inbound fees when receiving cross-chain messages from `receiveETHWithPayload`
    function setWhitelistedSenders(
        uint16 chainId,
        bytes32[] calldata whitelistedAddresses
    ) external onlyOwner {
        whitelistedSenders[chainId] = whitelistedAddresses;
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

    // Checks whether the sender from this chainId is whitelisted
    function isWhitelisted(uint16 chainId, bytes32 sender) public view returns (bool) {
        bytes32[] memory senders = whitelistedSenders[chainId];
        
        for (uint256 i = 0; i < senders.length; i++) {
            if (senders[i] == sender) {
                return true;
            }
        }
        
        return false;
    }
}
