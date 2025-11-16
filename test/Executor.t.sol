// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {IERC20}          from "wormhole-sdk/interfaces/token/IERC20.sol";
import {ICoreBridge}     from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {ITokenMessenger} from "wormhole-sdk/interfaces/cctp/ITokenMessenger.sol";
import {
  CHAIN_ID_ETHEREUM,
  CHAIN_ID_BASE,
  CHAIN_ID_POLYGON
} from "wormhole-sdk/constants/Chains.sol";
import {CONSISTENCY_LEVEL_FINALIZED} from "wormhole-sdk/constants/ConsistencyLevel.sol";
import {
  eagerOr,
  tokenOrNativeTransfer,
  toUniversalAddress
} from "wormhole-sdk/Utils.sol";
import {BytesParsing}                from "wormhole-sdk/libraries/BytesParsing.sol";
import {SequenceReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {ExecutorSendReceive} from "wormhole-sdk/Executor/Integration.sol";
import {RequestLib}          from "wormhole-sdk/Executor/Request.sol";
import {RelayInstructionLib} from "wormhole-sdk/Executor/RelayInstruction.sol";
import {ExecutorTest} from "wormhole-sdk/testing/ExecutorTest.sol";

//demo integration for Executor:
//A cross-chain vault that allows the owner to "live" on only one chain but distribute
//  USDC and gas on all vault chains, while the less trusted rebalancer role can move
//  funds only between vaults by submitting reblance requests on each vault's home chain.
//This example is ofc contrived because in practice one would just have the owner sign a message
//  and vaults verify against the owner key, this way the owner doesn't have to "live" on any chain
//  at all.
contract ToyCrossChainUsdcVault is ExecutorSendReceive {
  using BytesParsing for bytes;
  using {toUniversalAddress} for address;

  struct PeerConfig {
    address peer;
    uint32  cctpDomain;
  }

  struct WithdrawalParams {
    address recipient;
    uint64  usdcAmount;
    uint256 gasAmount;
  }

  struct RebalanceParams {
    uint16  chainId;
    uint64  usdcAmount;
    uint256 cost; //in native/gas tokens
    bytes   signedQuote;
  }

  struct PeerParams {
    uint16     chainId;
    PeerConfig config;
  }

  //coarse approximations of gas costs:
  //verifying and replay protecting the VAA, etc.
  uint256 private constant _GAS_COST_BASE = 200_000;
  //updating balances, emitting events, etc.
  uint256 private constant _GAS_COST_USDC_TRANSFER = 40_000;
  //we constrain the number of max recipients to ensure that we stay within reasonable bounds:
  // 1. 120 * 40k + 200k = max 5M gas
  // 2. 120 * 32 bytes (12 bytes amount, 20 bytes recipient) = 3841 bytes max payload size
  //Notice that if we wanted to go to Solana, we'd probably significantly reduce payload size
  //  and hence max recipients even further
  uint256 private constant _MAX_RECIPIENTS = 120;

  address private immutable _usdc;
  address private immutable _cctpTokenMessenger;
  uint32  private immutable _cctpDomain;

  address private _owner;
  address private _rebalancer;
  mapping(uint16 => PeerConfig) private _peers;

  constructor(
    address owner,
    address rebalancer,
    address coreBridge,
    address executor,
    address usdc,
    address cctpTokenMessenger,
    PeerParams[] memory peers
  ) ExecutorSendReceive(coreBridge, executor) {
    _usdc               = usdc;
    _cctpTokenMessenger = cctpTokenMessenger;

    _owner = owner;
    _rebalancer = rebalancer;
    for (uint i = 0; i < peers.length; ++i)
      _peers[peers[i].chainId] = peers[i].config;

    _cctpDomain = ITokenMessenger(cctpTokenMessenger).localMessageTransmitter().localDomain();
    IERC20(_usdc).approve(cctpTokenMessenger, type(uint256).max);
  }

  modifier onlyOwner() {
    require(msg.sender == _owner, "Not authorized");
    _;
  }

  modifier onlyAuthorized() {
    require(eagerOr(msg.sender == _owner, msg.sender == _rebalancer), "Not authorized");
    _;
  }

  function _getPeer(uint16 chainId) internal view override returns (bytes32 peer) {
    return _peers[chainId].peer.toUniversalAddress();
  }

  function _replayProtect(
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    bytes calldata //encodedVaa - only relevant when using hash-based replay protection
  ) internal override {
    SequenceReplayProtectionLib.replayProtect(emitterChainId, emitterAddress, sequence);
  }

  function _executeVaa(
    bytes calldata payload,
    //we don't need any of timestamp, peerChain, peerAddress, sequence, or consistencyLevel here
    uint32, uint16, bytes32, uint64, uint8
  ) internal override {
    uint offset = 0;
    while (offset < payload.length) {
      uint usdcAmount; address recipient;
      (usdcAmount, offset) = payload.asUint96CdUnchecked(offset);
      (recipient,  offset) = payload.asAddressCdUnchecked(offset);
      tokenOrNativeTransfer(_usdc, recipient, usdcAmount);
    }
  }

  function rebalance(RebalanceParams[] calldata distribution) external payable onlyAuthorized {
    uint totalCost = 0;
    for (uint i = 0; i < distribution.length; ++i) {
      RebalanceParams calldata param = distribution[i];
      totalCost += param.cost;
      uint16 peerChain = param.chainId;
      bytes32 peerAddress = _getExistingPeer(peerChain);
      uint32 destinationDomain = _peers[peerChain].cctpDomain;

      //initiate CCTP transfer to our peer
      uint64 cctpNonce = ITokenMessenger(_cctpTokenMessenger).depositForBurn(
        param.usdcAmount,
        destinationDomain,
        peerAddress,
        address(_usdc)
      );

      //request relay of CCTP transfer
      _executor.requestExecution{value: param.cost}(
        peerChain,
        peerAddress,
        msg.sender,
        param.signedQuote,
        RequestLib.encodeCctpV1Request(_cctpDomain, cctpNonce),
        new bytes(0)
      );
    }
    _checkMsgValue(totalCost);
  }

  function withdrawCrossChain(
    uint16 chainId,
    WithdrawalParams[] calldata params,
    bytes calldata signedQuote
  ) external payable onlyOwner { unchecked {
    uint count = params.length;
    require(count <= _MAX_RECIPIENTS, "Too many recipients");
    uint gasDropOffRequests = 0;
    for (uint i = 0; i < count; ++i)
      if (params[i].gasAmount > 0)
        ++gasDropOffRequests;

    uint128[] memory gasDropOffs = new uint128[](gasDropOffRequests);
    bytes32[] memory recipients  = new bytes32[](gasDropOffRequests);
    uint256[] memory payloadArr  = new uint256[](count);
    uint r = 0;
    for (uint i = 0; i < count; ++i) {
      WithdrawalParams calldata p = params[i];
      if (p.gasAmount > 0) {
        gasDropOffs[r] = uint128(p.gasAmount);
        recipients[r]  = p.recipient.toUniversalAddress();
        ++r;
      }
      payloadArr[i] = uint256(p.usdcAmount) << 160 | uint256(uint160(p.recipient));
    }

    //this exact value must also be used when querying for the executor quote
    //it's tighter to (cheaply) calculate it here, than to pass it in as a parameter
    uint gasLimit = _GAS_COST_BASE + recipients.length * _GAS_COST_USDC_TRANSFER;

    //this encoding is inefficient because we pack an array of 8 bytes for the usdc amount
    //  and 20 bytes for the recipient address into 32 bytes, hence wasting 4 bytes per item,
    //  but it's easier to implement given Solidity's lacking packing support
    //in general, there's a lot of stuff that should be optimized for gas here in production
    bytes memory payload = abi.encodePacked(payloadArr);

    _publishAndRelay(
      payload,
      CONSISTENCY_LEVEL_FINALIZED,
      msg.value, //must equal execution cost + Wormhole message fee for publishing!
      chainId,
      msg.sender,
      signedQuote,
      uint128(gasLimit),
      0,
      RelayInstructionLib.encodeGasDropOffInstructions(gasDropOffs, recipients)
    );
  }}

  //just for completeness sake (so it's not totally contrived)
  function withdrawLocal(WithdrawalParams[] calldata params) external payable onlyOwner {
    uint totalGasAmount = 0;
    for (uint i = 0; i < params.length; ++i) {
      WithdrawalParams calldata p = params[i];
      totalGasAmount += p.gasAmount;
      tokenOrNativeTransfer(address(0), p.recipient, p.gasAmount );
      tokenOrNativeTransfer(_usdc,      p.recipient, p.usdcAmount);
    }
    _checkMsgValue(totalGasAmount);
  }

  function _checkMsgValue(uint256 expected) internal {
    require(msg.value == expected, "Invalid msg.value");
  }
}

contract ExecutorDemoIntegrationTest is ExecutorTest {
  uint16[] private chains;
  ToyCrossChainUsdcVault[] private vaults;
  address private owner;
  address private rebalancer;
  address[] private recipients;

  constructor() {
    chains.push(CHAIN_ID_ETHEREUM);
    chains.push(CHAIN_ID_BASE);
    chains.push(CHAIN_ID_POLYGON);
  }

  function setUp() public override {
    for (uint i = 0; i < chains.length; ++i)
      setUpFork(chains[i]);

    selectFork(chains[0]);
    setMessageFee(10 gwei);

    rebalancer = makeAddr("rebalancer");
    for (uint i = 0; i < chains.length; ++i)
      recipients.push(makeAddr(string.concat("recipient", vm.toString(i + 1))));

    address[] memory vaultAddrs = new address[](chains.length);
    for (uint i = 0; i < chains.length; ++i)
      vaultAddrs[i] = computeCreateAddress(address(this), vm.getNonce(address(this)) + i);

    for (uint i = 0; i < chains.length; ++i) {
      ToyCrossChainUsdcVault.PeerParams[] memory peerParams =
        new ToyCrossChainUsdcVault.PeerParams[](chains.length - 1);
      uint k = 0;
      for (uint j = 0; j < chains.length; ++j) {
        if (j == i)
          continue;

        selectFork(chains[j]);
        peerParams[k].chainId           = chains[j];
        peerParams[k].config.peer       = vaultAddrs[j];
        peerParams[k].config.cctpDomain = cctpDomain();
        ++k;
      }

      selectFork(chains[i]);
      vaults.push(new ToyCrossChainUsdcVault(
        owner,
        rebalancer,
        address(coreBridge()),
        address(executor()),
        address(usdc()),
        address(cctpTokenMessenger()),
        peerParams
      ));
      assert(address(vaults[i]) == vaultAddrs[i]);
    }

    selectFork(chains[0]);
  }

  function testHappyPath() public {
    uint count = chains.length - 1;
    uint initialUsdc = 1e8;
    dealUsdc(address(vaults[0]), initialUsdc);

    //-- rebalance --

    //in the real world, these quote costs would be queried from the off-chain quoter endpoint
    uint256[] memory quoteCosts  = new uint256[](count);
    quoteCosts[0]  = uint256(0.5 ether);
    quoteCosts[1]  = uint256(1.5 ether);

    uint64[]  memory usdcAmounts = new uint64[](count);
    usdcAmounts[0] = uint64(20e6);
    usdcAmounts[1] = uint64(40e6);

    ToyCrossChainUsdcVault.RebalanceParams[] memory rParams =
      new ToyCrossChainUsdcVault.RebalanceParams[](count);
    uint rTotalCost = 0;
    uint usdcDistributed = 0;
    for (uint i = 0; i < count; ++i) {
      uint16 dstChain = chains[i + 1];
      uint cost = quoteCosts[i];
      rTotalCost += cost;
      usdcDistributed += usdcAmounts[i];
      rParams[i].chainId     = dstChain;
      rParams[i].usdcAmount  = usdcAmounts[i];
      rParams[i].cost        = cost;
      rParams[i].signedQuote = craftSignedQuote(dstChain);
    }

    hoax(rebalancer);
    vm.recordLogs();
    vaults[0].rebalance{value: rTotalCost}(rParams);

    executeRelay();

    assertEq(executionResults.length, count);
    for (uint i = 0; i < count; ++i)
      assertTrue(executionResults[i].success);

    assertEq(payee.balance, rTotalCost);
    assertEq(usdc().balanceOf(address(vaults[0])), initialUsdc - usdcDistributed);

    for (uint i = 0; i < count; ++i) {
      selectFork(chains[i + 1]);
      assertEq(usdc().balanceOf(address(vaults[i + 1])), usdcAmounts[i]);
    }

    //-- withdraw cross-chain --
    selectFork(chains[0]);
    uint messageFee = ICoreBridge(address(coreBridge())).messageFee();

    uint16 wChain = chains[1];
    uint64 wUsdcBalance = usdcAmounts[0];

    ToyCrossChainUsdcVault.WithdrawalParams[] memory wParams =
      new ToyCrossChainUsdcVault.WithdrawalParams[](recipients.length);

    wParams[0].recipient  = recipients[0];
    wParams[1].recipient  = recipients[1];
    wParams[2].recipient  = recipients[2];
    wParams[0].usdcAmount = wUsdcBalance * 5 / 10;
    wParams[1].usdcAmount = wUsdcBalance * 3 / 10;
    wParams[2].usdcAmount = wUsdcBalance * 2 / 10;
    wParams[0].gasAmount  = 1 ether;
    wParams[1].gasAmount  = 0.5 ether;
    wParams[2].gasAmount  = 0.25 ether;

    uint wQuoteCost = 4 ether;
    uint wTotalCost = messageFee + wQuoteCost;
    bytes memory wSignedQuote = craftSignedQuote(wChain);

    hoax(owner);
    vm.recordLogs();
    vaults[0].withdrawCrossChain{value: wTotalCost}(wChain, wParams, wSignedQuote);

    executeRelay();

    assertEq(executionResults.length, count + 1);
    assertTrue(getLastExecutionResult().success);

    assertEq(payee.balance, rTotalCost + wQuoteCost);

    selectFork(wChain);
    assertEq(usdc().balanceOf(address(vaults[1])), 0);

    for (uint i = 0; i < recipients.length; ++i) {
      assertEq(usdc().balanceOf(recipients[i]), wParams[i].usdcAmount);
      assertEq(recipients[i].balance, wParams[i].gasAmount);
    }
  }
}
