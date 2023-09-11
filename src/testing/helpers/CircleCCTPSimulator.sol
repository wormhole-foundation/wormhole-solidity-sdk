// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {IMessageTransmitter} from "../../../src/interfaces/CCTPInterfaces/IMessageTransmitter.sol";
import "./BytesLib.sol";

import "forge-std/Vm.sol";
import "forge-std/console.sol";

interface MessageTransmitterViewAttesterManager {
    function attesterManager() external view returns (address);

    function enableAttester(address newAttester) external;
}

/**
 * @title A Circle MessageTransmitter Simulator
 * @notice This contract simulates attesting Circle messages emitted in a forge test.
 * It overrides the Circle 'attester' set to allow for signing messages with a single
 * private key on any EVM where the MessageTransmitter contract is deployed.
 * @dev This contract is meant to be used when testing against a testnet or mainnet fork.
 */
contract CircleMessageTransmitterSimulator {
    using BytesLib for bytes;

    // Taken from forge-std/Script.sol
    address private constant VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm public constant vm = Vm(VM_ADDRESS);

    // Allow access to MessageTransmitter
    IMessageTransmitter public messageTransmitter;

    // Save the private key to sign messages with
    uint256 private attesterPrivateKey;

    /**
     * @param messageTransmitter_ address of the MessageTransmitter for the chain being forked
     * @param attesterPrivateKey_ private key of the (single) attester - to override the MessageTransmitter contract with
     */
    constructor(address messageTransmitter_, uint256 attesterPrivateKey_) {
        messageTransmitter = IMessageTransmitter(messageTransmitter_);
        attesterPrivateKey = attesterPrivateKey_;
        overrideAttester(vm.addr(attesterPrivateKey));
    }

    function overrideAttester(address attesterPublicKey) internal {
        {
            MessageTransmitterViewAttesterManager attesterManagerInterface = MessageTransmitterViewAttesterManager(
                    address(messageTransmitter)
                );
            address attesterManager = attesterManagerInterface
                .attesterManager();
            vm.prank(attesterManager);
            attesterManagerInterface.enableAttester(attesterPublicKey);
        }
    }

    
    function parseMessageFromMessageTransmitterLog(
        Vm.Log memory log
    ) internal pure returns (bytes memory message) {
        uint256 index = 32;

        // length of payload
        uint256 payloadLen = log.data.toUint256(index);
        index += 32;

        message = log.data.slice(index, payloadLen);
        index += payloadLen;

        // trailing bytes (due to 32 byte slot overlap)
        require(log.data.length - index < 32, "Too many extra bytes");
        index += log.data.length - index;

        require(
            index == log.data.length,
            "failed to parse MessageTransmitter message"
        );
    }

    /**
     * @notice Finds published messageTransmitter events in forge logs
     * @param logs The forge Vm.log captured when recording events during test execution
     */
    function fetchMessageTransmitterLogsFromLogs(
        Vm.Log[] memory logs
    ) public pure returns (Vm.Log[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("event MessageSent(bytes message);")
            ) {
                count += 1;
            }
        }

        // create log array to save published messages
        Vm.Log[] memory published = new Vm.Log[](count);

        uint256 publishedIndex = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("event MessageSent(bytes message);")
            ) {
                published[publishedIndex] = logs[i];
                publishedIndex += 1;
            }
        }

        return published;
    }

    /**
     * @notice attests a simulated MessageTransmitter message using the emitted log from MessageTransmitter
     * @param log The forge Vm.log captured when recording events during test execution
     * @return attestation attested message
     */
    
    function fetchSignedMessageFromLog(
        Vm.Log memory log
    ) public view returns (bytes memory attestation) {
        // Parse messageTransmitter message from ethereum logs
        bytes memory message = parseMessageFromMessageTransmitterLog(log);

        return signMessage(message);
    }
    
    /**
     * @notice Signs a simulated messageTransmitter message
     * @param message The messageTransmitter message
     * @return signedMessage signed messageTransmitter message
     */
    
    function signMessage(
        bytes memory message
    ) public view returns (bytes memory signedMessage) {

        bytes32 messageHash = keccak256(message);

        // Sign the hash with the attester private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

}
