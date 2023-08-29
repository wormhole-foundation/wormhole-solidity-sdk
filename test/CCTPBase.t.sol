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

contract CCTPToy is CCTPSender, CCTPReceiver {
    uint256 constant GAS_LIMIT = 250_000;

    function quoteCrossChainDeposit(uint16 targetChain) public view returns (uint256 cost) {
        // Cost of delivering token and payload to targetChain
        uint256 deliveryCost;
        (deliveryCost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
    }

    function sendCrossChainDeposit(uint16 targetChain, address recipient, uint256 amount)
        public
        payable
    {
        uint256 cost = quoteCrossChainDeposit(targetChain);
        require(msg.value == cost, "msg.value must be quoteCrossChainDeposit(targetChain)");

        IERC20(USDC).transferFrom(msg.sender, address(this), amount);

        bytes memory payload = abi.encode(recipient);
        sendUSDCWithPayloadToEvm(
            targetChain,
            fromWormholeFormat(registeredSenders[targetChain]), // address (on targetChain) to send token and payload to
            payload,
            0, // receiver value
            GAS_LIMIT,
            amount
        );
    }

    // function sendCrossChainDeposit(
    //     uint16 targetChain,
    //     address recipient,
    //     uint256 amount,
    //     uint16 refundChain,
    //     address refundAddress
    // ) public payable {
    //     uint256 cost = quoteCrossChainDeposit(targetChain);
    //     require(msg.value == cost, "msg.value must be quoteCrossChainDeposit(targetChain)");

    //     IERC20(token).transferFrom(msg.sender, address(this), amount);

    //     bytes memory payload = abi.encode(recipient);
    //     sendUSDCWithPayloadToEvm(
    //         targetChain,
    //         fromWormholeFormat(registeredSenders[targetChain]), // address (on targetChain) to send token and payload to
    //         payload,
    //         0, // receiver value
    //         GAS_LIMIT,
    //         amount,
    //         refundChain,
    //         refundAddress
    //     );
    // }

    function receivePayloadAndUSDC(
        bytes memory payload,
        uint256 amount,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 // deliveryHash
    ) internal override onlyWormholeRelayer isRegisteredSender(sourceChain, sourceAddress) {
        require(receivedTokens.length == 1, "Expected 1 token transfers");
        address recipient = abi.decode(payload, (address));
        IERC20(receivedTokens[0].tokenAddress).transfer(recipient, receivedTokens[0].amount);
    }
}

contract WormholeSDKTest is WormholeRelayerBasicTest {
    Toy toySource;
    Toy toyTarget;
    CCTPToy CCTPToySource;
    CCTPToy CCTPToyTarget;
    ERC20Mock public token;

    function setUpSource() public override {
        toySource = new Toy(address(relayerSource), address(wormholeSource));
        toySource.setRegisteredSender(targetChain, toWormholeFormat(address(this)));

        CCTPToySource = new CCTPToy(address(relayerSource), address(tokenBridgeSource), address(wormholeSource));

        token = createAndAttestToken(sourceChain);
    }

    function setUpTarget() public override {
        toyTarget = new Toy(address(relayerTarget), address(wormholeTarget));
        toyTarget.setRegisteredSender(sourceChain, toWormholeFormat(address(this)));

        CCTPToyTarget = new CCTPToy(address(relayerTarget), address(tokenBridgeTarget), address(wormholeTarget));
    }

    function setUpGeneral() public override {
        vm.selectFork(sourceFork);
        CCTPToySource.setRegisteredSender(targetChain, toWormholeFormat(address(CCTPToyTarget)));

        vm.selectFork(targetFork);
        CCTPToyTarget.setRegisteredSender(sourceChain, toWormholeFormat(address(CCTPToySource)));
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

    function testSendToken() public {
        vm.selectFork(sourceFork);

        uint256 amount = 19e17;
        token.approve(address(CCTPToySource), amount);

        vm.selectFork(targetFork);
        address recipient = 0x1234567890123456789012345678901234567890;

        vm.selectFork(sourceFork);
        uint256 cost = CCTPToySource.quoteCrossChainDeposit(targetChain);

        vm.recordLogs();
        CCTPToySource.sendCrossChainDeposit{value: cost}(targetChain, recipient, amount, address(token));
        performDelivery();

        vm.selectFork(targetFork);
        address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(sourceChain, toWormholeFormat(address(token)));
        assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
    }

    function testSendTokenWithRefund() public {
        vm.selectFork(sourceFork);

        uint256 amount = 19e17;
        token.approve(address(CCTPToySource), amount);

        vm.selectFork(targetFork);
        address recipient = 0x1234567890123456789012345678901234567890;
        address refundAddress = 0x2234567890123456789012345678901234567890;
        vm.selectFork(sourceFork);
        uint256 cost = CCTPToySource.quoteCrossChainDeposit(targetChain);

        vm.recordLogs();
        CCTPToySource.sendCrossChainDeposit{value: cost}(
            targetChain, recipient, amount, address(token), targetChain, refundAddress
        );
        performDelivery();

        vm.selectFork(targetFork);
        address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(sourceChain, toWormholeFormat(address(token)));
        assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
        assertTrue(refundAddress.balance > 0);
    }
}
