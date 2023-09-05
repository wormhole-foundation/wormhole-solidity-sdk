// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/WormholeRelayerSDK.sol";
import "../src/interfaces/IWormholeReceiver.sol";
import "../src/interfaces/IWormholeRelayer.sol";
import "../src/interfaces/IERC20.sol";

import "../src/testing/WormholeRelayerTest.sol";
import "../src/testing/CCTPMocks.sol";

import "../src/WormholeRelayerSDK.sol";
import "../src/Utils.sol";

import "forge-std/console.sol";

contract CCTPToy is CCTPSender, CCTPReceiver {
    uint256 constant GAS_LIMIT = 250_000;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address _circleMessageTransmitter,
        address _circleTokenMessenger,
        address _USDC
    ) CCTPBase(_wormholeRelayer, _tokenBridge, _wormhole, _circleMessageTransmitter, _circleTokenMessenger, _USDC) {}

    function quoteCrossChainDeposit(uint16 targetChain) public view returns (uint256 cost) {
        // Cost of delivering token and payload to targetChain
        uint256 deliveryCost;
        (deliveryCost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
    }

    function sendCrossChainDeposit(uint16 targetChain, address recipient, uint256 amount) public payable {
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

    function receivePayloadAndUSDC(
        bytes memory payload,
        uint256 amount,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 // deliveryHash
    ) internal override onlyWormholeRelayer isRegisteredSender(sourceChain, sourceAddress) {
        (address recipient, uint256 expectedAmount) = abi.decode(payload, (address, uint256));
        require(amount == expectedAmount, "amount != payload.expectedAmount");
        IERC20(USDC).transfer(recipient, amount);
    }
}

contract WormholeSDKTest is WormholeRelayerBasicTest {
    CCTPToy CCTPToySource;
    CCTPToy CCTPToyTarget;
    ERC20Mock USDCSource;
    ERC20Mock USDCTarget;
    MockMessageTransmitter circleMessageTransmitter;
    MockTokenMessenger circleTokenMessenger;

    function setUpSource() public override {
        CCTPToySource = new CCTPToy(
            address(relayerSource),
            address(tokenBridgeSource),
            address(wormholeSource),
            address(circleMessageTransmitter),
            address(circleTokenMessenger),
            address(USDCSource)
        );
        USDCSource = createAndAttestToken(sourceChain);
        circleMessageTransmitter = new MockMessageTransmitter(USDCSource);
    }

    function setUpTarget() public override {
        CCTPToyTarget = new CCTPToy(
            address(relayerTarget), 
            address(tokenBridgeTarget), 
            address(wormholeTarget), 
            address(circleMessageTransmitter), 
            address(circleTokenMessenger),
            address(USDCTarget)
        );
        USDCTarget = createAndAttestToken(targetChain);
        circleTokenMessenger = new MockTokenMessenger(USDCTarget);
    }

    // function setUpGeneral() public override {
    //     vm.selectFork(sourceFork);

    //     vm.selectFork(targetFork);
    // }

    function testSendToken() public {
        vm.selectFork(sourceFork);

        uint256 amount = 19e17;
        USDCSource.approve(address(CCTPToySource), amount);

        vm.selectFork(targetFork);
        address recipient = 0x1234567890123456789012345678901234567890;

        vm.selectFork(sourceFork);
        uint256 cost = CCTPToySource.quoteCrossChainDeposit(targetChain);

        vm.recordLogs();
        CCTPToySource.sendCrossChainDeposit{value: cost}(targetChain, recipient, amount);
        performDelivery();

        vm.selectFork(targetFork);
        // address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(sourceChain, toWormholeFormat(address(token)));
        // assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
    }

    // function testSendTokenWithRefund() public {
    //     vm.selectFork(sourceFork);

    //     uint256 amount = 19e17;
    //     token.approve(address(CCTPToySource), amount);

    //     vm.selectFork(targetFork);
    //     address recipient = 0x1234567890123456789012345678901234567890;
    //     address refundAddress = 0x2234567890123456789012345678901234567890;
    //     vm.selectFork(sourceFork);
    //     uint256 cost = CCTPToySource.quoteCrossChainDeposit(targetChain);

    //     vm.recordLogs();
    //     CCTPToySource.sendCrossChainDeposit{value: cost}(
    //         targetChain, recipient, amount, address(token), targetChain, refundAddress
    //     );
    //     performDelivery();

    //     vm.selectFork(targetFork);
    //     address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(sourceChain, toWormholeFormat(address(token)));
    //     assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
    //     assertTrue(refundAddress.balance > 0);
    // }
}
