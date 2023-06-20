// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/interfaces/IWormholeRelayer.sol";
import "../../src/interfaces/IWormhole.sol";
import "../../src/interfaces/ITokenBridge.sol";

import "./helpers/WormholeSimulator.sol";
import "./ERC20Mock.sol";
import "./helpers/DeliveryInstructionDecoder.sol";
import "./helpers/ExecutionParameters.sol";
import "./helpers/MockOffchainRelayer.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

abstract contract WormholeRelayerTest is Test {
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;

    string public constant FUJI_URL =
        "https://api.avax-test.network/ext/bc/C/rpc";
    string public constant CELO_URL =
        "https://alfajores-forno.celo-testnet.org";

    uint16 public constant sourceChain = 6; // fuji testnet
    uint16 public constant targetChain = 14; // celo testnet

    uint public sourceFork;
    uint public targetFork;

    WormholeSimulator public guardianSource;
    WormholeSimulator public guardianTarget;

    // fuji testnet forked contracts
    IWormholeRelayer public relayerSource =
        IWormholeRelayer(0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB);
    ITokenBridge public tokenBridgeSource =
        ITokenBridge(0x61E44E506Ca5659E6c0bba9b678586fA2d729756);
    IWormhole public wormholeSource =
        IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C);

    // celo testnet forked contracts
    IWormholeRelayer public relayerTarget =
        IWormholeRelayer(0x306B68267Deb7c5DfCDa3619E22E9Ca39C374f84);
    ITokenBridge public tokenBridgeTarget =
        ITokenBridge(0x05ca6037eC51F8b712eD2E6Fa72219FEaE74E153);
    IWormhole public wormholeTarget =
        IWormhole(0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56);

    MockOffchainRelayer public mockOffchainRelayer;

    function setUpSource() public virtual;

    function setUpTarget() public virtual;

    function setUp() public {
        sourceFork = vm.createSelectFork(FUJI_URL);
        guardianSource = new WormholeSimulator(
            address(wormholeSource),
            DEVNET_GUARDIAN_PK
        );

        targetFork = vm.createSelectFork(CELO_URL);
        guardianTarget = new WormholeSimulator(
            address(wormholeTarget),
            DEVNET_GUARDIAN_PK
        );

        vm.selectFork(sourceFork);
        setUpSource();
        vm.selectFork(targetFork);
        setUpTarget();

        vm.selectFork(sourceFork);

        
        mockOffchainRelayer = new MockOffchainRelayer(address(wormholeSource), address(guardianSource), vm);
        mockOffchainRelayer.registerChain(sourceChain, address(relayerSource), sourceFork);
        mockOffchainRelayer.registerChain(targetChain, address(relayerTarget), targetFork);

        // Allow the offchain relayer to work on both source and target fork
        vm.makePersistent(address(mockOffchainRelayer));

    }

    function performDelivery() public {
        
        performDelivery(vm.getRecordedLogs());
    }

    function performDelivery(Vm.Log[] memory logs) public {

        require(logs.length > 0, "no events recorded");
        mockOffchainRelayer.relay(logs);
    }

    function createAndAttestToken(uint fork) public returns (ERC20Mock token) {
        vm.selectFork(fork);

        token = new ERC20Mock("Test Token", "TST");
        token.mint(address(this), 5000e18);

        ITokenBridge tokenBridge = fork == sourceFork
            ? tokenBridgeSource
            : tokenBridgeTarget;
        vm.recordLogs();
        tokenBridge.attestToken(address(token), 0);
        WormholeSimulator guardian = fork == sourceFork
            ? guardianSource
            : guardianTarget;
        Vm.Log memory log = guardian.fetchWormholeMessageFromLog(
            vm.getRecordedLogs()
        )[0];
        uint16 chainId = fork == sourceFork ? sourceChain : targetChain;
        bytes memory attestation = guardian.fetchSignedMessageFromLogs(
            log,
            chainId
        );

        vm.selectFork(fork == sourceFork ? targetFork : sourceFork);
        tokenBridge = fork == sourceFork
            ? tokenBridgeTarget
            : tokenBridgeSource;
        tokenBridge.createWrapped(attestation);
        vm.selectFork(fork);
    }

    function logFork() public view {
        console.log(
            vm.activeFork() == sourceFork
                ? "source fork active"
                : "target fork active"
        );
    }

    receive() external payable {}
}
