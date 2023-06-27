// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/WormholeRelayerSDK.sol";
import "../src/interfaces/IWormholeReceiver.sol";
import "../src/interfaces/IWormholeRelayer.sol";
import "../src/interfaces/IERC20.sol";

import "../src/testing/WormholeRelayerTest.sol";

import "../src/WormholeRelayerSDK.sol";
import "../src/Utils.sol";

import "forge-std/console.sol";

contract Toy is Base {
    IWormholeRelayer relayer;

    uint256 public payloadReceived;

    constructor(address _wormholeRelayer, address _wormhole) Base(_wormholeRelayer, _wormhole) {}

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable onlyWormholeRelayer replayProtect(deliveryHash) isRegisteredSender(sourceChain, sourceAddress) {
        payloadReceived = abi.decode(payload, (uint256));

        console.log("Toy received message");
        console.log("Payload", payloadReceived);
        console.log("Value Received", msg.value);
    }
}

contract WormholeSDKTest is WormholeRelayerTest {
    Toy toySource;
    Toy toyTarget;

    function setUpSource() public override {
        toySource = new Toy(address(relayerSource), address(wormholeSource));
        toySource.setRegisteredSender(targetChain, toWormholeFormat(address(this)));
    }

    function setUpTarget() public override {
        toyTarget = new Toy(address(relayerTarget), address(wormholeTarget));
        toyTarget.setRegisteredSender(sourceChain, toWormholeFormat(address(this)));
    }

    function testSendMessage() public {
        vm.recordLogs();
        (uint256 cost,) = relayerSource.quoteEVMDeliveryPrice(targetChain, 1e17, 100_000);
        relayerSource.sendPayloadToEvm{value: cost}(targetChain, address(toyTarget), abi.encode(55), 1e17, 100_000);
        performDelivery();

        vm.selectFork(targetFork);
        require(55 == toyTarget.payloadReceived());
    }

    function testSendMessageSource() public {
        vm.selectFork(targetFork);
        vm.recordLogs();

        (uint256 cost,) = relayerTarget.quoteEVMDeliveryPrice(sourceChain, 1e17, 100_000);
        relayerTarget.sendPayloadToEvm{value: cost}(sourceChain, address(toySource), abi.encode(56), 1e17, 100_000);
        performDelivery();

        vm.selectFork(sourceFork);
        require(56 == toySource.payloadReceived());
    }
}
