pragma solidity ^0.8.19;

import "wormhole-sdk/WormholeRelayerSDK.sol";
import "wormhole-sdk/interfaces/token/IERC20.sol";
import "wormhole-sdk/testing/WormholeRelayerTest.sol";

contract CCTPAndTokenBridgeToy is CCTPAndTokenSender, CCTPAndTokenReceiver {
    uint256 constant GAS_LIMIT = 250_000;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address _circleMessageTransmitter,
        address _circleTokenMessenger,
        address _USDC
    )
        CCTPAndTokenBase(
            _wormholeRelayer,
            _tokenBridge,
            _wormhole,
            _circleMessageTransmitter,
            _circleTokenMessenger,
            _USDC
        )
    {
        setCCTPDomain(23, 3);
        setCCTPDomain(2, 0);
    }

    function quoteCrossChainDeposit(
        uint16 targetChain
    ) public view returns (uint256 cost) {
        // Cost of delivering token and payload to targetChain
        (cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            GAS_LIMIT
        );
    }

    function sendCrossChainDeposit(
        uint16 targetChain,
        address recipient,
        uint256 amount,
        address token
    ) public payable {
        uint256 cost = quoteCrossChainDeposit(targetChain);
        require(
            msg.value == cost,
            "msg.value must be quoteCrossChainDeposit(targetChain)"
        );

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        bytes memory payload = abi.encode(recipient, amount);
        sendTokenWithPayloadToEvm(
            targetChain,
            fromUniversalAddress(registeredSenders[targetChain]), // address (on targetChain) to send token and payload to
            payload,
            0, // receiver value
            GAS_LIMIT,
            token,
            amount
        );
    }

    function sendCrossChainUSDCDeposit(
        uint16 targetChain,
        address recipient,
        uint256 amount
    ) public payable {
        uint256 cost = quoteCrossChainDeposit(targetChain);
        require(
            msg.value == cost,
            "msg.value must be quoteCrossChainDeposit(targetChain)"
        );

        IERC20(USDC).transferFrom(msg.sender, address(this), amount);

        bytes memory payload = abi.encode(recipient, amount);
        sendUSDCWithPayloadToEvm(
            targetChain,
            fromUniversalAddress(registeredSenders[targetChain]), // address (on targetChain) to send token and payload to
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
    )
        internal
        override
        onlyWormholeRelayer
        isRegisteredSender(sourceChain, sourceAddress)
    {
        (address recipient, uint256 expectedAmount) = abi.decode(
            payload,
            (address, uint256)
        );
        require(amount == expectedAmount, "amount != payload.expectedAmount");
        IERC20(USDC).transfer(recipient, amount);
    }

    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 // deliveryHash
    )
        internal
        override
        onlyWormholeRelayer
        isRegisteredSender(sourceChain, sourceAddress)
    {
        require(receivedTokens.length == 1, "Expected 1 token transfers");
        address recipient = abi.decode(payload, (address));
        IERC20(receivedTokens[0].tokenAddress).transfer(
            recipient,
            receivedTokens[0].amount
        );
    }
}

contract WormholeSDKTest is WormholeRelayerBasicTest {
    CCTPAndTokenBridgeToy CCTPAndTokenBridgeToySource;
    CCTPAndTokenBridgeToy CCTPAndTokenBridgeToyTarget;
    ERC20Mock USDCSource;
    ERC20Mock USDCTarget;
    ERC20Mock public token;

    constructor() {
        setMainnetForkChains(23, 2);
    }

    function setUpSource() public override {
        USDCSource = ERC20Mock(address(sourceChainInfo.USDC));
        mintUSDC(sourceChain, address(this), 5000e18);
        CCTPAndTokenBridgeToySource = new CCTPAndTokenBridgeToy(
            address(relayerSource),
            address(tokenBridgeSource),
            address(wormholeSource),
            address(sourceChainInfo.circleMessageTransmitter),
            address(sourceChainInfo.circleTokenMessenger),
            address(USDCSource)
        );
        token = createAndAttestToken(sourceChain);
    }

    function setUpTarget() public override {
        USDCTarget = ERC20Mock(address(targetChainInfo.USDC));
        mintUSDC(targetChain, address(this), 5000e18);
        CCTPAndTokenBridgeToyTarget = new CCTPAndTokenBridgeToy(
            address(relayerTarget),
            address(tokenBridgeTarget),
            address(wormholeTarget),
            address(targetChainInfo.circleMessageTransmitter),
            address(targetChainInfo.circleTokenMessenger),
            address(USDCTarget)
        );
    }

    function setUpGeneral() public override {
        vm.selectFork(sourceFork);
        CCTPAndTokenBridgeToySource.setRegisteredSender(
            targetChain,
            toUniversalAddress(address(CCTPAndTokenBridgeToyTarget))
        );

        vm.selectFork(targetFork);
        CCTPAndTokenBridgeToyTarget.setRegisteredSender(
            sourceChain,
            toUniversalAddress(address(CCTPAndTokenBridgeToySource))
        );
    }

    function testSendUSDC() public {
        vm.selectFork(sourceFork);

        uint256 amount = 100e6;
        USDCSource.approve(address(CCTPAndTokenBridgeToySource), amount);

        vm.selectFork(targetFork);
        address recipient = 0x1234567890123456789012345678901234567890;

        vm.selectFork(sourceFork);
        uint256 cost = CCTPAndTokenBridgeToySource.quoteCrossChainDeposit(
            targetChain
        );

        vm.recordLogs();
        CCTPAndTokenBridgeToySource.sendCrossChainUSDCDeposit{value: cost}(
            targetChain,
            recipient,
            amount
        );
        performDelivery(true);

        vm.selectFork(targetFork);
        assertEq(IERC20(USDCTarget).balanceOf(recipient), amount);
    }

    function testSendToken() public {
        vm.selectFork(sourceFork);

        uint256 amount = 19e17;
        token.approve(address(CCTPAndTokenBridgeToySource), amount);

        vm.selectFork(targetFork);
        address recipient = 0x1234567890123456789012345678901234567890;

        vm.selectFork(sourceFork);
        uint256 cost = CCTPAndTokenBridgeToySource.quoteCrossChainDeposit(
            targetChain
        );

        vm.recordLogs();
        CCTPAndTokenBridgeToySource.sendCrossChainDeposit{value: cost}(
            targetChain,
            recipient,
            amount,
            address(token)
        );
        performDelivery();

        vm.selectFork(targetFork);
        address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(
            sourceChain,
            toUniversalAddress(address(token))
        );
        assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
    }
}
