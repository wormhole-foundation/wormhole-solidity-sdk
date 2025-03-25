# Legacy Directory

The legacy directory is a dumping ground for all files that are kept for backwards compatibility but that are not kept up to the standards of the rest of the SDK.

# WormholeCctp

The WormholeCctpTokenMessenger is a standalone implementation of [WormholeCircleIntegration](https://github.com/wormhole-foundation/wormhole-circle-integration/).

Its has two associated files:
1. WormholeCctpMessages (message encoding/decoding)
2. WormholeCctpSimulator (for forge testing)

WormholeCctp functionality was extracted during the [liquidity layer](https://github.com/wormhole-foundation/example-liquidity-layer/blob/main/evm/src/shared/WormholeCctpTokenMessenger.sol) development process when it was recognized that going through the circle integration contract was adding additional, unnecessary overhead (gas, deployment, registration).

It later got moved to the Solidity SDK and used for testing in the [swap layer](https://github.com/wormhole-foundation/example-swap-layer).

The implementation is now considered legacy because it's unlikely to see any future use and thus keeping it up to date is not worth the effort.

A proper overhaul, besides introducing common optimizations in the rest of the SDK, would also rework the message format. Currently, most of the information that's in the VAA is actually redundant and could simply be taken from the CctpBurnTokenMessage. The only 2 pieces of information that should actually go into the VAA to uniquely link it to its associated CCTP messages is the CCTP nonce and the sourceDomain. But changing the message format would break backwards compatibility, thus interfering with its only expected use case.
