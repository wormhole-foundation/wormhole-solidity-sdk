# Introduction

As a general point, your testing environment should match your real world environment as much as possible. Therefore, fork testing is generally encouraged over running standalone tests, despite the RPC provider dependency and its associated headaches.

Besides fork testing, forge also offers [mockCall](https://book.getfoundry.sh/cheatcodes/mock-call), [mockCallRevert](https://book.getfoundry.sh/cheatcodes/mock-call-revert), and [mockFunction](https://book.getfoundry.sh/cheatcodes/mock-function) cheat-codes, which should typically be preferred over writing and deploying mock contracts due to their more explicit nature.

# Utils

All Solidity testing utilities can be found in src/testing.

## WormholeForkTest

**Purpose**

The `WormholeForkTest` contract serves as a base class for fork testing Wormhole (and CCTP) integrations. It provides utilities for setting up and managing multiple forks, taking control of each chain's CoreBridge and CCTP MessageTransmitter using the respective override libraries, and various other common tasks.

**Fork Handling**

The contract comes with built-in default RPC URLs for each chain, but these can be overridden by explicitly specifying a custom RPC URL when calling `setUpFork()`. By default, it forks against mainnet chains, but this can be changed by setting `isMainnet` to false in the constructor. The `selectFork(uint16)` function is used to switch between forks using the Wormhole chain id.

**Utilities**

- Provides addresses of all Wormhole and CCTP contracts and other useful constants
- Creates a TokenBridge attestation for a token on a given chain and automatically submits it on all other forks
- USDC minting through the `UsdcDealer` library
- Fetching and parsing of both Wormhole and CCTP messages from Forge logs
- Creating VAAs/Circle attestations for Wormhole/CCTP messages

## WormholeRelayerTest

The `WormholeRelayerTest` contract extends `WormholeForkTest`, by providing additional utils for testing WormholeRelayer integrations. Namely picking up and delivering of WormholeRelayer messages to their intended targets and checking the delivery result afterwards. See test/WormholeRelayer.t.sol for an example.

## WormholeOverride

**Purpose**

The `WormholeOverride` library allows taking control of the CoreBridge on a given chain by overriding the current guardian set with a newly generated one, which can then be used to sign published messages and thus create VAAs.

**Default Guardian Set**

By default, the new guardian set has the same size as the old one, again to match the forked network's setup as closely as possible and keep message sizes and gas costs accurate. Since this can bloat traces and make them harder to read due to the VAAs' sizes, overriding with a single guardian when debugging tests can be helpful. This can be achieved by setting the environment variable `DEFAULT_TO_DEVNET_GUARDIAN` to true.

Also by default, the addresses and private keys of the new guardians are deterministically derived using Forge's `makeAddrAndKey` utility with the strings `guardian<i = 1, ..., n>`, naturally giving rise to the same values across all forks that are being overridden.

**Log Parsing**

Besides signing messages / creating VAAs, `WormholeOverride` also provides convenient forge log parsing capabilities to ensure that the right number of messages with the correct content are emitted by the core bridge. Be sure to call `vm.recordLogs()` beforehand to capture emitted events so that they are available for parsing.

**Message Fee**

Integrators should ensure that their contracts work correctly in case of a non-zero Wormhole message fee. `WormholeOverride` provides `setMessageFee` for this purpose.

## CctpOverride

The `CctpOverride` library is somewhat similar to `WormholeOverride` in that it allows overriding Circle's attester in their CCTP [MessageTransmitter](https://github.com/circlefin/evm-cctp-contracts/blob/master/src/MessageTransmitter.sol) contract (which is comparable in its functionality to Wormhole's core bridge).

However, `CctpOverride`, rather than providing generic signing and log parsing functionality like `WormholeOverride`, is more specialized and only deals with signing and log-parsing `CctpTokenBurnMessage`s emitted through Circle's [TokenMessenger](https://github.com/circlefin/evm-cctp-contracts/blob/master/src/TokenMessenger.sol) contract (which is roughly comparable to Wormhole's token bridge).

## UsdcDealer

Forge's `deal` cheat code does not work for USDC. `UsdcDealer` is another override library that implements a `deal` function that allows minting of USDC.

## ERC20Mock

Copy of SolMate's ERC20 Mock token that uses the overrideable `IERC20` interface of this SDK to guarantee compatibility.

## LogUtils

A library to simplify filtering of logs captured in Forge tests via `vm.recordLogs()`. Used by `WormholeOverride`, `CctpOverride`, ...
