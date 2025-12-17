// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import {SafeERC20} from "wormhole-sdk/libraries/SafeERC20.sol";
import {IERC20} from "IERC20/IERC20.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {
    ITokenMessenger
} from "wormhole-sdk/interfaces/cctp/ITokenMessenger.sol";
import {
    IMessageTransmitter
} from "wormhole-sdk/interfaces/cctp/IMessageTransmitter.sol";
import {
    CctpMessageLib,
    CctpTokenBurnMessage
} from "wormhole-sdk/libraries/CctpMessages.sol";
import "wormhole-sdk/utils/UniversalAddress.sol";

contract ExampleCCTPIntegration {
    using SafeERC20 for IERC20;

    // A struct which is used inside the `peers` mapping
    struct ChainIdToDomain {
        // The contract address deployed for this Wormhole chain ID
        bytes32 peerAddress;
        // The CCTP domain that this Wormhole chain ID points to
        uint32 cctpDomain;
    }

    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/TokenMessenger.sol
    ITokenMessenger private immutable tokenMessenger;

    // Source code: https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/MessageTransmitter.sol
    IMessageTransmitter private immutable messageTransmitter;

    // List of wormhole chain IDs and their associated peer address and CCTP domain configuration
    // key: Wormhole chain ID => (peer address, CCTP domain)
    // This mapping is based on Wormhole chain ID mappings in src/constants/Chains.sol
    mapping(uint16 => ChainIdToDomain) public peers;

    // This map records the timestamp when the unlock is requested
    // Tokens are only unlocked after 24 hours before redemption
    // Only non-whitelisted users (see `whitelistedRecipients` below) are required to wait for 24 hours before receiving the funds
    // keccak256(message, attestation) -> unlock timestamp
    mapping(bytes32 => uint) public unlockTimestamps;

    // Map of whitelisted recipients that do not have to wait for 24 hours before redeeming their funds
    // Key: address => isWhitelisted
    mapping(address => bool) public whitelistedRecipients;

    // Owner of this contract
    address public owner;

    constructor(
        address tokenMessengerAddress,
        address messageTransmitterAddress,
        address ownerAddress
    ) {
        require(tokenMessengerAddress != address(0), "Invalid address");
        require(messageTransmitterAddress != address(0), "Invalid address");
        require(ownerAddress != address(0), "Invalid address");

        tokenMessenger = ITokenMessenger(tokenMessengerAddress);
        messageTransmitter = IMessageTransmitter(messageTransmitterAddress);
        owner = ownerAddress;
    }

    // Entry point in the source chain to start cross-chain transfers
    function initiateCrossChainTransfer(
        uint256 amount,
        uint16 destinationChainId, // this is Wormhole chain IDs
        bytes32 mintRecipient,
        address burnToken
    ) external {
        // read the `peers` mapping to get the peer address from the given wormhole chain ID
        ChainIdToDomain memory chainIdInfo = peers[destinationChainId];
        require(chainIdInfo.peerAddress != bytes32(0), "Invalid peer address!");

        // transfer the funds from user
        IERC20(burnToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(burnToken).forceApprove(address(tokenMessenger), amount);

        // validate the upper 12 bytes of the `mintRecipient` address is zero since we will be casting bytes32 into bytes20 in `redeemUnlockedFunds`
        // we perform this by using the `fromUniversalAddress` function to ensure it is a valid EVM address
        fromUniversalAddress(mintRecipient);

        // call the token Messenger contract with the `destinationDomain` set to CCTP domain
        tokenMessenger.depositForBurnWithCaller(
            amount,
            chainIdInfo.cctpDomain, // this is in CCTP domain type, see src/constants/CctpDomains.sol
            mintRecipient, // this is the recipient's address on the destination chain
            burnToken,
            chainIdInfo.peerAddress // we set `destinationCaller` to our peer address so only our contract in destination chain can unlock the messenges
        );
    }

    // Entry point in the destination chain to request funds to be unlocked
    // This entry point needs to be called before calling `redeemUnlockedFunds`
    function startUnlockFunds(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        // Compute the key from the message and attestation parameters
        bytes32 key = keccak256(abi.encodePacked(message, attestation));
        require(unlockTimestamps[key] == 0, "Unlock already requested!");

        // populate the map field to only allow funds to be unlocked after 24 hours
        unlockTimestamps[key] = block.timestamp + 1 days;
    }

    // Entry point in the destination chain to redeem the funds after the lock period has elapsed
    // If the mintRecipient is not whitelisted, `startUnlockFunds` should be called first to request funds to be unlocked
    function redeemUnlockedFunds(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        // The CctpMessageLib library implements a variety of helper functions to decode incoming messages
        // In this case we use the `decodeCctpTokenBurnMessageStructCd` function to decode the provided message into an CctpTokenBurnMessage
        CctpTokenBurnMessage memory burnMessage = CctpMessageLib
            .decodeCctpTokenBurnMessageStructCd(message);

        // See src/libraries/CctpMessages.sol:41~69 for the message formats of a CctpTokenBurnMessage
        bytes32 mintRecipient = burnMessage.body.mintRecipient;

        // The timelock for funds redemption is only enforced if the recipient is not whitelisted
        address finalRecipient = fromUniversalAddress(mintRecipient);
        bool isRecipientWhitelisted = whitelistedRecipients[finalRecipient];

        if (!isRecipientWhitelisted) {
            bytes32 key = keccak256(abi.encodePacked(message, attestation));

            uint unlockTimestamp = unlockTimestamps[key];

            // Ensure there is an entry in the unlockTimestamps mapping (i.e., users have request their funds to be unlocked)
            require(
                unlockTimestamp != 0,
                "Funds unlock is not requested, see `startUnlockFunds` entry point"
            );

            // Ensure the lock period has elapsed
            require(
                block.timestamp >= unlockTimestamp,
                "Timelock is not elapsed yet!"
            );
        }

        // Calling receiveMessage() in the `messageTransmitter` will finalize and transfer the funds to the `mintRecipient`
        // https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/TokenMessenger.sol#L337-L343
        // We don't need to check the `success` bool from this function because it can only ever return true or throws on error, see https://github.com/circlefin/evm-cctp-contracts/blob/4061786a5726bc05f99fcdb53b0985599f0dbaf7/src/MessageTransmitter.sol#L305
        messageTransmitter.receiveMessage(message, attestation);
    }

    // Owner updates the peer address for various chains
    // Owner configures an entry of Wormhole chain ID => (peer address, CCTP domain)
    function setPeer(
        uint16 chainId,
        bytes32 peerAddress,
        uint32 cctpDomain
    ) external onlyOwner {
        peers[chainId] = ChainIdToDomain(peerAddress, cctpDomain);
    }

    // Owner sets whitelisted recipients from various chains
    // Whitelisted recipients can redeem their funds without waiting for the 24 hour delay
    function setWhitelistedRecipients(
        address whitelistAddress,
        bool isWhitelisted
    ) external onlyOwner {
        whitelistedRecipients[whitelistAddress] = isWhitelisted;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
