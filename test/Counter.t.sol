// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/WormholeRelayerSDK.sol";
import "../src/interfaces/IWormholeReceiver.sol";
import "../src/interfaces/IWormholeRelayer.sol";
import "../src/interfaces/IERC20.sol";

import "../src/testing/WormholeRelayerTest.sol";

import "forge-std/console.sol";

contract Toy is IWormholeReceiver {
    IWormholeRelayer relayer;

    uint public payloadReceived;

    constructor(address _wormholeRelayer) {
        relayer = IWormholeRelayer(_wormholeRelayer);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32, //sourceAddress,
        uint16, //sourceChain,
        bytes32 //deliveryHash
    ) public payable {
        require(msg.sender == address(relayer), "Only relayer can call");
        payloadReceived = abi.decode(payload, (uint));

        console.log("Toy received message");
        console.log("Payload", payloadReceived);
        console.log("Num additional vaas", additionalVaas.length);
    }
}

contract WormholeSDKTest is WormholeRelayerTest {
    IERC20 token;
    Toy toy;

    function setUpSource() public override {
        token = createAndAttestToken(sourceFork);
    }

    function setUpTarget() public override {
        toy = new Toy(address(relayerTarget));
    }

    function testSendToken() public {
        vm.recordLogs();
        (uint cost, ) = relayerSource.quoteEVMDeliveryPrice(
            targetChain,
            1e17,
            50_000
        );
        relayerSource.sendPayloadToEvm{value: cost}(
            targetChain,
            address(toy),
            abi.encode(55),
            1e17,
            50_000
        );
        performDelivery();

        vm.selectFork(targetFork);
        require(55 == toy.payloadReceived());
    }

    function testSendTokenSource() public {
        vm.recordLogs();

        Toy toySource = new Toy(address(relayerSource));

        (uint cost, ) = relayerSource.quoteEVMDeliveryPrice(
            sourceChain,
            1e17,
            50_000
        );
        relayerSource.sendPayloadToEvm{value: cost}(
            sourceChain,
            address(toySource),
            abi.encode(56),
            1e17,
            50_000
        );

        performDelivery();

        require(56 == toySource.payloadReceived());


    }
}
