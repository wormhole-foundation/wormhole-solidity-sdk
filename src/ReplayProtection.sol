// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";

abstract contract ReplayProtection is IWormholeReceiver {
    mapping(bytes32 => bool) public replayProtection;

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override {
        require(!replayProtection[deliveryHash], "Replay protection");
        replayProtection[deliveryHash] = true;

        receiveWormholeMessages(
            payload,
            additionalVaas,
            sourceAddress,
            sourceChain
        );
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain
    ) internal virtual;
}