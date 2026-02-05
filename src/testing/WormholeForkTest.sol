// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "wormhole-sdk/constants/Chains.sol";
import "wormhole-sdk/interfaces/ICoreBridge.sol";
import "wormhole-sdk/interfaces/ITokenBridge.sol";
import "wormhole-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-sdk/interfaces/IExecutor.sol";
import "wormhole-sdk/interfaces/cctp/IMessageTransmitter.sol";
import "wormhole-sdk/interfaces/cctp/ITokenMessenger.sol";
import "wormhole-sdk/libraries/VaaLib.sol";
import "wormhole-sdk/Utils.sol";

//avoid solidity shadowing bug
import {
  defaultRPC,
  chainName as chainName_,
  coreBridge as coreBridge_,
  tokenBridge as tokenBridge_,
  wormholeRelayer as wormholeRelayer_,
  executor as executor_,
  executorQuoterRouter as executorQuoterRouter_,
  cctpDomain as cctpDomain_,
  usdc as usdc_,
  cctpMessageTransmitter as cctpMessageTransmitter_,
  cctpTokenMessenger as cctpTokenMessenger_
} from "wormhole-sdk/testing/ChainConsts.sol";
import "wormhole-sdk/testing/UsdcDealer.sol";
import "wormhole-sdk/testing/WormholeOverride.sol";
import "wormhole-sdk/testing/CctpOverride.sol";
import "wormhole-sdk/testing/ERC20Mock.sol";

struct Fork {
  uint256 fork;
  uint16 chainId;
  string chainName;
  string rpcUrl;

  ICoreBridge coreBridge;
  ITokenBridge tokenBridge;
  IWormholeRelayer relayer;
  IExecutor executor;
  IExecutorQuoterRouter executorQuoterRouter;
  IUSDC usdc;
  uint32 cctpDomain;
  IMessageTransmitter cctpMessageTransmitter;
  ITokenMessenger cctpTokenMessenger;
}

struct AttestedMessages {
  Vaa[] vaas;
  AttestedCctpBurnMessage[] attestedCctpBurnMsgs;
}

struct AttestedCctpBurnMessage {
  CctpTokenBurnMessage cctpBurnMsg;
  bytes attestation;
}

abstract contract WormholeForkTest is Test {
  using WormholeOverride for ICoreBridge;
  using CctpOverride for IMessageTransmitter;
  using UsdcDealer for IUSDC;

  bool internal isMainnet;
  mapping(uint16 => uint) internal chainIdToForkIndexPlusOne;
  mapping(uint256 => uint) internal forkToForkIndexPlusOne;
  Fork[] internal forks;

  // -- setup --

  constructor() {
    //by default fork/test against mainnets, set to false in your own constructor to override
    isMainnet = true;
  }

  function setUp() public virtual { //default impl that can be overridden
    setUpFork(CHAIN_ID_ETHEREUM);
    selectFork(CHAIN_ID_ETHEREUM);
  }

  function setUpFork(uint16 chainId_) internal virtual {
    setUpFork(chainId_, defaultRPC(isMainnet, chainId_));
  }

  function setUpFork(uint16 chainId_, string memory rpcUrl_) internal virtual {
    Fork memory fork = Fork(
      vm.createSelectFork(rpcUrl_),
      chainId_,
      chainName_(isMainnet, chainId_),
      rpcUrl_,
      ICoreBridge(coreBridge_(isMainnet, chainId_)),
      ITokenBridge(tokenBridge_(isMainnet, chainId_)),
      IWormholeRelayer(wormholeRelayer_(isMainnet, chainId_)),
      IExecutor(executor_(isMainnet, chainId_)),
      IExecutorQuoterRouter(executorQuoterRouter_(isMainnet, chainId_)),
      IUSDC(usdc_(isMainnet, chainId_)),
      cctpDomain_(isMainnet, chainId_),
      IMessageTransmitter(cctpMessageTransmitter_(isMainnet, chainId_)),
      ITokenMessenger(cctpTokenMessenger_(isMainnet, chainId_))
    );
    setUpFork(fork);
  }

  function setUpFork(Fork memory fork) internal virtual {
    setUpOverrides(fork);
    addFork(fork);
  }

  // -- basic usage --

  modifier preserveFork() {
    uint originalFork = vm.activeFork();
    _;
    vm.selectFork(originalFork);
  }

  function selectFork(uint16 chainId_) internal virtual { unchecked {
    uint index = chainIdToForkIndexPlusOne[chainId_];
    require(index != 0, "Chain not registered with ForkTest");
    vm.selectFork(forks[index-1].fork);
  }}

  function chainId() internal view virtual returns (uint16) {
    return activeFork().chainId;
  }

  function chainName() internal view virtual returns (string memory) {
    return activeFork().chainName;
  }

  function rpcUrl() internal view virtual returns (string memory) {
    return activeFork().rpcUrl;
  }

  function coreBridge() internal view virtual returns (ICoreBridge) {
    return activeFork().coreBridge;
  }

  function tokenBridge() internal view virtual returns (ITokenBridge) {
    return activeFork().tokenBridge;
  }

  function wormholeRelayer() internal view virtual returns (IWormholeRelayer) {
    return activeFork().relayer;
  }

  function executor() internal view virtual returns (IExecutor) {
    return activeFork().executor;
  }

  function executorQuoterRouter() internal view virtual returns (IExecutorQuoterRouter) {
    return activeFork().executorQuoterRouter;
  }

  function usdc() internal view virtual returns (IUSDC) {
    return activeFork().usdc;
  }

  function cctpDomain() internal view virtual returns (uint32) {
    return activeFork().cctpDomain;
  }

  function cctpMessageTransmitter() internal view virtual returns (IMessageTransmitter) {
    return activeFork().cctpMessageTransmitter;
  }

  function cctpTokenMessenger() internal view virtual returns (ITokenMessenger) {
    return activeFork().cctpTokenMessenger;
  }

  function dealUsdc(address to, uint256 amount) internal virtual {
    usdc().deal(to, amount);
  }

  // -- convenience functions --

  function setMessageFee(uint256 msgFee) internal virtual{
    coreBridge().setMessageFee(msgFee);
  }

  function attestToken(address token) internal virtual preserveFork {
    uint originalChainId = chainId();
    vm.recordLogs();
    tokenBridge().attestToken{value: coreBridge().messageFee()}(token, 0);
    bytes memory tokenAttestationVaa = fetchEncodedVaa();

    for (uint i = 0; i < forks.length; ++i) {
      Fork storage fork = forks[i];
      if (fork.chainId == originalChainId || address(fork.tokenBridge) == address(0))
        continue;

      vm.selectFork(fork.fork);
      fork.tokenBridge.createWrapped(tokenAttestationVaa);
    }
  }

  //convenience function for common use case
  function fetchEncodedVaa() internal virtual returns (bytes memory encodedVaa) {
    return fetchEncodedVaa(vm.getRecordedLogs());
  }

  function fetchEncodedVaa(
    Vm.Log[] memory logs
  ) internal view virtual returns (bytes memory encodedVaa) {
    PublishedMessage[] memory pms = coreBridge().fetchPublishedMessages(logs);
    assert(pms.length > 0);
    return coreBridge().sign(pms[0]).encode();
  }

  //fetches and signs all published messages of the CoreBridge
  function fetchVaas() internal virtual returns (Vaa[] memory) {
    return fetchVaas(vm.getRecordedLogs());
  }

  function fetchVaas(Vm.Log[] memory logs) internal view virtual returns (Vaa[] memory vaas) {
    PublishedMessage[] memory pms = coreBridge().fetchPublishedMessages(logs);
    vaas = new Vaa[](pms.length);
    for (uint i = 0; i < pms.length; ++i)
      vaas[i] = coreBridge().sign(pms[i]);
  }

  //fetches and signs all emitted messages (CoreBridge + CCTP)
  //returning a single struct rather than multiple arrays for future extensibility
  function fetchAttestedMessages() internal virtual returns (AttestedMessages memory) {
    return fetchAttestedMessages(vm.getRecordedLogs());
  }

  function fetchAttestedMessages(
    Vm.Log[] memory logs
  ) internal view virtual returns (AttestedMessages memory attestedMessages) {
    attestedMessages.vaas = fetchVaas(logs);
    attestedMessages.attestedCctpBurnMsgs = fetchAttestedCctpBurnMessages(logs);
  }

  //fetches and signs all CCTP burn messages
  function fetchAttestedCctpBurnMessages(
    Vm.Log[] memory logs
  ) internal view virtual returns (AttestedCctpBurnMessage[] memory attestedCctpBurnMsgs) {
    CctpTokenBurnMessage[] memory cctpBurnMsgs = cctpMessageTransmitter().fetchBurnMessages(logs);
    attestedCctpBurnMsgs = new AttestedCctpBurnMessage[](cctpBurnMsgs.length);
    for (uint i = 0; i < cctpBurnMsgs.length; ++i)
      attestedCctpBurnMsgs[i] = AttestedCctpBurnMessage(
        cctpBurnMsgs[i],
        cctpMessageTransmitter().sign(cctpBurnMsgs[i])
      );
  }

  // -- more low-level stuff --

  function activeFork() internal view virtual returns (Fork storage fork) { unchecked {
    fork = forks[forkToForkIndexPlusOne[vm.activeFork()] - 1];
  }}

  function setUpOverrides(Fork memory fork) internal virtual {
    fork.coreBridge.setUpOverride();
    if (address(fork.cctpMessageTransmitter) != address(0))
      fork.cctpMessageTransmitter.setUpOverride();
  }

  function addFork(Fork memory fork) internal virtual { unchecked {
    require(fork.chainId != 0, "ChainId is not valid");
    require(address(fork.coreBridge) != address(0), "CoreBridge is not valid");
    require(chainIdToForkIndexPlusOne[fork.chainId] == 0, "Chain already has a fork");
    uint forkIndex = forks.length;
    forks.push(fork);
    forkToForkIndexPlusOne[fork.fork] = forkIndex + 1;
    chainIdToForkIndexPlusOne[fork.chainId] = forkIndex + 1;
  }}
}
