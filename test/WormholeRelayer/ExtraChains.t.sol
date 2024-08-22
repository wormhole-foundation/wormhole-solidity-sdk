
pragma solidity ^0.8.19;

import "wormhole-sdk/WormholeRelayerSDK.sol";
import "wormhole-sdk/interfaces/token/IERC20.sol";
import "wormhole-sdk/testing/WormholeRelayerTest.sol";

import {Toy} from "./Fork.t.sol";

contract ExtraChainsTest is WormholeRelayerTest {
    mapping(uint16 => Toy) toys;

    constructor() WormholeRelayerTest() {
        ChainInfo[] memory chains = new ChainInfo[](3);
        chains[0] = chainInfosTestnet[4];
        chains[1] = chainInfosTestnet[6];
        chains[2] = chainInfosTestnet[14];
        setActiveForks(chains);
    }

    function setUpFork(ActiveFork memory fork) public override {
        toys[fork.chainId] = new Toy(address(fork.relayer), address(fork.wormhole));
        toys[fork.chainId].setRegisteredSender(4, toUniversalAddress(address(this)));
        toys[fork.chainId].setRegisteredSender(6, toUniversalAddress(address(this)));
        toys[fork.chainId].setRegisteredSender(14, toUniversalAddress(address(this)));
    }

    function testSendFromCelo() public {
        ActiveFork memory celo = activeForks[14];

        uint16[] memory chains = new uint16[](2);
        chains[0] = 4;
        chains[1] = 6;
        for (uint16 i = 0; i < chains.length; ++i) {
            uint16 chainId = chains[i];
            vm.selectFork(celo.fork);
            vm.recordLogs();
            ActiveFork memory target = activeForks[chainId];

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
