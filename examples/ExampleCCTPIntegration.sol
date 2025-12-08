// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {ITokenMessenger} from "src/interfaces/cctp/ITokenMessenger.sol";
import {IMessageTransmitter} from "src/interfaces/cctp/IMessageTransmitter.sol";
import {Percentage, PercentageLib} from "wormhole-sdk/libraries/Percentage.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {CctpMessageLib} from "wormhole-sdk/libraries/CctpMessages.sol";
import "src/utils/DecimalNormalization.sol";

contract ExampleCCTPIntegration {
    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/TokenMessenger.sol
    ITokenMessenger public tokenMessenger;

    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/MessageTransmitter.sol
    IMessageTransmitter public messageTransmitter;

    // List of peers from various chains
    // This will be our contract addresses deployed on each chain
    mapping(uint32 => bytes32) public peers;

    constructor(
        address tokenMessengerAddress,
        address messageTransmitterAddress
    ) {
        require(tokenMessengerAddress != address(0), "Invalid address");
        require(messageTransmitterAddress != address(0), "Invalid address");

        tokenMessenger = ITokenMessenger(tokenMessengerAddress);
        messageTransmitterAddress = IMessageTransmitter(
            messageTransmitterAddress
        );
    }

    function sendCCTPMessages(
        uint256 amount,
        uint32 destinationDomain,
        address burnToken
    ) external {
        bytes32 peerAddress = peers[destinationDomain];
        require(peerAddress != bytes32(0), "Invalid peer address!");

        SafeERC20(burnToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        SafeERC20(burnToken).forceApprove(tokenMessenger, amount);

        tokenMessenger.depositForBurnWithCaller(
            amount,
            destinationDomain,
            peerAddress,
            burnToken,
            peerAddress
        );
    }

    function receiveCCTPMessages(
        bytes calldata message,
        bytes calldata attestation
    ) external {
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
}
