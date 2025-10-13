// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "wormhole-sdk/constants/Chains.sol";
import "wormhole-sdk/interfaces/ICoreBridge.sol";
import "wormhole-sdk/interfaces/ITokenBridge.sol";
import "wormhole-sdk/interfaces/IWormholeRelayer.sol";
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

  IUSDC usdc;
  uint32 cctpDomain;
  IMessageTransmitter cctpMessageTransmitter;
  ITokenMessenger cctpTokenMessenger;
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
    isMainnet = true; //by default fork/test against mainnets
  }

  function setUp() public virtual { //default impl that can be overridden
    setUpFork(CHAIN_ID_ETHEREUM);
    selectFork(CHAIN_ID_ETHEREUM);
  }

  function setUpFork(uint16 chainId_) internal {
    setUpFork(chainId_, defaultRPC(isMainnet, chainId_));
  }

  function setUpFork(uint16 chainId_, string memory rpcUrl_) internal {
    Fork memory fork = Fork(
      vm.createSelectFork(rpcUrl_),
      chainId_,
      chainName_(isMainnet, chainId_),
      rpcUrl_,
      ICoreBridge(coreBridge_(isMainnet, chainId_)),
      ITokenBridge(tokenBridge_(isMainnet, chainId_)),
      IWormholeRelayer(wormholeRelayer_(isMainnet, chainId_)),
      IUSDC(usdc_(isMainnet, chainId_)),
      cctpDomain_(isMainnet, chainId_),
      IMessageTransmitter(cctpMessageTransmitter_(isMainnet, chainId_)),
      ITokenMessenger(cctpTokenMessenger_(isMainnet, chainId_))
    );
    setUpFork(fork);
  }

  function setUpFork(Fork memory fork) internal {
    setUpOverrides(fork);
    addFork(fork);
  }

  // -- basic usage --

  modifier preserveFork() {
    uint originalFork = vm.activeFork();
    _;
    vm.selectFork(originalFork);
  }

  function selectFork(uint16 chainId_) internal { unchecked {
    uint index = chainIdToForkIndexPlusOne[chainId_];
    require(index != 0, "Chain not registered with ForkTest");
    vm.selectFork(forks[index-1].fork);
  }}

  function chainId() internal view returns (uint16) {
    return activeFork().chainId;
  }

  function chainName() internal view returns (string memory) {
    return activeFork().chainName;
  }

  function rpcUrl() internal view returns (string memory) {
    return activeFork().rpcUrl;
  }

  function coreBridge() internal view returns (ICoreBridge) {
    return activeFork().coreBridge;
  }

  function tokenBridge() internal view returns (ITokenBridge) {
    return activeFork().tokenBridge;
  }

  function wormholeRelayer() internal view returns (IWormholeRelayer) {
    return activeFork().relayer;
  }

  function usdc() internal view returns (IUSDC) {
    return activeFork().usdc;
  }

  function cctpDomain() internal view returns (uint32) {
    return activeFork().cctpDomain;
  }

  function cctpMessageTransmitter() internal view returns (IMessageTransmitter) {
    return activeFork().cctpMessageTransmitter;
  }

  function cctpTokenMessenger() internal view returns (ITokenMessenger) {
    return activeFork().cctpTokenMessenger;
  }

  function dealUsdc(address to, uint256 amount) internal {
    usdc().deal(to, amount);
  }

  // -- convenience functions --

  function setMessageFee(uint256 msgFee) internal {
    coreBridge().setMessageFee(msgFee);
  }

  function attestToken(address token) internal preserveFork {
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

  function fetchEncodedVaa() internal returns (bytes memory) {
    return fetchEncodedVaa(vm.getRecordedLogs());
  }

  function fetchEncodedVaa(Vm.Log[] memory logs) internal view returns (bytes memory) {
    return coreBridge().sign(
      coreBridge().fetchPublishedMessages(logs)[0]
    ).encode();
  }

  function fetchEncodedBurnMessageAndAttestation(
  ) internal returns (bytes memory encodedBurnMessage, bytes memory attestation) {
    return fetchEncodedBurnMessageAndAttestation(vm.getRecordedLogs());
  }

  function fetchEncodedBurnMessageAndAttestation(
    Vm.Log[] memory logs
  ) internal view returns (bytes memory encodedBurnMessage, bytes memory attestation) {
    CctpTokenBurnMessage memory burnMessage = cctpMessageTransmitter().fetchBurnMessages(logs)[0];
    return (burnMessage.encode(), cctpMessageTransmitter().sign(burnMessage));
  }

  // -- more low-level stuff --

  function activeFork() internal view returns (Fork storage fork) { unchecked {
    fork = forks[forkToForkIndexPlusOne[vm.activeFork()] - 1];
  }}

  function setUpOverrides(Fork memory fork) internal {
    fork.coreBridge.setUpOverride();
    if (address(fork.cctpMessageTransmitter) != address(0))
      fork.cctpMessageTransmitter.setUpOverride();
  }

  function addFork(Fork memory fork) internal { unchecked {
    require(fork.chainId != 0, "ChainId is not valid");
    require(address(fork.coreBridge) != address(0), "CoreBridge is not valid");
    require(chainIdToForkIndexPlusOne[fork.chainId] == 0, "Chain already has a fork");
    uint forkIndex = forks.length;
    forks.push(fork);
    forkToForkIndexPlusOne[fork.fork] = forkIndex + 1;
    chainIdToForkIndexPlusOne[fork.chainId] = forkIndex + 1;
  }}
}
