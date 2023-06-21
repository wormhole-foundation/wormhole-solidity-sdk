# Wormhole Relayer Solidity SDK

The purpose of this SDK is to provide helpers to take your existing single-chain solidity application cross-chain

### Installation

**Foundry and Forge**
```bash
forge install wormhole-foundation/wormhole-relayer-solidity-sdk
```

### Example Usage

[HelloWormhole - Simple cross-chain message sending application](https://github.com/JoeHowarth/hello-wormhole)

[HelloToken - Simple cross-chain token sending application](https://github.com/JoeHowarth/hello-tokens)

### SDK Summary

- Includes interfaces to interact with contracts in the Wormhole ecosystem (src/interfaces)
- Includes the base class ‘Base’ with helpers for common actions that will typically need to be done within ‘receiveWormholeMessages’:
    - `onlyWormholeRelayer()`: Checking that msg.sender is the wormhole relayer contract
    - `replayProtect(bytes32 deliveryHash)`: Checking that the current delivery has not already been processed (via the hash)
    
    Sometimes, Cross-chain applications may be set up such that there is one ‘spoke’ contract on every chain, which sends messages to the ‘hub’ contract. If so, we’d ideally only want to allow messages to be sent from these spoke contracts. Included are helpers for this:
    
    - `setRegisteredSender(uint16 sourceChain, bytes32 sourceAddress)`: Setting the specified sender for ‘sourceChain’ to be ‘sourceAddress’
    - `isRegisteredSender(uint16 sourceChain, bytes32 sourceAddress)` : Checking that the sender who requested the delivery is the registered address for that chain
    
    Look at test/Counter.t.sol for an example usage of Base
    
- Included are also the ‘TokenSender’ and ‘TokenReceiver’ base classes with helpers for smart contracts that wish to send and receive tokens using Wormhole’s TokenBridge. See ‘HelloToken’ for example usage.
- Included are helpers that help set up a local forge testing environment. See ‘HelloWormhole’ for example usage.
