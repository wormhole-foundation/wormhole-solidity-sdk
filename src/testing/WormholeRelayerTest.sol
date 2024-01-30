pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "wormhole-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-sdk/interfaces/IWormhole.sol";
import "wormhole-sdk/interfaces/ITokenBridge.sol";
import "wormhole-sdk/interfaces/cctp/IMessageTransmitter.sol";
import "wormhole-sdk/interfaces/cctp/ITokenMessenger.sol";
import "wormhole-sdk/Utils.sol";

import "./UsdcDealer.sol";
import "./WormholeOverride.sol";
import "./CctpOverride.sol";
import "./ERC20Mock.sol";
import "./WormholeRelayer/DeliveryInstructionDecoder.sol";
import "./WormholeRelayer/ExecutionParameters.sol";
import "./WormholeRelayer/MockOffchainRelayer.sol";

struct ChainInfo {
    uint16 chainId;
    string name;
    string url;
    IWormholeRelayer relayer;
    ITokenBridge tokenBridge;
    IWormhole wormhole;
    IMessageTransmitter circleMessageTransmitter;
    ITokenMessenger circleTokenMessenger;
    IUSDC USDC;
}

struct ActiveFork {
    uint16 chainId;
    string name;
    string url;
    uint256 fork;
    IWormholeRelayer relayer;
    ITokenBridge tokenBridge;
    IWormhole wormhole;
    // USDC parameters - only non-empty for Ethereum, Avalanche, Optimism, Arbitrum mainnets/testnets
    IUSDC USDC;
    ITokenMessenger circleTokenMessenger;
    IMessageTransmitter circleMessageTransmitter;
}

abstract contract WormholeRelayerTest is Test {
    using WormholeOverride for IWormhole;
    using CctpOverride for IMessageTransmitter;
    using UsdcDealer for IUSDC;

    /**
     * @dev required override to initialize active forks before each test
     */
    function setUpFork(ActiveFork memory fork) public virtual;

    /**
     * @dev optional override that runs after all forks have been set up
     */
    function setUpGeneral() public virtual {}

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
                circleMessageTransmitter: chainInfos[i].circleMessageTransmitter,
                circleTokenMessenger: chainInfos[i].circleTokenMessenger,
                USDC: chainInfos[i].USDC
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
        // create and setup each active fork
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            uint16 chainId = activeForksList[i];
            ActiveFork storage fork = activeForks[chainId];
            fork.fork = vm.createSelectFork(fork.url);
            fork.wormhole.setUpOverride();
            if (address(fork.circleMessageTransmitter) != address(0))
                fork.circleMessageTransmitter.setUpOverride();
        }

        // run setUp virtual functions for each fork
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            ActiveFork memory fork = activeForks[activeForksList[i]];
            vm.selectFork(fork.fork);
            setUpFork(fork);
        }

        ActiveFork memory firstFork = activeForks[activeForksList[0]];
        vm.selectFork(firstFork.fork);
        mockOffchainRelayer = new MockOffchainRelayer();
        // register all active forks with the 'offchain' relayer
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            ActiveFork storage fork = activeForks[activeForksList[i]];
            mockOffchainRelayer.registerChain(
                fork.chainId,
                fork.wormhole,
                fork.circleMessageTransmitter,
                fork.relayer,
                fork.fork
            );
        }

        // Allow the offchain relayer to work on all forks
        vm.makePersistent(address(mockOffchainRelayer));

        vm.selectFork(firstFork.fork);
        setUpGeneral();

        vm.selectFork(firstFork.fork);
    }

    function performDelivery() public {
        performDelivery(vm.getRecordedLogs(), false);
    }

    function performDelivery(bool debugLogging) public {
        performDelivery(vm.getRecordedLogs(), debugLogging);
    }

    function performDelivery(Vm.Log[] memory logs) public {
        performDelivery(logs, false);
    }

    function performDelivery(Vm.Log[] memory logs, bool debugLogging) public {
        require(logs.length > 0, "no events recorded");
        mockOffchainRelayer.relay(logs, debugLogging);
    }

    function createAndAttestToken(
        uint16 homeChain
    ) public returns (ERC20Mock token) {
        uint256 originalFork = vm.activeFork();
        ActiveFork memory home = activeForks[homeChain];
        vm.selectFork(home.fork);

        token = new ERC20Mock("Test Token", "TST");
        token.mint(address(this), 5000e18);

        vm.recordLogs();
        home.tokenBridge.attestToken(address(token), 0);
        (, bytes memory attestation) = home.wormhole.sign(
            home.wormhole.fetchPublishedMessages(vm.getRecordedLogs())[0]
        );

        for (uint256 i = 0; i < activeForksList.length; ++i) {
            if (activeForksList[i] == home.chainId) {
                continue;
            }
            ActiveFork memory fork = activeForks[activeForksList[i]];
            vm.selectFork(fork.fork);
            fork.tokenBridge.createWrapped(attestation);
        }

        vm.selectFork(originalFork);
    }

    function mintUSDC(uint16 chain, address addr, uint256 amount) public {
        uint256 originalFork = vm.activeFork();
        ActiveFork memory current = activeForks[chain];
        vm.selectFork(current.fork);

        current.USDC.deal(addr, amount);

        vm.selectFork(originalFork);
    }

    function logFork() public view {
        uint256 fork = vm.activeFork();
        for (uint256 i = 0; i < activeForksList.length; ++i) {
            if (fork == activeForks[activeForksList[i]].fork) {
                console.log(
                    "%s fork active",
                    activeForks[activeForksList[i]].name
                );
                return;
            }
        }
    }

    function initChainInfo() private {
        chainInfosTestnet[6] = ChainInfo({
            chainId: 6,
            name: "fuji - avalanche",
            url: vm.envOr(
                "AVALANCHE_FUJI_RPC_URL",
                string("https://api.avax-test.network/ext/bc/C/rpc")
            ),
            relayer: IWormholeRelayer(
                0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB
            ),
            tokenBridge: ITokenBridge(
                0x61E44E506Ca5659E6c0bba9b678586fA2d729756
            ),
            wormhole: IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C),
            circleMessageTransmitter: IMessageTransmitter(
                0xa9fB1b3009DCb79E2fe346c16a604B8Fa8aE0a79
            ),
            circleTokenMessenger: ITokenMessenger(
                0xeb08f243E5d3FCFF26A9E38Ae5520A669f4019d0
            ),
            USDC: IUSDC(0x5425890298aed601595a70AB815c96711a31Bc65)
        });
        chainInfosTestnet[14] = ChainInfo({
            chainId: 14,
            name: "alfajores - celo",
            url: vm.envOr(
                "CELO_TESTNET_RPC_URL",
                string("https://alfajores-forno.celo-testnet.org")
            ),
            relayer: IWormholeRelayer(
                0x306B68267Deb7c5DfCDa3619E22E9Ca39C374f84
            ),
            tokenBridge: ITokenBridge(
                0x05ca6037eC51F8b712eD2E6Fa72219FEaE74E153
            ),
            wormhole: IWormhole(0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosTestnet[4] = ChainInfo({
            chainId: 4,
            name: "bsc testnet",
            url: vm.envOr(
                "BSC_TESTNET_RPC_URL",
                string("https://bsc-testnet.public.blastapi.io")
            ),
            relayer: IWormholeRelayer(
                0x80aC94316391752A193C1c47E27D382b507c93F3
            ),
            tokenBridge: ITokenBridge(
                0x9dcF9D205C9De35334D646BeE44b2D2859712A09
            ),
            wormhole: IWormhole(0x68605AD7b15c732a30b1BbC62BE8F2A509D74b4D),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosTestnet[5] = ChainInfo({
            chainId: 5,
            name: "polygon mumbai",
            url: vm.envOr(
                "POLYGON_MUMBAI_RPC_URL",
                string("https://rpc.ankr.com/polygon_mumbai")
            ),
            relayer: IWormholeRelayer(
                0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0
            ),
            tokenBridge: ITokenBridge(
                0x377D55a7928c046E18eEbb61977e714d2a76472a
            ),
            wormhole: IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20),
            circleMessageTransmitter: IMessageTransmitter(
                0xe09A679F56207EF33F5b9d8fb4499Ec00792eA73
            ),
            circleTokenMessenger: ITokenMessenger(
                0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5
            ),
            USDC: IUSDC(0x9999f7Fea5938fD3b1E26A12c3f2fb024e194f97)
        });
        chainInfosTestnet[16] = ChainInfo({
            chainId: 16,
            name: "moonbase alpha - moonbeam",
            url: vm.envOr(
                "MOONBASE_ALPHA_RPC_URL",
                string("https://rpc.testnet.moonbeam.network")
            ),
            relayer: IWormholeRelayer(
                0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0
            ),
            tokenBridge: ITokenBridge(
                0xbc976D4b9D57E57c3cA52e1Fd136C45FF7955A96
            ),
            wormhole: IWormhole(0xa5B7D85a8f27dd7907dc8FdC21FA5657D5E2F901),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[2] = ChainInfo({
            chainId: 2,
            name: "ethereum",
            url: vm.envOr(
                "ETHEREUM_RPC_URL",
                string("https://rpc.ankr.com/eth")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0x3ee18B2214AFF97000D974cf647E7C347E8fa585
            ),
            wormhole: IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B),
            circleMessageTransmitter: IMessageTransmitter(
                0x0a992d191DEeC32aFe36203Ad87D7d289a738F81
            ),
            circleTokenMessenger: ITokenMessenger(
                0xBd3fa81B58Ba92a82136038B25aDec7066af3155
            ),
            USDC: IUSDC(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
        });
        chainInfosMainnet[4] = ChainInfo({
            chainId: 4,
            name: "bsc",
            url: vm.envOr(
                "BSC_RPC_URL",
                string("https://bsc-dataseed2.defibit.io")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0xB6F6D86a8f9879A9c87f643768d9efc38c1Da6E7
            ),
            wormhole: IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[6] = ChainInfo({
            chainId: 6,
            name: "avalanche",
            url: vm.envOr(
                "AVALANCHE_RPC_URL",
                string("https://rpc.ankr.com/avalanche")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0x0e082F06FF657D94310cB8cE8B0D9a04541d8052
            ),
            wormhole: IWormhole(0x54a8e5f9c4CbA08F9943965859F6c34eAF03E26c),
            circleMessageTransmitter: IMessageTransmitter(
                0x8186359aF5F57FbB40c6b14A588d2A59C0C29880
            ),
            circleTokenMessenger: ITokenMessenger(
                0x6B25532e1060CE10cc3B0A99e5683b91BFDe6982
            ),
            USDC: IUSDC(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E)
        });
        chainInfosMainnet[10] = ChainInfo({
            chainId: 10,
            name: "fantom",
            url: vm.envOr(
                "FANTOM_RPC_URL",
                string("https://rpc.ankr.com/fantom")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0x7C9Fc5741288cDFdD83CeB07f3ea7e22618D79D2
            ),
            wormhole: IWormhole(0x126783A6Cb203a3E35344528B26ca3a0489a1485),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[13] = ChainInfo({
            chainId: 13,
            name: "klaytn",
            url: vm.envOr(
                "KLAYTN_RPC_URL",
                string("https://klaytn-mainnet-rpc.allthatnode.com:8551")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0x5b08ac39EAED75c0439FC750d9FE7E1F9dD0193F
            ),
            wormhole: IWormhole(0x0C21603c4f3a6387e241c0091A7EA39E43E90bb7),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[14] = ChainInfo({
            chainId: 14,
            name: "celo",
            url: vm.envOr("CELO_RPC_URL", string("https://forno.celo.org")),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0x796Dff6D74F3E27060B71255Fe517BFb23C93eed
            ),
            wormhole: IWormhole(0xa321448d90d4e5b0A732867c18eA198e75CAC48E),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[12] = ChainInfo({
            chainId: 12,
            name: "acala",
            url: vm.envOr(
                "ACALA_RPC_URL",
                string("https://eth-rpc-acala.aca-api.network")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0xae9d7fe007b3327AA64A32824Aaac52C42a6E624
            ),
            wormhole: IWormhole(0xa321448d90d4e5b0A732867c18eA198e75CAC48E),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[11] = ChainInfo({
            chainId: 11,
            name: "karura",
            url: vm.envOr(
                "KARURA_RPC_URL",
                string("https://eth-rpc-karura.aca-api.network")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0xae9d7fe007b3327AA64A32824Aaac52C42a6E624
            ),
            wormhole: IWormhole(0xa321448d90d4e5b0A732867c18eA198e75CAC48E),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[16] = ChainInfo({
            chainId: 16,
            name: "moombeam",
            url: vm.envOr(
                "MOOMBEAM_RPC_URL",
                string("https://rpc.ankr.com/moonbeam")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0xB1731c586ca89a23809861c6103F0b96B3F57D92
            ),
            wormhole: IWormhole(0xC8e2b0cD52Cf01b0Ce87d389Daa3d414d4cE29f3),
            circleMessageTransmitter: IMessageTransmitter(address(0)),
            circleTokenMessenger: ITokenMessenger(address(0)),
            USDC: IUSDC(address(0))
        });
        chainInfosMainnet[23] = ChainInfo({
            chainId: 23,
            name: "arbitrum",
            url: vm.envOr(
                "ARBITRUM_RPC_URL",
                string("https://rpc.ankr.com/arbitrum")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0x0b2402144Bb366A632D14B83F244D2e0e21bD39c
            ),
            wormhole: IWormhole(0xa5f208e072434bC67592E4C49C1B991BA79BCA46),
            circleMessageTransmitter: IMessageTransmitter(
                0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca
            ),
            circleTokenMessenger: ITokenMessenger(
                0x19330d10D9Cc8751218eaf51E8885D058642E08A
            ),
            USDC: IUSDC(0xaf88d065e77c8cC2239327C5EDb3A432268e5831)
        });
        chainInfosMainnet[24] = ChainInfo({
            chainId: 24,
            name: "optimism",
            url: vm.envOr(
                "OPTIMISM_RPC_URL",
                string("https://rpc.ankr.com/optimism")
            ),
            relayer: IWormholeRelayer(
                0x27428DD2d3DD32A4D7f7C497eAaa23130d894911
            ),
            tokenBridge: ITokenBridge(
                0x1D68124e65faFC907325e3EDbF8c4d84499DAa8b
            ),
            wormhole: IWormhole(0xEe91C335eab126dF5fDB3797EA9d6aD93aeC9722),
            circleMessageTransmitter: IMessageTransmitter(
                0x4D41f22c5a0e5c74090899E5a8Fb597a8842b3e8
            ),
            circleTokenMessenger: ITokenMessenger(
                0x2B4069517957735bE00ceE0fadAE88a26365528f
            ),
            USDC: IUSDC(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85)
        });
        chainInfosMainnet[30] = ChainInfo({
            chainId: 30,
            name: "base",
            url: vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org")),
            relayer: IWormholeRelayer(
                0x706F82e9bb5b0813501714Ab5974216704980e31
            ),
            tokenBridge: ITokenBridge(
                0x8d2de8d2f73F1F4cAB472AC9A881C9b123C79627
            ),
            wormhole: IWormhole(0xbebdb6C8ddC678FfA9f8748f85C815C556Dd8ac6),
            circleMessageTransmitter: IMessageTransmitter(
                address(0xAD09780d193884d503182aD4588450C416D6F9D4)
            ),
            circleTokenMessenger: ITokenMessenger(
                address(0x1682Ae6375C4E4A97e4B583BC394c861A46D8962)
            ),
            USDC: IUSDC(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913))
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

    function setTestnetForkChains(
        uint16 _sourceChain,
        uint16 _targetChain
    ) public {
        ChainInfo[] memory forks = new ChainInfo[](2);
        forks[0] = chainInfosTestnet[_sourceChain];
        forks[1] = chainInfosTestnet[_targetChain];
        setActiveForks(forks);
    }

    function setMainnetForkChains(
        uint16 _sourceChain,
        uint16 _targetChain
    ) public {
        ChainInfo[] memory forks = new ChainInfo[](2);
        forks[0] = chainInfosMainnet[_sourceChain];
        forks[1] = chainInfosMainnet[_targetChain];
        setActiveForks(forks);
    }

    function setForkChains(
        bool testnet,
        uint16 _sourceChain,
        uint16 _targetChain
    ) public {
        if (testnet) {
            setTestnetForkChains(_sourceChain, _targetChain);
            return;
        }
        setMainnetForkChains(_sourceChain, _targetChain);
    }
}
