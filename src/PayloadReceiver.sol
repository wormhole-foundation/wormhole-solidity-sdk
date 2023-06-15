// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./Utils.sol";

abstract contract PayloadReceiver is IWormholeReceiver {
    mapping(bytes32 => bool) public replayProtection;

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override {
        require(!replayProtection[deliveryHash], "Replay protection");
        replayProtection[deliveryHash] = true;

        receivePayload(
            payload,
            fromWormholeFormat(sourceAddress),
            sourceChain
        );
    }

    function receivePayload(
        bytes memory payload,
        address sourceAddress,
        uint16 sourceChain
    ) internal virtual;
}