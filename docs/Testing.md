# Testing

As a general point, your testing environment should match your real world environment as much as possible. Therefore, fork testing is generally encouraged over running standalone tests, despite the RPC provider dependency and its associated headaches.

Besides fork testing, forge also offers [mockCall](https://book.getfoundry.sh/cheatcodes/mock-call), [mockCallRevert](https://book.getfoundry.sh/cheatcodes/mock-call-revert), and [mockFunction](https://book.getfoundry.sh/cheatcodes/mock-function) cheat-codes, which should typically be preferred over writing and deploying mock contracts due to their more explicit nature.

## Utils

All Solidity testing utilities can be found in src/testing.

### WormholeOverride

**Purpose**

The `WormholeOverride` library is the main way to fork test integrations. It allows overriding the current guardian set of the core bridge with a newly generated one which can then be used to sign messages and thus create VAAs.

**Default Guardian Set**

By default the new guardian set has the same size as the old one, again to match the forked network's setup as closely as possible and keep message sizes and gas costs accurate. Since this can bloat traces and make them harder to read due to the VAAs' sizes, overriding with a single guardian when debugging tests can be helpful. This can be achieved by setting the environment variable `DEFAULT_TO_DEVNET_GUARDIAN` to true.

**Log Parsing**

Besides signing messages / creating VAAs, `WormholeOverride` also provides convenient forge log parsing capabilities to ensure that the right number of messages with the correct content are emitted by the core bridge. Be sure to call `vm.recordLogs();` beforehand to capture emitted events so that they are available for parsing.

**Message Fee**

Integrators should ensure that their contracts work correctly in case of a non-zero Wormhole message fee. `WormholeOverride` provides `setMessageFee` for this purpose.


### CctpOverride

The `CctpOverride` library, is somewhat similar to `WormholeOverride` in that it allows overriding Circle's attester in their CCTP [MessageTransmitter](https://github.com/circlefin/evm-cctp-contracts/blob/master/src/MessageTransmitter.sol) contract (which is comparable in its functionality to Wormhole's core bridge).

However, `CctpOverride`, rather than providing generic signing and log parsing functionality like `WormholeOverride`, is more specialized and only deals with signing and log-parsing `CctpTokenBurnMessage`s emitted through Circle's [TokenMessenger](https://github.com/circlefin/evm-cctp-contracts/blob/master/src/TokenMessenger.sol) contract (which is roughly comparable to Wormhole's token bridge).


### WormholeCctpSimulator

The `WormholeCctpSimulator` contract can be deployed to simulate a virtual `WormholeCctpTokenMessenger` instance on some made-up foreign chain. It uses `0xDDDDDDDD` as the circle domain of that chain, and also simulates virtual instances of Circle's TokenMessenger and USDC contract, which are correctly registered with the instances on the forked chain. The foreign Wormhole chain id and the address of the foregin sender can be set during construction. Uses `WormholeOverride` and `CctpOverride`.

### UsdcDealer

Forge's `deal` cheat code does not work for USDC. `UsdcDealer` is another override library that implements a `deal` function that allows minting of USDC.

### CctpMessages

Library to parse CCTP messages composed/emitted by Circle's `TokenMessenger` and `MessageTransmitter` contracts. Used in `CctpOverride` and `WormholeCctpSimulator`.

### ERC20Mock

Copy of SolMate's ERC20 Mock token that uses the overrideable `IERC20` interface of this SDK to guarantee compatibility.

### LogUtils

A library to simplify filtering of logs captured in Forge tests. Used by `WormholeOverride`, `CctpOverride`, ...
