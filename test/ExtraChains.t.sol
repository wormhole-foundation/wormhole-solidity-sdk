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
import {Toy} from "./Fork.t.sol";

contract ChooseChainsTest is WormholeRelayerTest {
    Toy toyBSC;
    Toy toyPolygon;
    Toy toyAvax;
    Toy toyCelo;

    constructor() WormholeRelayerTest() {
        ChainInfo[] memory chains = new ChainInfo[](4);
        chains[0] = chainInfosTestnet[4];
        chains[1] = chainInfosTestnet[5];
        chains[2] = chainInfosTestnet[6];
        chains[3] = chainInfosTestnet[14];
        setActiveForks(chains);
    }

    function setUpSource() public override {
        require(wormholeSource.chainId() == 4);
        toyBSC = new Toy(address(relayerSource), address(wormholeSource));
        toyBSC.setRegisteredSender(targetChain, toWormholeFormat(address(this)));
    }

    function setUpTarget() public override {
        require(wormholeTarget.chainId() == 5);
        toyPolygon = new Toy(address(relayerTarget), address(wormholeTarget));
        toyPolygon.setRegisteredSender(sourceChain, toWormholeFormat(address(this)));
    }

    function setUpOther(ActiveFork memory fork) public override {
        if (fork.chainId == 6) {
            toyAvax = new Toy(address(fork.relayer), address(fork.wormhole));
            toyAvax.setRegisteredSender(14, toWormholeFormat(address(this)));
        } else if (fork.chainId == 14) {
            toyCelo = new Toy(address(fork.relayer), address(fork.wormhole));
            toyCelo.setRegisteredSender(6, toWormholeFormat(address(this)));
        }
    }

    function testSendMessage() public {
        vm.recordLogs();
        (uint256 cost,) = relayerSource.quoteEVMDeliveryPrice(targetChain, 1e17, 100_000);
        relayerSource.sendPayloadToEvm{value: cost}(targetChain, address(toyPolygon), abi.encode(55), 1e17, 100_000);
        performDelivery();

        vm.selectFork(targetFork);
        require(55 == toyPolygon.payloadReceived());
    }

    function testSendMessageSource() public {
        vm.selectFork(targetFork);
        vm.recordLogs();

        (uint256 cost,) = relayerTarget.quoteEVMDeliveryPrice(sourceChain, 1e17, 100_000);
        relayerTarget.sendPayloadToEvm{value: cost}(sourceChain, address(toyBSC), abi.encode(56), 1e17, 100_000);
        performDelivery();

        vm.selectFork(sourceFork);
        require(56 == toyBSC.payloadReceived());
    }

    function testSendMessageOthers() public {
        ActiveFork memory avax = activeForks[6];
        ActiveFork memory celo = activeForks[14];
        vm.selectFork(celo.fork);
        vm.recordLogs();

        (uint256 cost,) = celo.relayer.quoteEVMDeliveryPrice(avax.chainId, 1e17, 100_000);
        celo.relayer.sendPayloadToEvm{value: cost}(avax.chainId, address(toyAvax), abi.encode(56), 1e17, 100_000);
        performDelivery();

        vm.selectFork(avax.fork);
        require(56 == toyAvax.payloadReceived());
    }
}
