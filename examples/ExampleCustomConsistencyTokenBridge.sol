// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {IERC20} from "IERC20/IERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {CoreBridgeLib} from "wormhole-sdk/libraries/CoreBridge.sol";
import {
    CustomConsistencyLib
} from "wormhole-sdk/libraries/CustomConsistency.sol";
import {
    HashReplayProtectionLib
} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {VaaLib} from "wormhole-sdk/libraries/VaaLib.sol";
import "wormhole-sdk/constants/ConsistencyLevel.sol";

/*
    Wormhole implements a feature that allows custom contracts to define custom consistency levels and finality requirements. This is configured by setting the `consistencyLevel` parameter in the `publishMessage` function to `ConsistencyLevelCustom`, which is 203.

    // https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/sdk/vaa/structs.go#L108
    const (
        ConsistencyLevelPublishImmediately = uint8(200)
        ConsistencyLevelSafe               = uint8(201)
        ConsistencyLevelFinalized          = uint8(202)
        ConsistencyLevelCustom             = uint8(203)
    )   

    NOTE that there is a possibility that ConsistencyLevelCustom will default to use ConsistencyLevelFinalized due to (but not limited to) any of the following reasons:
    - The watcher did not enable the feature for the specific chain
    - Consistency level is not explicitly configured in the custom consistency contract address (`cclContract`)
    - Configured consistency level in the cclContract is invalid
        
    See more in https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/node/pkg/watchers/evm/watcher.go#L852-L855 & https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/node/pkg/watchers/evm/custom_consistency_level.go#L169-L186
*/
contract ExampleCustomConsistencyTokenBridge {
    using SafeERC20 for IERC20;
    using BytesParsing for bytes;

    // Wormhole core bridge contract
    // Source code: https://github.com/wormhole-foundation/wormhole/blob/main/ethereum/contracts/Implementation.sol
    ICoreBridge immutable coreBridge;

    // Custom consistency contract address
    // Allows the owner to define a custom consistency level and additional blocks to elapse before starting to process a message
    // See src/libraries/CustomConsistency.sol
    address immutable cclContract;

    // The token address
    IERC20 immutable token;

    // Owner of this contract
    address public owner;

    // List of peers from various chains
    // This is used for validating the emitterAddress, see https://wormhole.com/docs/products/messaging/guides/core-contracts/#validating-the-emitter
    // This mapping is based on Wormhole chain ID mappings in src/constants/Chains.sol
    mapping(uint16 => bytes32) public peers;

    constructor(
        address coreBridgeAddress,
        address tokenAddress,
        address customConsistencyAddress,
        address ownerAddress,
        uint8 requiredConsistencyLevel,
        uint16 requiredBlocksToWait
    ) {
        require(coreBridgeAddress != address(0), "Invalid address");
        require(tokenAddress != address(0), "Invalid address");
        require(customConsistencyAddress != address(0), "Invalid address");
        require(ownerAddress != address(0), "Invalid address");

        coreBridge = ICoreBridge(coreBridgeAddress);
        token = IERC20(tokenAddress);
        cclContract = customConsistencyAddress;
        owner = ownerAddress;

        // Set the required consistency level and blocks to wait in the CCL contract
        // The Guardians will read from the `cclContract` and will only start processing a message emission after the specified additional blocks have elapsed
        // For example, our contract may want an additional delay of 10 blocks before the watcher starts processing observations
        // See https://github.com/wormhole-foundation/wormhole/blob/5af2e5e8ccf2377771e8a3bc741ed8772ddd4d47/node/pkg/watchers/evm/watcher.go#L528-L536
        CustomConsistencyLib.setAdditionalBlocksConfig(
            cclContract,
            requiredConsistencyLevel,
            requiredBlocksToWait
        );
    }

    // Entry point for users to send tokens from this chain (source chain) to destination chain
    function sendToken(address to, uint256 amount) external payable {
        uint256 wormholeFee = coreBridge.messageFee();

        // require users to pay Wormhole fee
        require(msg.value == wormholeFee, "invalid fee");

        // The SafeERC20 library function can be used exactly as the OZ equivalent
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Construct the payload for the token transfer message
        bytes memory payload = abi.encodePacked(to, amount);

        // We use CONSISTENCY_LEVEL_CUSTOM here so the watcher will read from cclContract to determine our configured consistency levels
        // See src/constants/ConsistencyLevel.sol
        coreBridge.publishMessage{value: wormholeFee}(
            0,
            payload,
            CONSISTENCY_LEVEL_CUSTOM
        );
    }

    // Entry point when we receive a cross-chain message from other chains
    function receiveToken(bytes calldata vaa) external {
        // First we need to parse and verify the VAA
        // CoreBridgeLib.decodeAndVerifyVaaCd will do this for us
        // It is functionalty equivalent to calling parseAndVerifyVM on the core bridge contract
        (
            , //timestamp is ignored
            , //nonce is ignored
            uint16 emitterChainId,
            bytes32 emitterAddress,
            , // sequence is ignored
            , // consistencyLevel is ignored
            bytes memory payload
        ) = CoreBridgeLib.decodeAndVerifyVaaCd(address(coreBridge), vaa);

        // By the time this entry point is executed, our configured `consistencyLevel` and `blocksToWait` in the `cclContract` should already be enforced by the watcher

        // Perform replay protection via the hash of the VAA
        // We are using hash replay protections here as the consistency levels may not be finalized yet
        // This function will revert if the VAA has already been processed/consumed

        // NOTE we use `calcVaaSingleHashCd` to compute the VAA's `Body` hash once (single-hashed) and not doubly hashed
        // See src/libraries/ReplayProtection.sol and https://wormhole.com/docs/protocol/infrastructure/vaas/#signatures for more details
        bytes32 vaaHash = VaaLib.calcVaaSingleHashCd(vaa);
        HashReplayProtectionLib.replayProtect(vaaHash);

        // Ensure that the contract that emits the message is our trusted contract on the source chain
        // See the `setPeer` function for more context
        require(peers[emitterChainId] != bytes32(0), "Invalid peer address!");
        require(
            peers[emitterChainId] == emitterAddress,
            "Incorrect peer/emitter from source chain"
        );

        // Now we have verified the VAA is valid, checked the emitter, and ensured it hasn't been processed before
        // We can process the payload
        // We know the payload contains an address and a uint256 amount and we can start parsing from the beginning
        uint256 offset = 0;
        address to;
        uint256 amount;

        // `asAddressMem` and `asUint256Mem` will validate the offsets internally via the `checkBound` function
        // The corresponding unchecked variants (`asAddressMemUnchecked` and `asUint256MemUnchecked`) could be used for gas optimization purposes, however it requires an additional `checkLength` call to ensure the offsets are correct, see examples/ExampleCustomTokenBridge.sol
        (to, offset) = payload.asAddressMem(offset);
        (amount, offset) = payload.asUint256Mem(offset);

        // Finally we can transfer the tokens to the recipient
        // Again, this is functionally equivalent to the OZ SafeERC20 library
        // Here we assume the contract has enough balance to cover the transfer, but a real implementation
        // would likely have more complex logic to handle this
        token.safeTransfer(to, amount);
    }

    // Owner updates contract configuration
    function updateConfiguration(
        address ownerAddress,
        uint8 requiredConsistencyLevel,
        uint16 requiredBlocksToWait
    ) external onlyOwner {
        require(ownerAddress != address(0), "Invalid address");

        owner = ownerAddress;
        CustomConsistencyLib.setAdditionalBlocksConfig(
            cclContract,
            requiredConsistencyLevel,
            requiredBlocksToWait
        );
    }

    // Owner updates the peer address so we are only accepting messages emitted by trusted contracts from other chains
    // This is important to ensure we are not listening to a faulty contract that tries to mint valuable tokens on the destination chain
    // See https://wormhole.com/docs/products/messaging/guides/core-contracts/#validating-the-emitter
    function setPeer(uint16 chainId, bytes32 peerAddress) external onlyOwner {
        peers[chainId] = peerAddress;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
