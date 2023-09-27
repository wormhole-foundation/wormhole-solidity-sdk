
pragma solidity ^0.8.13;

import "./interfaces/IWormholeReceiver.sol";
import "./interfaces/IWormholeRelayer.sol";
import "./interfaces/IWormhole.sol";
import "./Utils.sol";

abstract contract Base {
    IWormholeRelayer public immutable wormholeRelayer;
    IWormhole public immutable wormhole;

    mapping(bytes32 => bool) public seenDeliveryVaaHashes;

    address registrationOwner;
    mapping(uint16 => bytes32) registeredSenders;

    constructor(address _wormholeRelayer, address _wormhole) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        wormhole = IWormhole(_wormhole);
        registrationOwner = msg.sender;
    }

    modifier onlyWormholeRelayer() {
        require(msg.sender == address(wormholeRelayer), "Msg.sender is not Wormhole Relayer");
        _;
    }

    modifier replayProtect(bytes32 deliveryHash) {
        require(!seenDeliveryVaaHashes[deliveryHash], "Message already processed");
        seenDeliveryVaaHashes[deliveryHash] = true;
        _;
    }

    modifier isRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) {
        require(registeredSenders[sourceChain] == sourceAddress, "Not registered sender");
        _;
    }

    /**
     * Sets the registered address for 'sourceChain' to 'sourceAddress'
     * So that for messages from 'sourceChain', only ones from 'sourceAddress' are valid
     *
     * Assumes only one sender per chain is valid
     * Sender is the address that called 'send' on the Wormhole Relayer contract on the source chain)
     */
    function setRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) public {
        require(msg.sender == registrationOwner, "Not allowed to set registered sender");
        registeredSenders[sourceChain] = sourceAddress;
    }
}
