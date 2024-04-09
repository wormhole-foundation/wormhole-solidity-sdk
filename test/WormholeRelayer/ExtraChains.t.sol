
pragma solidity ^0.8.19;

import "wormhole-sdk/WormholeRelayerSDK.sol";
import "wormhole-sdk/interfaces/token/IERC20.sol";
import "wormhole-sdk/testing/WormholeRelayerTest.sol";

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
        toys[fork.chainId].setRegisteredSender(4, toUniversalAddress(address(this)));
        toys[fork.chainId].setRegisteredSender(5, toUniversalAddress(address(this)));
        toys[fork.chainId].setRegisteredSender(6, toUniversalAddress(address(this)));
        toys[fork.chainId].setRegisteredSender(14, toUniversalAddress(address(this)));
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
