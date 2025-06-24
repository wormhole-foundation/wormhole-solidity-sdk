// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

import "wormhole-sdk/interfaces/token/IERC20Metadata.sol";
import "wormhole-sdk/libraries/SafeERC20.sol";
import "wormhole-sdk/WormholeRelayer.sol";
import "wormhole-sdk/testing/ERC20Mock.sol";
import "wormhole-sdk/testing/WormholeRelayerTest.sol";
import "wormhole-sdk/testing/WormholeRelayer/DeliveryProviderStub.sol";
import {
  tokenOrNativeTransfer,
  normalizeAmount,
  deNormalizeAmount,
  toUniversalAddress
} from "wormhole-sdk/Utils.sol";

//coarse approximations
uint constant GAS_COST_BASE           = 100_000;
uint constant GAS_COST_TOKEN_TRANSFER = 200_000;
uint constant GAS_COST_CCTP_TRANSFER  = 150_000;

contract WormholeRelayerDemoIntegration is WormholeRelayerReceiver {
  using { toUniversalAddress } for address;
  using WormholeRelayerKeysLib for VaaKey;
  using WormholeRelayerKeysLib for CctpKey;
  using WormholeRelayerSend for address;

  event DeliveryReceived(
    bytes32 deliveryHash,
    uint256 extraReceiverValue,
    uint256 receivedInAddition
  );

  struct Peer {
    address peer;
    uint32 cctpDomain;
  }

  address private immutable _wormholeRelayer;
  address private immutable _token;
  address private immutable _tokenBridge;
  address private immutable _usdc;
  address private immutable _cctpTokenMessenger;
  address private immutable _coreBridge;
  address private immutable _cctpMsgTransmitter;

  uint16 private immutable _chainId;
  uint32 private immutable _domain;

  address private owner;

  mapping(uint16 => Peer) private _peers;

  constructor(
    address wormholeRelayer,
    address token,
    address tokenBridge,
    address usdc,
    address cctpTokenMessenger
  ) WormholeRelayerReceiver(wormholeRelayer) {
    _wormholeRelayer    = wormholeRelayer;
    _token              = token;
    _tokenBridge        = tokenBridge;
    _usdc               = usdc;
    _cctpTokenMessenger = cctpTokenMessenger;
    _coreBridge         = ITokenBridge(_tokenBridge).wormhole();
    _cctpMsgTransmitter = address(ITokenMessenger(_cctpTokenMessenger).localMessageTransmitter());

    _chainId = ICoreBridge(_coreBridge).chainId();
    _domain  = IMessageTransmitter(_cctpMsgTransmitter).localDomain();

    owner = msg.sender;

    //more gas efficient to approve only once
    IERC20(_usdc).approve(_cctpTokenMessenger, type(uint256).max);
    //no need to use SafeERC20 forceApprove here, allowance must be zero upon construction
    IERC20(_token).approve(_tokenBridge, type(uint256).max);
  }

  function registerPeer(uint16 chainId, address peerAddress, uint32 cctpDomain) external {
    require(msg.sender == owner, "Unauthorized");
    _peers[chainId] = Peer(peerAddress, cctpDomain);
  }

  function bulkTransfer(
    uint16 targetChain,
    address recipient,
    uint256 receiverValue,
    uint256 tokenAmount,
    uint256 usdcAmount
  ) external payable returns (uint64 whRelayerSequence) { unchecked {
    Peer memory peerData = _peers[targetChain];
    bytes32 peer = peerData.peer.toUniversalAddress();
    require(peer != bytes32(0), "No peer on target chain");

    uint gasLimit =
      GAS_COST_BASE +
      (tokenAmount > 0 ? GAS_COST_TOKEN_TRANSFER : 0) +
      (usdcAmount > 0 ? GAS_COST_CCTP_TRANSFER : 0);

    (uint256 deliveryPrice, ) = _wormholeRelayer.quoteDeliveryPrice(
      targetChain,
      receiverValue,
      gasLimit
    );
    require(msg.value >= deliveryPrice, "Insufficient msg.value");
    uint256 extraReceiverValue = msg.value - deliveryPrice;

    uint additionalMessagesCount = (tokenAmount > 0 ? 1 : 0) + (usdcAmount > 0 ? 1 : 0);
    MessageKey[] memory messageKeys = new MessageKey[](additionalMessagesCount);
    uint messageKeysIndex = 0;
    uint256 normalizedTokenAmount;
    if (tokenAmount > 0) {
      uint decimals = IERC20Metadata(_token).decimals();
      normalizedTokenAmount = normalizeAmount(tokenAmount, decimals);
      uint dustFreeTokenAmount = deNormalizeAmount(normalizedTokenAmount, decimals);
      SafeERC20.safeTransferFrom(IERC20(_token), msg.sender, address(this), dustFreeTokenAmount);

      uint256 wormholeMessageFee = ICoreBridge(_coreBridge).messageFee();
      require(extraReceiverValue >= wormholeMessageFee, "Insufficient msg.value");
      extraReceiverValue -= wormholeMessageFee;
      //use a transfer with payload to enforce that only our peer can redeem the transfer
      uint64 sequence =
        ITokenBridge(_tokenBridge).transferTokensWithPayload{value: wormholeMessageFee}(
          _token,
          dustFreeTokenAmount,
          targetChain,
          peer,
          0,
          bytes("")
        );

      messageKeys[messageKeysIndex++] = MessageKey(
        WormholeRelayerKeysLib.KEY_TYPE_VAA,
        VaaKey(_chainId, _tokenBridge.toUniversalAddress(), sequence).encode()
      );
    }
    if (usdcAmount > 0) {
      //no need to normalize, USDC has 6 decimals
      SafeERC20.safeTransferFrom(IERC20(_usdc), msg.sender, address(this), usdcAmount);

      //use a transfer with destinationCaller to enforce that only our peer can redeem the transfer
      uint64 nonce =
        ITokenMessenger(_cctpTokenMessenger).depositForBurnWithCaller(
          usdcAmount,
          peerData.cctpDomain,
          recipient.toUniversalAddress(),
          _usdc,
          peer
        );

      messageKeys[messageKeysIndex] = MessageKey(
        WormholeRelayerKeysLib.KEY_TYPE_CCTP,
        CctpKey(_domain, nonce).encode()
      );
    }

    return _wormholeRelayer.send(
      deliveryPrice,
      targetChain,
      _peers[targetChain].peer,
      abi.encode(recipient, receiverValue, extraReceiverValue, normalizedTokenAmount, usdcAmount),
      receiverValue,
      gasLimit,
      messageKeys,
      extraReceiverValue
    );
  }}

  function _isPeer(uint16 chainId, bytes32 peerAddress) internal view override returns (bool) {
    return _peers[chainId].peer.toUniversalAddress() == peerAddress;
  }

  function _handleDelivery(
    bytes   calldata payload,
    bytes[] calldata additionalMessages,
    uint16, //sourceChain
    bytes32, //sender (already checked to be a peer by base contract via _isPeer)
    bytes32 deliveryHash
  ) internal override { unchecked {
    ( address recipient,
      uint256 receiverValue,
      uint256 extraReceiverValue,
      uint256 normalizedTokenAmount,
      uint256 usdcAmount
    ) = abi.decode(payload, (address, uint256, uint256, uint256, uint256));

    uint expectedMessageCount = (normalizedTokenAmount > 0 ? 1 : 0) + (usdcAmount > 0 ? 1 : 0);

    //WormholeRelayer guarantees these:
    assert(msg.value >= receiverValue);
    assert(additionalMessages.length == expectedMessageCount);

    tokenOrNativeTransfer(address(0), recipient, msg.value);

    if (normalizedTokenAmount > 0) {
      uint tokenAmount =
        deNormalizeAmount(normalizedTokenAmount, IERC20Metadata(_token).decimals());
      ITokenBridge(_tokenBridge).completeTransferWithPayload(additionalMessages[0]);
      tokenOrNativeTransfer(_token, recipient, tokenAmount);
    }

    if (usdcAmount > 0) {
      (bytes calldata cctpMessage, bytes calldata attestation) =
        unpackAdditionalCctpMessage(additionalMessages[normalizedTokenAmount > 0 ? 1 : 0]);
      IMessageTransmitter(_cctpMsgTransmitter).receiveMessage(cctpMessage, attestation);
      //transfers usdc directly to recipient
    }

    emit DeliveryReceived(deliveryHash, extraReceiverValue, msg.value - receiverValue);
  }}
}

contract WormholeRelayerDemoIntegrationTest is WormholeRelayerTest {
  uint16 private constant SOURCE_CHAIN_ID = CHAIN_ID_ETHEREUM;
  uint16 private constant TARGET_CHAIN_ID = CHAIN_ID_AVALANCHE;

  WormholeRelayerDemoIntegration private _sourceDemoIntegration;
  DeliveryProviderStub private           _sourceDeliveryProviderStub;
  WormholeRelayerDemoIntegration private _targetDemoIntegration;
  DeliveryProviderStub private           _targetDeliveryProviderStub;

  ERC20Mock private _sourceToken;
  IERC20Metadata private _targetWrappedToken;

  address private user;

  function setUp() public override {
    //set up forks
    setUpFork(SOURCE_CHAIN_ID);
    setUpFork(TARGET_CHAIN_ID);

    //deploy tokens
    selectFork(SOURCE_CHAIN_ID);
    setMessageFee(10 gwei);
    _sourceToken = new ERC20Mock("TestToken", "TEST");
    attestToken(address(_sourceToken)); //automatically attests on all forks
    selectFork(TARGET_CHAIN_ID);
    _targetWrappedToken = IERC20Metadata(
      tokenBridge().wrappedAsset(SOURCE_CHAIN_ID, toUniversalAddress(address(_sourceToken)))
    );

    //deploy demo integrations
    selectFork(SOURCE_CHAIN_ID);
    uint32 sourceCctpDomain = cctpDomain();
    _sourceDemoIntegration = new WormholeRelayerDemoIntegration(
      address(wormholeRelayer()),
      address(_sourceToken),
      address(tokenBridge()),
      address(usdc()),
      address(cctpTokenMessenger())
    );

    selectFork(TARGET_CHAIN_ID);
    uint32 targetCctpDomain = cctpDomain();
    _targetDemoIntegration = new WormholeRelayerDemoIntegration(
      address(wormholeRelayer()),
      address(_targetWrappedToken),
      address(tokenBridge()),
      address(usdc()),
      address(cctpTokenMessenger())
    );

    //set up stub delivery providers and set as default
    uint256 sourcePrice = 2;
    uint256 targetPrice = 1;
    uint256 sourceGasPrice = 5 gwei;
    uint256 targetGasPrice = 1 gwei;

    selectFork(SOURCE_CHAIN_ID);
    _sourceDeliveryProviderStub = new DeliveryProviderStub(sourcePrice);
    updateDefaultDeliveryProvider(SOURCE_CHAIN_ID, address(_sourceDeliveryProviderStub));
    selectFork(TARGET_CHAIN_ID);
    _targetDeliveryProviderStub = new DeliveryProviderStub(targetPrice);
    updateDefaultDeliveryProvider(TARGET_CHAIN_ID, address(_targetDeliveryProviderStub));

    //cross-registration
    selectFork(SOURCE_CHAIN_ID);
    _sourceDemoIntegration.registerPeer(
      TARGET_CHAIN_ID,
      address(_targetDemoIntegration),
      targetCctpDomain
    );
    _sourceDeliveryProviderStub.registerPeer(
      TARGET_CHAIN_ID,
      address(_targetDeliveryProviderStub),
      targetPrice,
      targetGasPrice
    );

    selectFork(TARGET_CHAIN_ID);
    _targetDemoIntegration.registerPeer(
      SOURCE_CHAIN_ID,
      address(_sourceDemoIntegration),
      sourceCctpDomain
    );
    _targetDeliveryProviderStub.registerPeer(
      SOURCE_CHAIN_ID,
      address(_sourceDeliveryProviderStub),
      sourcePrice,
      sourceGasPrice
    );

    selectFork(SOURCE_CHAIN_ID);
    user = makeAddr("user");
  }

  function bulkTransferTestTemplate(
    uint usdcAmount,
    uint tokenAmount,
    uint receiverValue
  ) public {
    uint requestedGasLimit = GAS_COST_BASE;
    if (usdcAmount > 0) {
      dealUsdc(user, usdcAmount);
      hoax(user);
      usdc().approve(address(_sourceDemoIntegration), usdcAmount);
      requestedGasLimit += GAS_COST_CCTP_TRANSFER;
    }
    if (tokenAmount > 0) {
      _sourceToken.mint(user, tokenAmount);
      hoax(user);
      _sourceToken.approve(address(_sourceDemoIntegration), tokenAmount);
      requestedGasLimit += GAS_COST_TOKEN_TRANSFER;
    }

    (uint256 expectedDeliveryPrice, ) =
      quoteDeliveryPrice(TARGET_CHAIN_ID, receiverValue, requestedGasLimit);

    uint msgValue = expectedDeliveryPrice + (tokenAmount > 0 ? coreBridge().messageFee() : 0);

    hoax(user);
    vm.recordLogs();
    _sourceDemoIntegration.bulkTransfer{value: msgValue}(
      TARGET_CHAIN_ID,
      user,
      receiverValue,
      tokenAmount,
      usdcAmount
    );

    deliver();

    selectFork(TARGET_CHAIN_ID);
    DeliveryResult memory deliveryResult = getLastDeliveryResult();
    assertEq(deliveryResult.recipientContract, address(_targetDemoIntegration));
    assertEq(
      uint8(deliveryResult.status),
      uint8(IWormholeRelayerDelivery.DeliveryStatus.SUCCESS)
    );

    assertEq(user.balance, receiverValue);
    assertEq(_targetWrappedToken.balanceOf(user), tokenAmount);
    assertEq(usdc().balanceOf(user), usdcAmount);
  }

  function test_all() public {
    bulkTransferTestTemplate(10e6, 5e18, 1e18);
  }

  function test_tokenOnly() public {
    bulkTransferTestTemplate(0, 5e18, 0);
  }

  function test_usdcOnly() public {
    bulkTransferTestTemplate(10e6, 0, 0);
  }

  function test_receiverValueOnly() public {
    bulkTransferTestTemplate(0, 0, 1e18);
  }
}
