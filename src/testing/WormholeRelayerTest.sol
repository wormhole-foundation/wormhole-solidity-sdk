// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/interfaces/IWormholeRelayer.sol";
import "../../src/interfaces/IWormhole.sol";
import "../../src/interfaces/ITokenBridge.sol";
import "../../src/Utils.sol";

import "./helpers/WormholeSimulator.sol";
import "./ERC20Mock.sol";
import "./helpers/DeliveryInstructionDecoder.sol";
import "./helpers/ExecutionParameters.sol";
import "./helpers/MockOffchainRelayer.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

struct ChainInfo {
    uint16 chainId;
    string name;
    string url;
    IWormholeRelayer relayer;
    ITokenBridge tokenBridge;
    IWormhole wormhole;
}

struct ActiveFork {
    uint16 chainId;
    string name;
    string url;
    uint256 fork;
    IWormholeRelayer relayer;
    ITokenBridge tokenBridge;
    IWormhole wormhole;
    WormholeSimulator guardian;
}

abstract contract WormholeRelayerTest is Test {
    /**
     * @dev required override to initialize active forks before each test
     */
    function setUpFork(ActiveFork memory fork) public virtual;

    /**
     * @dev optional override that runs after all forks have been set up
     */
    function setUpGeneral() public virtual {}

    uint256 constant DEVNET_GUARDIAN_PK = 0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;

    // conveneince information to set up tests against testnet/mainnet forks
    mapping(uint16 => ChainInfo) public chainInfosTestnet;
    mapping(uint16 => ChainInfo) public chainInfosMainnet;

    // active forks for the test
    mapping(uint16 => ActiveFork) public activeForks;
    uint16[] public activeForksList;

    MockOffchainRelayer public mockOffchainRelayer;

    constructor() {
        initChainInfo();

        // set default active forks. These can be overridden in your test
        ChainInfo[] memory forks = new ChainInfo[](2);
        forks[0] = chainInfosTestnet[6]; // fuji avax
        forks[1] = chainInfosTestnet[14]; // alfajores celo
        setActiveForks(forks);
    }

    function _setActiveForks(ChainInfo[] memory chainInfos) internal virtual {
        if (chainInfos.length < 2) {
            console.log("setActiveForks: 2 or more forks must be specified");
            revert("setActiveForks: 2 or more forks must be specified");
        }
        activeForksList = new uint16[](chainInfos.length);
        for (uint256 i = 0; i < chainInfos.length; i++) {
            activeForksList[i] = chainInfos[i].chainId;
            activeForks[chainInfos[i].chainId] = ActiveFork({
                chainId: chainInfos[i].chainId,
                url: chainInfos[i].url,
                name: chainInfos[i].name,
                relayer: chainInfos[i].relayer,
                tokenBridge: chainInfos[i].tokenBridge,
                wormhole: chainInfos[i].wormhole,
                // patch these in setUp() once we have the fork
                fork: 0,
                guardian: WormholeSimulator(address(0))
            });
        }
    }

    function setActiveForks(ChainInfo[] memory chainInfos) public virtual {
        _setActiveForks(chainInfos);
    }

    function setUp() public virtual {
        _setUp();
    }

    function _setUp() internal {
        // create fork and guardian for each active fork
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            uint16 chainId = activeForksList[i];
            ActiveFork storage fork = activeForks[chainId];
            fork.fork = vm.createSelectFork(fork.url);
            fork.guardian = new WormholeSimulator(
                address(fork.wormhole),
                DEVNET_GUARDIAN_PK
            );
        }

        // run setUp virtual functions for each fork
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            ActiveFork memory fork = activeForks[activeForksList[i]];
            vm.selectFork(fork.fork);
            setUpFork(fork);
        }

        ActiveFork memory firstFork = activeForks[activeForksList[0]];
        vm.selectFork(firstFork.fork);
        mockOffchainRelayer = new MockOffchainRelayer(address(firstFork.wormhole), address(firstFork.guardian), vm);
        // register all active forks with the 'offchain' relayer
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            ActiveFork storage fork = activeForks[activeForksList[i]];
            mockOffchainRelayer.registerChain(fork.chainId, address(fork.relayer), fork.fork);
        }

        // Allow the offchain relayer to work on all forks
        vm.makePersistent(address(mockOffchainRelayer));

        vm.selectFork(firstFork.fork);
        setUpGeneral();

        vm.selectFork(firstFork.fork);
    }

    function performDelivery() public {
        performDelivery(vm.getRecordedLogs());
    }

    function performDelivery(Vm.Log[] memory logs, bool debugLogging) public {
        require(logs.length > 0, "no events recorded");
        mockOffchainRelayer.relay(logs, debugLogging);
    }

    function performDelivery(Vm.Log[] memory logs) public {
        require(logs.length > 0, "no events recorded");
        mockOffchainRelayer.relay(logs);
    }

    function createAndAttestToken(uint16 homeChain) public returns (ERC20Mock token) {
        uint256 originalFork = vm.activeFork();
        ActiveFork memory home = activeForks[homeChain];
        vm.selectFork(home.fork);

        token = new ERC20Mock("Test Token", "TST");
        token.mint(address(this), 5000e18);

        vm.recordLogs();
        home.tokenBridge.attestToken(address(token), 0);
        Vm.Log memory log = home.guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs())[0];
        bytes memory attestation = home.guardian.fetchSignedMessageFromLogs(log, home.chainId);

        for (uint256 i = 0; i < activeForksList.length; ++i) {
            if(activeForksList[i] == home.chainId) {
                continue;
            }
            ActiveFork memory fork = activeForks[activeForksList[i]];
            vm.selectFork(fork.fork);
            fork.tokenBridge.createWrapped(attestation);
        }

        vm.selectFork(originalFork);
    }

    function logFork() public view {
        uint256 fork = vm.activeFork();
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            if (fork == activeForks[activeForksList[i]].fork) {
                console.log("%s fork active", activeForks[activeForksList[i]].name);
                return;
            }
        }
    }

    function initChainInfo() private {
        chainInfosTestnet[6] = ChainInfo({
            chainId: 6,
            name: "fuji - avalanche",
            url: "https://api.avax-test.network/ext/bc/C/rpc",
            relayer: IWormholeRelayer(0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB),
            tokenBridge: ITokenBridge(0x61E44E506Ca5659E6c0bba9b678586fA2d729756),
            wormhole: IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C)
        });
        chainInfosTestnet[14] = ChainInfo({
            chainId: 14,
            name: "alfajores - celo",
            url: "https://alfajores-forno.celo-testnet.org",
            relayer: IWormholeRelayer(0x306B68267Deb7c5DfCDa3619E22E9Ca39C374f84),
            tokenBridge: ITokenBridge(0x05ca6037eC51F8b712eD2E6Fa72219FEaE74E153),
            wormhole: IWormhole(0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56)
        });
        chainInfosTestnet[4] = ChainInfo({
            chainId: 4,
            name: "bsc testnet",
            url: "https://bsc-testnet.public.blastapi.io",
            relayer: IWormholeRelayer(0x80aC94316391752A193C1c47E27D382b507c93F3),
            tokenBridge: ITokenBridge(0x9dcF9D205C9De35334D646BeE44b2D2859712A09),
            wormhole: IWormhole(0x68605AD7b15c732a30b1BbC62BE8F2A509D74b4D)
        });
        chainInfosTestnet[5] = ChainInfo({
            chainId: 5,
            name: "polygon mumbai",
            url: "https://rpc.ankr.com/polygon_mumbai",
            relayer: IWormholeRelayer(0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0),
            tokenBridge: ITokenBridge(0x377D55a7928c046E18eEbb61977e714d2a76472a),
            wormhole: IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20)
        });
        chainInfosTestnet[16] = ChainInfo({
            chainId: 16,
            name: "moonbase alpha - moonbeam",
            url: "https://rpc.testnet.moonbeam.network",
            relayer: IWormholeRelayer(0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0),
            tokenBridge: ITokenBridge(0xbc976D4b9D57E57c3cA52e1Fd136C45FF7955A96),
            wormhole: IWormhole(0xa5B7D85a8f27dd7907dc8FdC21FA5657D5E2F901)
        });

        chainInfosMainnet[2] = ChainInfo({
            chainId: 2,
            name: "ethereum",
            url: "https://rpc.ankr.com/eth",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0x3ee18B2214AFF97000D974cf647E7C347E8fa585),
            wormhole: IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B)
        });
        chainInfosMainnet[4] = ChainInfo({
            chainId: 4,
            name: "bsc",
            url: "https://bsc-dataseed2.defibit.io",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0xB6F6D86a8f9879A9c87f643768d9efc38c1Da6E7),
            wormhole: IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B)
        });
        chainInfosMainnet[6] = ChainInfo({
            chainId: 6,
            name: "avalanche",
            url: "https://rpc.ankr.com/avalanche",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0x0e082F06FF657D94310cB8cE8B0D9a04541d8052),
            wormhole: IWormhole(0x54a8e5f9c4CbA08F9943965859F6c34eAF03E26c)
        });
        chainInfosMainnet[10] = ChainInfo({
            chainId: 10,
            name: "fantom",
            url: "https://rpc.ankr.com/fantom",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0x7C9Fc5741288cDFdD83CeB07f3ea7e22618D79D2),
            wormhole: IWormhole(0x126783A6Cb203a3E35344528B26ca3a0489a1485)
        });
        chainInfosMainnet[13] = ChainInfo({
            chainId: 13,
            name: "klaytn",
            url: "https://klaytn-mainnet-rpc.allthatnode.com:8551",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0x5b08ac39EAED75c0439FC750d9FE7E1F9dD0193F),
            wormhole: IWormhole(0x0C21603c4f3a6387e241c0091A7EA39E43E90bb7)
        });
        chainInfosMainnet[14] = ChainInfo({
            chainId: 14,
            name: "celo",
            url: "https://forno.celo.org",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0x796Dff6D74F3E27060B71255Fe517BFb23C93eed),
            wormhole: IWormhole(0xa321448d90d4e5b0A732867c18eA198e75CAC48E)
        });
        chainInfosMainnet[12] = ChainInfo({
            chainId: 12,
            name: "acala",
            url: "https://eth-rpc-acala.aca-api.network",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0xae9d7fe007b3327AA64A32824Aaac52C42a6E624),
            wormhole: IWormhole(0xa321448d90d4e5b0A732867c18eA198e75CAC48E)
        });
        chainInfosMainnet[11] = ChainInfo({
            chainId: 11,
            name: "karura",
            url: "https://eth-rpc-karura.aca-api.network",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0xae9d7fe007b3327AA64A32824Aaac52C42a6E624),
            wormhole: IWormhole(0xa321448d90d4e5b0A732867c18eA198e75CAC48E)
        });
        chainInfosMainnet[16] = ChainInfo({
            chainId: 16,
            name: "moombeam",
            url: "https://rpc.ankr.com/moonbeam",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0xB1731c586ca89a23809861c6103F0b96B3F57D92),
            wormhole: IWormhole(0xC8e2b0cD52Cf01b0Ce87d389Daa3d414d4cE29f3)
        });
        chainInfosMainnet[23] = ChainInfo({
            chainId: 23,
            name: "arbitrum",
            url: "https://rpc.ankr.com/arbitrum",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0x0b2402144Bb366A632D14B83F244D2e0e21bD39c),
            wormhole: IWormhole(0xa5f208e072434bC67592E4C49C1B991BA79BCA46)
        });
        chainInfosMainnet[24] = ChainInfo({
            chainId: 24,
            name: "optimism",
            url: "https://rpc.ankr.com/arbitrum",
            relayer: IWormholeRelayer(0x27428DD2d3DD32A4D7f7C497eAaa23130d894911),
            tokenBridge: ITokenBridge(0x1D68124e65faFC907325e3EDbF8c4d84499DAa8b),
            wormhole: IWormhole(0xEe91C335eab126dF5fDB3797EA9d6aD93aeC9722)
        });
    }

    receive() external payable {}
}

abstract contract WormholeRelayerBasicTest is WormholeRelayerTest {
    /**
     * @dev virtual function to initialize source chain before each test
     */
    function setUpSource() public virtual;

    /**
     * @dev virtual function to initialize target chain before each test
     */
    function setUpTarget() public virtual;

    /**
     * @dev virtual function to initialize other active forks before each test
     * Note: not called for source/target forks
     */
    function setUpOther(ActiveFork memory fork) public virtual {}

    /* 
     * aliases for activeForks
     */

    ChainInfo public sourceChainInfo;
    ChainInfo public targetChainInfo;

    uint16 public sourceChain;
    uint16 public targetChain;

    uint256 public sourceFork;
    uint256 public targetFork;

    IWormholeRelayer public relayerSource;
    ITokenBridge public tokenBridgeSource;
    IWormhole public wormholeSource;

    IWormholeRelayer public relayerTarget;
    ITokenBridge public tokenBridgeTarget;
    IWormhole public wormholeTarget;

    WormholeSimulator public guardianSource;
    WormholeSimulator public guardianTarget;

    /* 
     * end activeForks aliases 
     */

    constructor() WormholeRelayerTest() {
        setTestnetForkChains(6, 14);
    }

    function setUp() public override {
        sourceFork = 0;
        targetFork = 1;
        _setUp();
        // aliases can't be set until after setUp
        guardianSource = activeForks[activeForksList[0]].guardian;
        guardianTarget = activeForks[activeForksList[1]].guardian;
        sourceFork = activeForks[activeForksList[0]].fork;
        targetFork = activeForks[activeForksList[1]].fork;
    }

    function setUpFork(ActiveFork memory fork) public override {
        if (fork.chainId == sourceChain) {
            setUpSource();
        } else if (fork.chainId == targetChain) {
            setUpTarget();
        } else {
            setUpOther(fork);
        }
    }

    function setActiveForks(ChainInfo[] memory chainInfos) public override {
        _setActiveForks(chainInfos);

        sourceChainInfo = chainInfos[0];
        sourceChain = sourceChainInfo.chainId;
        relayerSource = sourceChainInfo.relayer;
        tokenBridgeSource = sourceChainInfo.tokenBridge;
        wormholeSource = sourceChainInfo.wormhole;

        targetChainInfo = chainInfos[1];
        targetChain = targetChainInfo.chainId;
        relayerTarget = targetChainInfo.relayer;
        tokenBridgeTarget = targetChainInfo.tokenBridge;
        wormholeTarget = targetChainInfo.wormhole;
    }

    function setTestnetForkChains(uint16 _sourceChain, uint16 _targetChain) public {
        ChainInfo[] memory forks = new ChainInfo[](2);
        forks[0] = chainInfosTestnet[_sourceChain];
        forks[1] = chainInfosTestnet[_targetChain];
        setActiveForks(forks);
    }

    function setMainnetForkChains(uint16 _sourceChain, uint16 _targetChain) public {
        ChainInfo[] memory forks = new ChainInfo[](2);
        forks[0] = chainInfosMainnet[_sourceChain];
        forks[1] = chainInfosMainnet[_targetChain];
        setActiveForks(forks);
    }
}
