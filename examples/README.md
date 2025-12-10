# Wormhole Solidity SDK Examples

## ⚠️ Disclaimer

**These contracts are for demonstration and educational purposes only. DO NOT use them in production environments without thorough auditing, testing, and proper security reviews.** These examples are intended to showcase the usage of the Wormhole Solidity SDK libraries and may not implement all necessary security measures, error handling, or gas optimizations required for production deployments.

## Overview

This repository contains example contracts that demonstrate how to integrate with the Wormhole cross-chain messaging protocol using the Wormhole Solidity SDK. Each example showcases different aspects of cross-chain communication, token transfers, and security patterns.

## Examples

### 1. [ExampleCustomTokenBridge.sol](ExampleCustomTokenBridge.sol)

A basic cross-chain token bridge implementation using Wormhole's core messaging system with finalized consistency levels.

**Key Features:**

- Cross-chain token transfers using VAA (Verifiable Action Approval) messages
- Finalized consistency level for maximum security
- Sequence-based replay protection
- Peer validation to ensure messages come from trusted contracts

**Libraries Demonstrated:**

- `SafeERC20` - Safe ERC20 token operations
- `CoreBridgeLib` - VAA decoding and verification
- `SequenceReplayProtectionLib` - Prevents duplicate message processing
- `BytesParsing` - Efficient payload parsing with unchecked variants

**Use Case:** Building a simple token bridge between two chains where you control both source and destination contracts.

---

### 2. [ExampleCustomConsistencyTokenBridge.sol](ExampleCustomConsistencyTokenBridge.sol)

An advanced token bridge that demonstrates Wormhole's custom consistency level feature, allowing contracts to define their own finality requirements.

**Key Features:**

- Custom consistency levels with configurable block delays
- Hash-based replay protection (suitable for non-finalized consistency)
- Dynamic configuration updates
- Additional security layer through custom finality definitions

**Libraries Demonstrated:**

- `CustomConsistencyLib` - Setting custom consistency levels and block waiting periods
- `HashReplayProtectionLib` - Hash-based replay protection for non-finalized messages
- `VaaLib` - Single-hash VAA computation
- `CoreBridgeLib` - VAA verification with calldata optimization

**Use Case:** When you need faster cross-chain transfers with custom finality requirements, or want to optimize for specific chain characteristics.

**Notes:**

- Uses `CONSISTENCY_LEVEL_CUSTOM` (203) to enable custom consistency
- May fallback to `ConsistencyLevelFinalized` if custom consistency is not properly configured
- Guardians read from the `cclContract` to determine when to start processing messages

---

### 3. [ExampleWTTBridgeIntegration.sol](ExampleWTTBridgeIntegration.sol)

Integration with Wormhole's native Token Bridge (WTT) for wrapped token transfers with custom payload handling and fee structures.

**Key Features:**

- ETH transfers with payload using Wormhole's Token Bridge
- Configurable inbound and outbound fees
- Whitelist system for fee exemptions
- Leverages Token Bridge's existing security for emitter validation

**Libraries Demonstrated:**

- `TokenBridgeMessageLib` - Parsing Token Bridge transfer messages
- `PercentageLib` - Fee percentage calculations with mantissa and fractional digits
- `BytesParsing` - Payload extraction and validation
- `DecimalNormalization` - Handling token decimal conversions

**Use Case:** Building applications that need to transfer tokens cross-chain with custom logic, fees, or additional data (e.g., DEX aggregators, payment systems).

---

### 4. [ExampleCCTPIntegration.sol](ExampleCCTPIntegration.sol)

Integration with Circle's Cross-Chain Transfer Protocol (CCTP) for native USDC transfers across chains.

**Key Features:**

- Native USDC cross-chain transfers
- 24-hour timelock for fund redemption
- Whitelist system to bypass timelock for trusted recipients

**Libraries Demonstrated:**

- `CctpMessageLib` - Decoding CCTP burn messages
- `SafeERC20` - Token approvals and transfers
- Integration with Circle's `ITokenMessenger` and `IMessageTransmitter`

**Use Case:** Transferring USDC between chains with additional security measures like timelocks, or building payment systems that require native USDC.

## SDK Libraries Reference

### Core Libraries

- **CoreBridgeLib** - VAA parsing and verification
- **BytesParsing** - Efficient payload parsing with checked and unchecked variants

### Replay Protection

- **SequenceReplayProtectionLib** - For finalized messages
- **HashReplayProtectionLib** - For non-finalized messages

### Specialized Libraries

- **CustomConsistencyLib** - Custom finality configuration
- **TokenBridgeMessageLib** - Token Bridge message parsing
- **CctpMessageLib** - CCTP message parsing
- **PercentageLib** - Fee calculations
- **VaaLib** - VAA hash computations

## Security Considerations

- Always validate emitter addresses using the peer mapping
- Implement appropriate replay protection for your consistency level
- Use finalized consistency levels for high-value transfers
- Audit custom payload parsing logic carefully
- Consider implementing additional access controls and circuit breakers
- Test edge cases thoroughly (failed transfers, malformed payloads, etc.)

## Resources

- [Wormhole Documentation](https://wormhole.com/docs/)
- [Wormhole GitHub](https://github.com/wormhole-foundation/wormhole)
- [Circle CCTP Documentation](https://developers.circle.com/stablecoins/docs/cctp-getting-started)
- [Consistency Levels Guide](https://wormhole.com/docs/products/reference/consistency-levels/)

---

**Remember:** These are educational examples. Production deployments require comprehensive security audits, extensive testing, and proper risk management strategies.
