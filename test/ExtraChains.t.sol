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

contract ExtraChainsTest is WormholeRelayerTest {
    mapping(uint16 => Toy) toys;

    constructor() WormholeRelayerTest() {
        ChainInfo[] memory chains = new ChainInfo[](4);
        chains[0] = chainInfosTestnet[4];
        chains[1] = chainInfosTestnet[5];
        chains[2] = chainInfosTestnet[6];
        chains[3] = chainInfosTestnet[14];
        setActiveForks(chains);
    }

    function setUpFork(ActiveFork memory fork) public override {
        toys[fork.chainId] = new Toy(address(fork.relayer), address(fork.wormhole));
        toys[fork.chainId].setRegisteredSender(4, toWormholeFormat(address(this)));
        toys[fork.chainId].setRegisteredSender(5, toWormholeFormat(address(this)));
        toys[fork.chainId].setRegisteredSender(6, toWormholeFormat(address(this)));
        toys[fork.chainId].setRegisteredSender(14, toWormholeFormat(address(this)));
    }

    function testSendFromCelo() public {
        ActiveFork memory celo = activeForks[14];

        for (uint16 i = 4; i < 7; ++i) {
            vm.selectFork(celo.fork);
            vm.recordLogs();
            ActiveFork memory target = activeForks[i];

            (uint256 cost,) = celo.relayer.quoteEVMDeliveryPrice(target.chainId, 1e17, 100_000);

            celo.relayer.sendPayloadToEvm{value: cost}(
                target.chainId, address(toys[target.chainId]), abi.encode(56), 1e17, 100_000
            );
            performDelivery();

            vm.selectFork(target.fork);
            require(56 == toys[target.chainId].payloadReceived());
        }
    }
}
