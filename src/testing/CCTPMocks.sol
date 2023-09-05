// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/CCTPInterfaces/ITokenMessenger.sol";
import "../interfaces/CCTPInterfaces/IMessageTransmitter.sol";
import "./ERC20Mock.sol";

struct MockMessage {
    uint256 amount;
    uint32 destinationDomain;
    bytes32 mintRecipient;
    address burnToken;
    bytes32 destinationCaller;
}

contract MockMessageTransmitter is IMessageTransmitter {
    ERC20Mock public immutable USDC;

    constructor(ERC20Mock _USDC) {
        USDC = _USDC;
    }

    function receiveMessage(bytes calldata _message, bytes calldata) public returns (bool success) {
        MockMessage memory message = abi.decode(_message, (MockMessage));
        require (msg.sender == bytes32ToAddress(message.destinationCaller), "Wrong caller");

        ERC20Mock(USDC).mint(bytes32ToAddress(message.mintRecipient), message.amount);
        return true;
    }

    function bytes32ToAddress(bytes32 _buf) public pure returns (address) {
        return address(uint160(uint256(_buf)));
    }

    /* Unimplemented functions */

    function sendMessage(uint32, bytes32, bytes calldata) external pure returns (uint64) {
        revert("Unimplemented");
    }

    function sendMessageWithCaller(uint32, bytes32, bytes32, bytes calldata) external pure returns (uint64) {
        revert("Unimplemented");
    }

    function replaceMessage(bytes calldata, bytes calldata, bytes calldata, bytes32) external pure {
        revert("Unimplemented");
    }
}

contract MockTokenMessenger is ITokenMessenger {
    ERC20Mock public immutable USDC;
    uint64 public nonce;

    MockMessage message;
    bytes packedMessage;

    constructor(ERC20Mock _USDC) {
        USDC = _USDC;
    }

    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller
    ) public returns (uint64) {
        ERC20Mock(USDC).burn(msg.sender, amount);
        nonce += 1;
        message = MockMessage(amount, destinationDomain, mintRecipient, burnToken, destinationCaller);
        packedMessage = abi.encode(message);
        return nonce;
    }
}
