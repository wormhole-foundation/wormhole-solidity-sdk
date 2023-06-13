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
    ITokenBridge public immutable tokenBridge;
    IWormhole public immutable wormhole;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole
    ) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        tokenBridge = ITokenBridge(_tokenBridge);
        wormhole = IWormhole(_wormhole);
    }
}

abstract contract TokenSender is Base {
    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole
    ) Base(_wormholeRelayer, _tokenBridge, _wormhole) {}

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
