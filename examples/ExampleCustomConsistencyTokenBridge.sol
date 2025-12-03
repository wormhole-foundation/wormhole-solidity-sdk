// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {IERC20} from "IERC20/IERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {ITokenBridge} from "wormhole-sdk/interfaces/ITokenBridge.sol";
import {CoreBridgeLib} from "wormhole-sdk/libraries/CoreBridge.sol";
import {CustomConsistencyLib} from "wormhole-sdk/libraries/CustomConsistency.sol";
import {HashReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

contract ExampleCustomConsistencyTokenBridge { //todo name could be better?
    using SafeERC20 for IERC20;
    using BytesParsing for bytes;

    // See https://wormhole.com/docs/products/reference/consistency-levels/
    // uint8 public constant consistencyLevel = 1; // finalized

    // Wormhole token bridge contract
    // Source code: https://github.com/wormhole-foundation/wormhole/blob/main/ethereum/contracts/Implementation.sol
    ICoreBridge public coreBridge;

    // Custom consistency contract address
    // Allows the owner to define a custom consistency level and block numbers to elapse before accepting a cross-chain message
    // See src/libraries/CustomConsistency.sol
    address public cclContract;

    // The token address
    IERC20 public token;

    // Owner of this contract
    address public owner;

    // List of deployed bridge address from various chains
    // This is used for validating the emitterAddress, see https://wormhole.com/docs/products/messaging/guides/core-contracts/#validating-the-emitter
    mapping(uint16 => bytes32) public peers;

    // Seconds per block minted
    uint16 public secondsPerBlock;

    constructor(
        address coreBridgeAddress,
        address tokenAddress,
        address customConsistencyAddress,
        address ownerAddress,
        uint16 _secondsPerBlock,
        uint8 requiredConsistencyLevel,
        uint16 requiredBlocksToWait
    ) {
        coreBridge = ICoreBridge(coreBridgeAddress);
        token = IERC20(tokenAddress);
        cclContract = customConsistencyAddress;
        owner = ownerAddress;
        secondsPerBlock = _secondsPerBlock;

        // Set the required consistency level and blocks to wait in the CCL contract
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

        // The SafeERC20 ibrary function can be used exactly as the OZ equivalent
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Construct the payload for the token transfer message
        bytes memory payload = abi.encodePacked(to, amount);

        // Enforce custom consistency level defined
        (uint8 requiredConsistencyLevel, ) = CustomConsistencyLib
            .getAdditionalBlocksConfig(cclContract);

        coreBridge.publishMessage{value: wormholeFee}(
            0,
            payload,
            requiredConsistencyLevel
        );
    }

    // Entry point when we receive a cross-chain message from other chains
    function receiveToken(bytes memory vaa) external {
        // First we need to parse and verify the VAA
        // CoreBridgeLib.decodeAndVerifyVaaMem will do this for us
        // It is functionalty equivalent to calling parseAndVerifyVM on the core bridge contract
        (
            uint32 timestamp,
            , //nonce is ignored
            uint16 emitterChainId,
            bytes32 emitterAddress, 
            , // sequence is ignored
            uint8 consistencyLevel,
            bytes memory payload
        ) = CoreBridgeLib.decodeAndVerifyVaaMem(address(coreBridge), vaa);

        // Perform replay protection via the hash of the VAA
        // We are using hash replay protections here as the consistency levels may not be finalized yet
        // This function will revert if the VAA has already been processed/consumed
        bytes32 vaaHash = keccak256(vaa);
        HashReplayProtectionLib.replayProtect(vaaHash);

        (
            uint8 requiredConsistencyLevel,
            uint16 requiredBlocksToWait
        ) = CustomConsistencyLib.getAdditionalBlocksConfig(cclContract);

        //todo is this needed if we already pass `requiredConsistencyLevel` into `publishMessage`?
        require(requiredConsistencyLevel >= consistencyLevel);

        // wait for required blocks to elapse
        uint16 requiredDurationToElapse = requiredBlocksToWait *
            secondsPerBlock;
        require(block.timestamp >= timestamp + requiredDurationToElapse);

        // Ensure that the contract that emits the message is our trusted contract on the source chain
        // See the `setPeer` function for more context
        require(
            peers[emitterChainId] == bytes32(emitterAddress),
            "Incorrect peer/emitter from source chain"
        );

        // Now we have verified the VAA is valid, checked the emitter, and ensured it hasn't been processed before
        // We can process the payload
        // We know the payload contains an address and a uint256 amount and we can start parsing from the beginning
        uint256 offset = 0;
        address to;
        uint256 amount;

        // `asAddressMem` and `asUint256Mem` will validate the offsets internally via the `checkBound` function
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
        address customConsistencyAddress,
        address ownerAddress,
        uint8 requiredConsistencyLevel,
        uint16 requiredBlocksToWait,
        uint16 _secondsPerBlock
    ) external onlyOwner {
        cclContract = customConsistencyAddress;
        owner = ownerAddress;
        CustomConsistencyLib.setAdditionalBlocksConfig(
            cclContract,
            requiredConsistencyLevel,
            requiredBlocksToWait
        );
        secondsPerBlock = _secondsPerBlock;
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
