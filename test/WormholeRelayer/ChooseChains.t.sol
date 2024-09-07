
pragma solidity ^0.8.19;

import "wormhole-sdk/WormholeRelayerSDK.sol";
import "wormhole-sdk/interfaces/token/IERC20.sol";
import "wormhole-sdk/testing/WormholeRelayerTest.sol";
import {Toy} from "./Fork.t.sol";

contract ChooseChainsTest is WormholeRelayerBasicTest {
  Toy toySource;
  Toy toyTarget;

  uint private constant _TEST_VALUE = 1e15;
  uint private constant _TEST_GAS_LIMIT = 100_000;

  constructor() {
    setTestnetForkChains(CHAIN_ID_BSC, CHAIN_ID_AVALANCHE);
  }

  function setUpSource() public override {
    require(wormholeSource.chainId() == CHAIN_ID_BSC);
    toySource = new Toy(address(relayerSource), address(wormholeSource));
    toySource.setRegisteredSender(targetChain, toUniversalAddress(address(this)));
  }

  function setUpTarget() public override {
    require(wormholeTarget.chainId() == CHAIN_ID_AVALANCHE);
    toyTarget = new Toy(address(relayerTarget), address(wormholeTarget));
    toyTarget.setRegisteredSender(sourceChain, toUniversalAddress(address(this)));
  }

  function testSendMessage() public {
    uint256 toyPayload = 55;
    vm.recordLogs();
    (uint256 cost,) =
      relayerSource.quoteEVMDeliveryPrice(targetChain, _TEST_VALUE, _TEST_GAS_LIMIT);
    relayerSource.sendPayloadToEvm{value: cost}(
      targetChain,
      address(toyTarget),
      abi.encode(toyPayload),
      _TEST_VALUE,
      _TEST_GAS_LIMIT
    );
    performDelivery();

    vm.selectFork(targetFork);
    require(toyPayload == toyTarget.payloadReceived());
  }

  function testSendMessageSource() public {
    uint256 toyPayload = 56;
    vm.selectFork(targetFork);
    vm.recordLogs();

    (uint256 cost,) =
      relayerTarget.quoteEVMDeliveryPrice(sourceChain, _TEST_VALUE, _TEST_GAS_LIMIT);
    relayerTarget.sendPayloadToEvm{value: cost}(
      sourceChain,
      address(toySource),
      abi.encode(toyPayload),
      _TEST_VALUE,
      _TEST_GAS_LIMIT
    );
    performDelivery();

    vm.selectFork(sourceFork);
    require(toyPayload == toySource.payloadReceived());
  }
}
