// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {IERC20} from "IERC20/IERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {
    ITokenMessenger
} from "wormhole-sdk/interfaces/cctp/ITokenMessenger.sol";
import {
    IMessageTransmitter
} from "wormhole-sdk/interfaces/cctp/IMessageTransmitter.sol";
import {
    CctpMessageLib,
    CctpTokenBurnMessage
} from "wormhole-sdk/libraries/CctpMessages.sol";

contract ExampleCCTPIntegration {
    using SafeERC20 for IERC20;

    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/TokenMessenger.sol
    ITokenMessenger public tokenMessenger;

    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/MessageTransmitter.sol
    IMessageTransmitter public messageTransmitter;

    // List of peers from various chains
    // This will be our contract addresses deployed on each chain
    mapping(uint32 => bytes32) public peers;

    // This map records the timestamp when the unlock is requested
    // Tokens are only unlocked after 24 hours before redemption
    // Only non-whitelisted users (see `whitelistedRecipients` below) are required to wait for 24 hours before receiving the funds
    // keccak256(message, attestation) -> unlock timestamp
    mapping(bytes32 => uint) public unlockTimestamps;

    // Map of whitelisted recipients that does not need to wait for 24 hours before redeeming their funds
    // Key: address => isWhitelisted
    mapping(address => bool) public whitelistedRecipients;

    // Owner of this contract
    address public owner;

    constructor(
        address tokenMessengerAddress,
        address messageTransmitterAddress,
        address ownerAddress
    ) {
        require(tokenMessengerAddress != address(0), "Invalid address");
        require(messageTransmitterAddress != address(0), "Invalid address");
        require(ownerAddress != address(0), "Invalid address");

        tokenMessenger = ITokenMessenger(tokenMessengerAddress);
        messageTransmitter = IMessageTransmitter(messageTransmitterAddress);
        owner = ownerAddress;
    }

    // Entry point in the source chain to start cross-chain transfers
    function initiateCrossChainTransfer(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external {
        bytes32 peerAddress = peers[destinationDomain];
        require(peerAddress != bytes32(0), "Invalid peer address!");

        IERC20(burnToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(burnToken).forceApprove(address(tokenMessenger), amount);

        tokenMessenger.depositForBurnWithCaller(
            amount,
            destinationDomain,
            mintRecipient, // this is the recipient's address on the destination chain
            burnToken,
            peerAddress // we set `destinationCaller` to our peer address so only our contract in destination chain can unlock the messenges
        );
    }

    // Entry point in the destination chain to request funds to be unlocked
    // This entry point needs to be called before calling `redeemUnlockedFunds`
    function startUnlockFunds(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        // Compute the key from the message and attestation parameters
        bytes32 key = keccak256(abi.encodePacked(message, attestation));
        require(unlockTimestamps[key] == 0, "Unlock already requested!");

        // populate the map field to only allow funds to be unlocked after 24 hours
        unlockTimestamps[key] = block.timestamp + 1 days;
    }

    // Entry point in the destination chain to redeem the funds after the lock period has elapsed
    function redeemUnlockedFunds(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        CctpTokenBurnMessage memory burnMessage = CctpMessageLib
            .decodeCctpTokenBurnMessageStructCd(message);

        // See src/libraries/CctpMessages.sol:41~69 for the message formats
        bytes32 mintRecipient = burnMessage.body.mintRecipient;

        // The timelock for funds redemption is only enforced if the recipient is not whitelisted
        address finalRecipient = address(uint160(uint256(mintRecipient)));
        bool isRecipientWhitelisted = whitelistedRecipients[finalRecipient];

        if (!isRecipientWhitelisted) {
            bytes32 key = keccak256(abi.encodePacked(message, attestation));

            uint unlockTimestamp = unlockTimestamps[key];

            // Ensure there is an entry in the unlockTimestamps mapping (i.e., users have request their funds to be unlocked)
            require(
                unlockTimestamp != 0,
                "Funds unlock is not requested, see `startUnlockFunds` entry point"
            );

            // Ensure the lock period has elapsed
            require(
                block.timestamp >= unlockTimestamp,
                "Timelock is not elapsed yet!"
            );
        }

        // Calling receiveMessage() in the `messageTransmitter` will finalize and transfer the funds to the `mintRecipient`
        // https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/TokenMessenger.sol#L337-L343
        bool isSuccess = messageTransmitter.receiveMessage(
            message,
            attestation
        );
        require(isSuccess, "receiveMessage() failed");
    }

    // Owner updates the peer address for various chains
    function setPeer(uint32 chainId, bytes32 peerAddress) external onlyOwner {
        peers[chainId] = peerAddress;
    }

    // Owner sets whitelisted recipients from various chains
    // Whitelisted recipients can redeem their funds without waiting for the 24 hour delay
    function setWhitelistedRecipients(
        address whitelistAddress,
        bool isWhitelisted
    ) external onlyOwner {
        whitelistedRecipients[whitelistAddress] = isWhitelisted;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
