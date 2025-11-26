// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {IERC20} from "IERC20/IERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {CoreBridgeLib} from "wormhole-sdk/libraries/CoreBridge.sol";
import {SequenceReplayProtectionLib} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

contract ExampleCustomTokenBridge {
    using SafeERC20 for IERC20;
    using BytesParsing for bytes;

    // See https://wormhole.com/docs/products/reference/consistency-levels/
    uint8 public constant consistencyLevel = 1; // finalized

    // Wormhole token bridge contract
    // Source code: https://github.com/wormhole-foundation/wormhole/blob/main/ethereum/contracts/Implementation.sol
    ICoreBridge public coreBridge;

    // The token address
    IERC20 public token;

    /// Owner of this contract
    address public owner;

    mapping(uint16 => bytes32) public peers;

    constructor(
        address coreBridgeAddress,
        address tokenAddress,
        address ownerAddress
    ) {
        coreBridge = ICoreBridge(coreBridgeAddress);
        token = IERC20(tokenAddress);
        owner = ownerAddress;
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

        coreBridge.publishMessage{value: wormholeFee}(
            0,
            payload,
            consistencyLevel
        );
    }

    // Entry point when we receive a cross-chain message from other chains
    function receiveToken(bytes memory vaa) external {
        // First we need to parse and verify the VAA
        // CoreBridgeLib.decodeAndVerifyVaaMem will do this for us
        // It is functionalty equivalent to calling parseAndVerifyVM on the core bridge contract
        (
            ,
            ,
            //timestamp is ignored
            //nonce is ignored
            uint16 emitterChainId,
            bytes32 emitterAddress,
            uint64 sequence, //consistencyLevel is ignored as we know the peers are using finalized
            ,
            bytes memory payload
        ) = CoreBridgeLib.decodeAndVerifyVaaMem(address(coreBridge), vaa);

        // Ensure that the contract that emits the message is our trusted contract on the source chain
        // See the `setPeer` function for more context
        require(
            peers[emitterChainId] == bytes32(emitterAddress),
            "Incorrect peer/emitter from source chain"
        );

        // Perform replay protection
        // We can safely use sequence-based replay protection here because we are using the finalized consistency level
        // NOTE: DO NOT use sequence-based replay protection for VAAs with non-finalized consistency levels!
        // This function will revert if the VAA has already been processed/consumed
        SequenceReplayProtectionLib.replayProtect(
            emitterChainId,
            emitterAddress,
            sequence
        );

        // Now we have verified the VAA is valid, checked the emitter, and ensured it hasn't been processed before
        // We can process the payload
        // We know the payload contains an address and a uint256 amount and we can start parsing from the beginning
        uint256 offset = 0;
        address to;
        uint256 amount;

        // We use the unchecked variant here, but it's important we check the offset via `checkLength` once we're done parsing to ensure we consumed the entire payload
        (to, offset) = payload.asAddressMemUnchecked(offset);
        (amount, offset) = payload.asUint256MemUnchecked(offset);

        // This check is critical when using unchecked parsing (`asAddressMemUnchecked` & `asUint256MemUnchecked`) because `checkLength` will ensure that the encoded length and expected length are the same
        // Also, it's more gas efficient if we're performing multiple parsing operations in succession
        BytesParsing.checkLength(payload.length, offset);

        // Finally we can transfer the tokens to the recipient
        // Again, this is functionally equivalent to the OZ SafeERC20 library
        // Here we assume the contract has enough balance to cover the transfer, but a real implementation
        // would likely have more complex logic to handle this
        token.safeTransfer(to, amount);
    }

    // Owner updates the peer address so we are only accepting messages emitted by trusted contracts from other chains
    // This is important to ensure we are not listening to a faulty contract that tries to mint valuable tokens on the destination chain
    // If you come from web2 security, think Insecure Direct Object Reference (IDOR) attack
    // See https://wormhole.com/docs/products/messaging/guides/core-contracts/#validating-the-emitter
    function setPeer(uint16 chainId, bytes32 peerAddress) external {
        require(
            msg.sender == owner,
            "Only owner can set peers from other chains"
        );
        peers[chainId] = peerAddress;
    }
}
