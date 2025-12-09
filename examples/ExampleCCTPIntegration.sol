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
import {Percentage, PercentageLib} from "wormhole-sdk/libraries/Percentage.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {
    CctpMessageLib,
    CctpTokenBurnMessage
} from "wormhole-sdk/libraries/CctpMessages.sol";
import "wormhole-sdk/utils/DecimalNormalization.sol";

contract ExampleCCTPIntegration {
    using SafeERC20 for IERC20;

    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/TokenMessenger.sol
    ITokenMessenger public tokenMessenger;

    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/MessageTransmitter.sol
    IMessageTransmitter public messageTransmitter;

    // List of peers from various chains
    // This will be our contract addresses deployed on each chain
    mapping(uint32 => bytes32) public peers;

    // keccak256(message, attestation) -> unlock timestamp
    mapping(bytes32 => uint) public unlockTimestamps;

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

    function sendCCTPMessages(
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
            mintRecipient,
            burnToken,
            peerAddress // we set `destinationCaller` to our peer address so only our contract in destination chain can unlock the messenges
        );
    }

    function startUnlockFunds(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        bool isValid = CctpMessageLib.isCctpTokenBurnMessageCd(message);
        require(isValid, "Message is invalid");

        CctpTokenBurnMessage memory burnMessage = CctpMessageLib
            .decodeCctpTokenBurnMessageStructCd(message);

        require(
            address(uint160(uint256(burnMessage.body.mintRecipient))) ==
                msg.sender,
            "Only sender can unlock the funds"
        );

        bytes32 key = keccak256(abi.encodePacked(message, attestation));
        require(unlockTimestamps[key] == 0, "Unlock already requested!");

        unlockTimestamps[key] = block.timestamp + 1 days;
    }

    function redeemFunds(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        bool isValid = CctpMessageLib.isCctpTokenBurnMessageCd(message);
        require(isValid, "Message is invalid");

        (
            uint32 sourceDomain,
            uint32 destinationDomain,
            uint64 nonce,
            bytes32 sender,
            bytes32 recipient,
            bytes32 destinationCaller,
            bytes32 burnToken,
            bytes32 mintRecipient,
            uint256 amount,
            bytes32 messageSender
        ) = CctpMessageLib.decodeCctpTokenBurnMessageCd(message);

        // Ensure the lockup has elapsed
        bytes32 key = keccak256(abi.encodePacked(message, attestation));
        uint unlockTimestamp = unlockTimestamps[key];
        require(unlockTimestamp != 0, "Unlock is not requested!");
        require(
            block.timestamp >= unlockTimestamp,
            "Timelock has not elapsed!"
        );

        // Calling receiveMessage() will in turn cause the funds to be sent to this contract
        // https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/TokenMessenger.sol#L337-L343
        bool isSuccess = messageTransmitter.receiveMessage(
            message,
            attestation
        );
        require(isSuccess, "Must succeed");
    }

    // Owner updates the peer address for various chains
    function setPeer(uint32 chainId, bytes32 peerAddress) external onlyOwner {
        peers[chainId] = peerAddress;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
