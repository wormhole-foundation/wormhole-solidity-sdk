# Solidity Function Selectors and the Dispatcher (+ Integrator Library) Pattern

## The Problem

### Basics

The Ethereum Virtual Machine has no concept of functions. Invoking a contract simply means sending calldata, i.e. an array of bytes, to the contract's address. It is up to the implementation of the contract to interpret this raw calldata.

Functions are a feature introduced by Solidity. Solidity encodes function calls using the first 4 bytes of the keccak256 hash of a [function's signature called its selector](https://docs.soliditylang.org/en/latest/abi-spec.html#function-selector). This selector is placed at the beginning of the calldata [followed by the 32 byte aligned encoding of the function's arguments](https://docs.soliditylang.org/en/latest/abi-spec.html#argument-encoding). When compiling a contract, `solc` generates dispatching code that maps the selector to its function's implementation.

### Drawbacks

This approach has two major drawbacks:
* It establishes a 1:1 relationship between transactions and contract function calls, giving rise to all sort of composability headaches.
* It is rather wasteful in terms of calldata usage, given that even small datatypes like bools use an entire 32 byte word. This negatively impacts transaction costs, particularly on L2s.

### Solc

On top of that, the way `solc` implements function selector dispatching introduces a lot of additional waste:

An optimal solution would use an `O(1)` approach, like e.g. [perfect hashing](https://en.wikipedia.org/wiki/Perfect_hash_function) or [bit masking](https://en.wikipedia.org/wiki/Mask_(computing)).

Sadly, the best that `solc` has to offer is binary search when using its legacy pipeline (when defining more than four externally callable functions).

Worse, its `via_ir` pipeline, which, due to its many attractive features such as smaller bytecode and automatic handling of "stack-too-deep" issues, is the generally preferred way of compiling Solidity contracts, currently always produces an `O(n)` `if-elif` cascade of selector comparisons in ascending order, independent of the number of externally callable functions defined in the contract.

One `elif` branch of this cascade looks like this in assembly (with the passed selector being on top of the stack):
```
DUP1
PUSH4
<4 byte function selector>
EQ
PUSH2
<2 byte function implementation offset>
JUMPI
```

This gives a total gas cost per branch not taken of 3 (DUP) + 3 (PUSH4) + 3 (EQ) + 3 (PUSH2) + 10 (JUMPI) = 22 gas.

### Example

An ERC20 token that implements nothing but the [ERC20 standard](https://eips.ethereum.org/EIPS/eip-20) and the [ERC2612 permit extension](https://eips.ethereum.org/EIPS/eip-2612) will have at least this list of functions:
```
Selector │ Signature
─────────┼───────────
06fdde03 │ name()
095ea7b3 │ approve(address,uint256)
18160ddd │ totalSupply()
23b872dd │ transferFrom(address,address,uint256)
313ce567 │ decimals()
3644e515 │ DOMAIN_SEPARATOR()
70a08231 │ balanceOf(address)
7ecebe00 │ nonces(address)
95d89b41 │ symbol()
a9059cbb │ transfer(address,uint256)
d505accf │ permit(address,address,uint256,uint256,uint8,bytes32,bytes32)
dd62ed3e │ allowance(address,address)
```

This means that, when compiling this token contract with `solc` and `via_ir`, querying the allowance takes 11 function skips for a total of 220 gas. This is more than the 100+100=200 gas of the required `STATICCALL` and `SLOAD` combined (assuming that the allowance storage slot will be touched again later and can hence be considered warm). These costs quickly add up.

### Further Limitations

Additionally, there's no way to override this default ordering. So even if a developer knows which functions of their contract will be called most frequently, there's no pragma or any other way for them to express this knowledge. All they can do is try out different function names until they find one that happens to have a low selector.

`solc` doesn't even group functions based on whether they are `payable` or not and the EVM itself lacks the ability to introspect, whether one is within the context of a `STATICCALL` to quickly narrow down possible candidates either.

## The Solution — As Always

In line with our [creeds](https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/README.md#philosophycreeds) and as the saying goes: If you want something done right, you gotta do it yourself, we tackle this problem by coming up with our own solution.

## A Naive Approach

Instead of relying on Solidity's dispatching mechanism, one could make all `public`/`external` functions `internal` instead and just implement one's own dispatching logic in the `fallback` function.

The glaring problem with this approach is that the `fallback` function is invoked at the very end of Solidity's dispatching cascade, therefore one has to ensure that the contract's ABI is effectively empty.

This is terrible for many reasons:
* *precludes most code reuse* - Even if the contract itself is written to adhere to a "no externally callable functions" rule, very few base utility classes will satisfy this constraint.
* *no backwards compatibility* - It's not possible to use this approach for upgrading an existing contract whose ABI can only be expanded, but not shrunk.
* *custom encoding tradeoff* - One has to choose:
  * Whether to stick with Solidity's function encoding scheme, thus incurring the drawbacks listed at the beginning, but with the upshot of being able to provide integrators with a normal `interface` definition of one's contract.
  * Or to use a custom encoding scheme, precluding the use of a normal `interface` definition and thus forcing all integrators to understand and support said custom encoding.
* *no Etherscan support* - Even if the contract adheres to Solidity's default function encoding convention, default verification on Etherscan will not provide the handy "Read Contract" and "Write Contract" tabs because its default ABI will not reflect the ABI of its associated interface.

## RawDispatcher

The abstract [RawDispatcher](https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/src/RawDispatcher.sol) contract/pattern eliminates all these drawbacks.

The basic idea is to introduce a dispatch function with a very low selector, which virually guarantees that it will come first in `solc`'s `via_ir` dispatching logic. This way, the contract can maintain its normal ABI but optionally allow integrators, both on-chain and off-chain, to opt into the more efficient custom encoding, which allows for smaller calldata, lower dispatching gas cost, and multicall support.

### Contract

The RawDispatcher contract is so short that we can reproduce it here in full:
```
abstract contract RawDispatcher {
  function exec768() external payable returns (bytes memory) { return _exec(msg.data[4:]); }
  function get1959() external view    returns (bytes memory) { return  _get(msg.data[4:]); }

  function _exec(bytes calldata data) internal      virtual returns (bytes memory);
  function  _get(bytes calldata data) internal view virtual returns (bytes memory);
}
```

Instead of just a singular dispatch function, it provides a more natural split into:
* `exec768()`, with a selector of `00000eb6` (fewer than 1 in a million functions have a lower selector), which is `payable` and handles _all_ state mutating operations (not just the `payable` ones!).
* `get1959()`, with a selector of `0008a112` (about 1 in ten thousand functions have a lower selector), which is `view` and handles all static calls.

While the functions' signatures suggest that they don't take any arguments, their implementations show that they operate on the calldata directly, without incurring the Solidity encoding overhead of `bytes calldata`, which would use one word to store the offset (always `0x20` here) and another word to redundantly store the length (which would always be `CALLDATASIZE - 4`), further cutting down on calldata size.

Contracts using this base class have to override the associated virtual functions and implement their corresponding dispatching logic there.

[BytesParsing](https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/src/libraries/BytesParsing.sol) can be used to parse the custom encoding in `bytes data`.

### Integrator Library

Of course, integrations have to actually make use of these custom dispatch functions to reap their benefits. To this end, contracts using the RawDispatcher pattern/base call should come with two additional "SDKs":
1. For on-chain integrations: A Solidity integrator `library` that fills the role of what is otherwise provided by an `interface`. That is, a set of encoding and decoding functions that mirror the contract's ABI but implement the custom call format of the contract decoding its returned `bytes` under the hood.
2. For off-chain integrations: A Typescript analog of the integrator library. The [layouting package](https://www.npmjs.com/package/binary-layout) offers an easy, declarative way to specify such custom encodings. It is also used in [the Wormhole Typescript SDK](https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/base/src/utils/layout.ts) to [define common types](https://github.com/wormhole-foundation/wormhole-sdk-ts/tree/main/core/definitions/src/layout-items) and various other layout examples can be found in [the protocols defined within the SDK itself](https://github.com/wormhole-foundation/wormhole-sdk-ts/tree/main/core/definitions/src/protocols) (e.g. [TokenBridge Messages](https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/definitions/src/protocols/tokenBridge/tokenBridgeLayout.ts), [WormholeRelayer Messages](https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/definitions/src/protocols/relayer/relayerLayout.ts), [CCTP messages](https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/definitions/src/protocols/circleBridge/circleBridgeLayout.ts)) or strewn throughout the various example repos e.g. [example-swap-layer](https://github.com/wormhole-foundation/example-swap-layer/blob/main/evm/ts-sdk/src/layout.ts) or [example-native-token-transfers](https://github.com/wormhole-foundation/example-native-token-transfers/tree/main/sdk/definitions/src/layouts).

### Limitations

* The gas efficiency of this solution strongly depends on the ascending `via_ir` selector sort ordering. If future versions of `solc`'s `via_ir` pipeline get around to implementing a more efficient dispatching mechanism, it will likely make this pattern obsolete at least from a gas efficiency standpoint.

* Since `exec768()` is `payable`, a manual `msg.value` check is necessary to enforce correct payability of all state mutable functions. Additionally, when implementing a native multicall pattern, additional function arguments are required to specify the distribution of `msg.value` between them.

# References

Great write-up on EVM function dispatchers: https://philogy.github.io/posts/selector-switches/
