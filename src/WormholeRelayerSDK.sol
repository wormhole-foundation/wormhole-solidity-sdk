// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/ITokenBridge.sol";
import "./interfaces/IERC20.sol";

import "./Utils.sol";
import "./ReplayProtection.sol";

import "forge-std/console.sol";

abstract contract Base {
    IWormholeRelayer public immutable wormholeRelayer;
    IWormhole public immutable wormhole;
    
    mapping(bytes32 => bool) seenDeliveryVaaHashes;
    mapping(uint16 => bytes32) registeredSenders;

    constructor(
        address _wormholeRelayer,
        address _wormhole
    ) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        wormhole = IWormhole(_wormhole);
    }

    modifier onlyWormholeRelayer() {
        require(msg.sender == address(wormholeRelayer), "Msg.sender is not Wormhole Relayer");
        _;
    }

    modifier replayProtect(bytes32 deliveryHash) {
        require(!seenDeliveryVaaHashes[deliveryHash], "Message already processed");
        seenDeliveryVaaHashes[deliveryHash] = true;
        _;
    }

    modifier isRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) {
        require(registeredSenders[sourceChain] == sourceAddress, "Not registered sender");
        _;
    }

    /**
     * Sets the registered address for 'sourceChain' to 'sourceAddress'
     * So that for messages from 'sourceChain', only ones from 'sourceAddress' are valid
     * 
     * Assumes only one sender per chain is valid
     * Sender is the address that called 'send' on the Wormhole Relayer contract on the source chain)
     */
    function setRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) internal {
        registeredSenders[sourceChain] = sourceAddress;
    }
}

abstract contract TokenBase is Base {
    ITokenBridge public immutable tokenBridge;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole
    ) Base(_wormholeRelayer, _wormhole) {
        tokenBridge = ITokenBridge(_tokenBridge);
    }
}

abstract contract TokenSender is TokenBase {

    function transferTokens(
        address token,
        uint256 amount,
        uint16 targetChain,
        address targetAddress
    ) internal returns (VaaKey memory) {
        IERC20(token).approve(address(tokenBridge), amount);
        uint64 sequence = tokenBridge.transferTokens{
            value: wormhole.messageFee()
        }(token, amount, targetChain, toWormholeFormat(targetAddress), 0, 0);
        return
            VaaKey({
                emitterAddress: toWormholeFormat(address(tokenBridge)),
                chainId: wormhole.chainId(),
                sequence: sequence
            });
    }

    function sendTokenWithPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint256 cost,
        address token,
        uint256 amount
    ) internal returns (uint64) {
        IERC20(token).approve(address(tokenBridge), amount);
        uint64 sequence = tokenBridge.transferTokensWithPayload{
            value: wormhole.messageFee()
        }(
            token,
            amount,
            targetChain,
            toWormholeFormat(targetAddress),
            0,
            payload
        );

        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = VaaKey({
            emitterAddress: toWormholeFormat(address(tokenBridge)),
            chainId: wormhole.chainId(),
            sequence: sequence
        });

        return
            wormholeRelayer.sendVaasToEvm{value: cost}(
                targetChain,
                targetAddress,
                new bytes(0), // payload is encoded in tokenTransfer
                receiverValue,
                gasLimit,
                vaaKeys
            );
    }
}
