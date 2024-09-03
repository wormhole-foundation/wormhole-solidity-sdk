// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "IERC20/IERC20.sol";
import "wormhole-sdk/interfaces/IWormholeReceiver.sol";
import "wormhole-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-sdk/interfaces/cctp/ITokenMessenger.sol";
import "wormhole-sdk/interfaces/cctp/IMessageTransmitter.sol";
import "wormhole-sdk/Utils.sol";

import "./Base.sol";

library CCTPMessageLib {
  // The second standardized key type is a CCTP Key
  // representing a CCTP transfer of USDC
  // (on the IWormholeRelayer interface)

  // Note - the default delivery provider only will relay CCTP transfers that were sent
  // in the same transaction that this message was emitted!
  // (This will always be the case if 'CCTPSender' is used)

  uint8 constant CCTP_KEY_TYPE = 2;

  // encoded using abi.encodePacked(domain, nonce)
  struct CCTPKey {
    uint32 domain;
    uint64 nonce;
  }

  // encoded using abi.encode(message, signature)
  struct CCTPMessage {
    bytes message;
    bytes signature;
  }
}

abstract contract CCTPBase is Base {
  ITokenMessenger immutable circleTokenMessenger;
  IMessageTransmitter immutable circleMessageTransmitter;
  address immutable USDC;
  address cctpConfigurationOwner;

  constructor(
    address _wormholeRelayer,
    address _wormhole,
    address _circleMessageTransmitter,
    address _circleTokenMessenger,
    address _USDC
  ) Base(_wormholeRelayer, _wormhole) {
    circleTokenMessenger = ITokenMessenger(_circleTokenMessenger);
    circleMessageTransmitter = IMessageTransmitter(_circleMessageTransmitter);
    USDC = _USDC;
    cctpConfigurationOwner = msg.sender;
  }
}

abstract contract CCTPSender is CCTPBase {
  uint8 internal constant CONSISTENCY_LEVEL_FINALIZED = 15;

  using CCTPMessageLib for *;

  mapping(uint16 => uint32) public chainIdToCCTPDomain;

  /**
   * Sets the CCTP Domain corresponding to chain 'chain' to be 'cctpDomain'
   * So that transfers of USDC to chain 'chain' use the target CCTP domain 'cctpDomain'
   *
   * This action can only be performed by 'cctpConfigurationOwner', who is set to be the deployer
   *
   * Currently, cctp domains are:
   * Ethereum: Wormhole chain id 2, cctp domain 0
   * Avalanche: Wormhole chain id 6, cctp domain 1
   * Optimism: Wormhole chain id 24, cctp domain 2
   * Arbitrum: Wormhole chain id 23, cctp domain 3
   * Base: Wormhole chain id 30, cctp domain 6
   *
   * These can be set via:
   * setCCTPDomain(2, 0);
   * setCCTPDomain(6, 1);
   * setCCTPDomain(24, 2);
   * setCCTPDomain(23, 3);
   * setCCTPDomain(30, 6);
   */
  function setCCTPDomain(uint16 chain, uint32 cctpDomain) public {
    require(
      msg.sender == cctpConfigurationOwner,
      "Not allowed to set CCTP Domain"
    );
    chainIdToCCTPDomain[chain] = cctpDomain;
  }

  function getCCTPDomain(uint16 chain) internal view returns (uint32) {
    return chainIdToCCTPDomain[chain];
  }

  /**
   * transferUSDC wraps common boilerplate for sending tokens to another chain using IWormholeRelayer
   * - approves the Circle TokenMessenger contract to spend 'amount' of USDC
   * - calls Circle's 'depositForBurnWithCaller'
   * - returns key for inclusion in WormholeRelayer `additionalVaas` argument
   *
   * Note: this requires that only the targetAddress can redeem transfers.
   *
   */

  function transferUSDC(
    uint256 amount,
    uint16 targetChain,
    address targetAddress
  ) internal returns (MessageKey memory) {
    IERC20(USDC).approve(address(circleTokenMessenger), amount);
    bytes32 targetAddressBytes32 = addressToBytes32CCTP(targetAddress);
    uint64 nonce = circleTokenMessenger.depositForBurnWithCaller(
      amount,
      getCCTPDomain(targetChain),
      targetAddressBytes32,
      USDC,
      targetAddressBytes32
    );
    return MessageKey(
      CCTPMessageLib.CCTP_KEY_TYPE,
      abi.encodePacked(getCCTPDomain(wormhole.chainId()), nonce)
    );
  }

  // Publishes a CCTP transfer of 'amount' of USDC
  // and requests a delivery of the transfer along with 'payload' to 'targetAddress' on 'targetChain'
  //
  // The second step is done by publishing a wormhole message representing a request
  // to call 'receiveWormholeMessages' on the address 'targetAddress' on chain 'targetChain'
  // with the payload 'abi.encode(amount, payload)'
  // (and we encode the amount so it can be checked on the target chain)
  function sendUSDCWithPayloadToEvm(
    uint16 targetChain,
    address targetAddress,
    bytes memory payload,
    uint256 receiverValue,
    uint256 gasLimit,
    uint256 amount
  ) internal returns (uint64 sequence) {
    MessageKey[] memory messageKeys = new MessageKey[](1);
    messageKeys[0] = transferUSDC(amount, targetChain, targetAddress);

    bytes memory userPayload = abi.encode(amount, payload);
    address defaultDeliveryProvider = wormholeRelayer.getDefaultDeliveryProvider();

    (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);

    sequence = wormholeRelayer.sendToEvm{value: cost}(
      targetChain,
      targetAddress,
      userPayload,
      receiverValue,
      0,
      gasLimit,
      targetChain,
      address(0x0),
      defaultDeliveryProvider,
      messageKeys,
      CONSISTENCY_LEVEL_FINALIZED
    );
  }

  function addressToBytes32CCTP(address addr) private pure returns (bytes32) {
    return bytes32(uint256(uint160(addr)));
  }
}

abstract contract CCTPReceiver is CCTPBase {
  function redeemUSDC(
    bytes memory cctpMessage
  ) internal returns (uint256 amount) {
    (bytes memory message, bytes memory signature) = abi.decode(cctpMessage, (bytes, bytes));
    uint256 beforeBalance = IERC20(USDC).balanceOf(address(this));
    circleMessageTransmitter.receiveMessage(message, signature);
    return IERC20(USDC).balanceOf(address(this)) - beforeBalance;
  }

  function receiveWormholeMessages(
    bytes memory payload,
    bytes[] memory additionalMessages,
    bytes32 sourceAddress,
    uint16 sourceChain,
    bytes32 deliveryHash
  ) external payable {
    // Currently, 'sendUSDCWithPayloadToEVM' only sends one CCTP transfer
    // That can be modified if the integrator desires to send multiple CCTP transfers
    // in which case the following code would have to be modified to support
    // redeeming these multiple transfers and checking that their 'amount's are accurate
    require(
      additionalMessages.length <= 1,
      "CCTP: At most one Message is supported"
    );

    uint256 amountUSDCReceived;
    if (additionalMessages.length == 1)
      amountUSDCReceived = redeemUSDC(additionalMessages[0]);

    (uint256 amount, bytes memory userPayload) = abi.decode(payload, (uint256, bytes));

    // Check that the correct amount was received
    // It is important to verify that the 'USDC' sent in by the relayer is the same amount
    // that the sender sent in on the source chain
    require(amount == amountUSDCReceived, "Wrong amount received");

    receivePayloadAndUSDC(
      userPayload,
      amountUSDCReceived,
      sourceAddress,
      sourceChain,
      deliveryHash
    );
  }

  // Implement this function to handle in-bound deliveries that include a CCTP transfer
  function receivePayloadAndUSDC(
    bytes memory payload,
    uint256 amountUSDCReceived,
    bytes32 sourceAddress,
    uint16 sourceChain,
    bytes32 deliveryHash
  ) internal virtual {}
}
