# Wormhole Solidity SDK

The purpose of this SDK is to make on-chain integrations with Wormhole on EVM compatible chains as smooth as possible by providing all necessary Solidity interfaces along with useful libraries and tools for testing.

For off-chain code, please refer to the [TypeScript SDK](https://github.com/wormhole-foundation/wormhole-sdk-ts) and in particular the [EVM platform implementation](https://github.com/wormhole-foundation/wormhole-sdk-ts/tree/main/platforms/evm).

This SDK was originally created for integrations with the WormholeRelayer and then expanded to cover all integration.

## Releases

> License Reminder
>
> The code is provided on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
>
> So make sure you check / audit any code you use before deploying to mainnet.

The `main` branch is considered the nightly version of the SDK. Stick to tagged releases for a stable experience.

**Note: The SDK is currently on its way to a version 1.0 . Proceed with extra caution until then.**

## Installation

**Foundry and Forge**

```bash
forge install wormhole-foundation/wormhole-solidity-sdk@v0.1.0
```

**EVM Version**

One hazard of developing EVM contracts in a cross-chain environment is that different chains have varying levels of "EVM-equivalence". This means you have to ensure that all chains that you are planning to deploy to support all EIPs/opcodes that you rely on.

For example, if you are using a solc version newer than `0.8.19` and are planning to deploy to a chain that does not support [PUSH0 opcode](https://eips.ethereum.org/EIPS/eip-3855) (introduced as part of the Shanghai hardfork), you should set `evm_version = "paris"` in your `foundry.toml`, since the default EVM version of solc was advanced from Paris to Shanghai as part of solc's `0.8.20` release.

**Testing**

It is strongly recommended that you run the forge test suite of this SDK with your own compiler version to catch potential errors that stem from differences in compiler versions early. Yes, strictly speaking the Solidity version pragma should prevent these issues, but better to be safe than sorry, especially given that some components make extensive use of inline assembly.

**IERC20 and SafeERC20 Remapping**

This SDK comes with its own IERC20 interface and SafeERC20 implementation. Given that projects tend to combine different SDKs, there's often this annoying issue of clashes of IERC20 interfaces, even though they are effectively the same. We handle this issue by importing `IERC20/IERC20.sol` which allows remapping the `IERC20/` prefix to whatever directory contains `IERC20.sol` in your project, thus providing an override mechanism that should allow dealing with this problem seamlessly until forge allows remapping of individual files. The same approach is used for SafeERC20.

## Components

For additional documentation of components, see the docs directory.

## Philosophy/Creeds

In This House We Believe:
* clarity breeds security
* Do NOT trust in the Lord (i.e. the community, auditors, fellow devs, FOSS, ...) with any of your heart (i.e. with your or your users' security), but lean _hard_ on your own understanding.
* _Nothing_ is considered safe unless you have _personally_ verified it as such.
* git gud
* shut up and suffer

## Notable Solidity Repos

* [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)
* [Solmate](https://github.com/transmissions11/solmate) / [Solady](https://github.com/Vectorized/solady)
* [Uniswap Permit2](https://github.com/Uniswap/permit2) + [explanation](https://github.com/dragonfly-xyz/useful-solidity-patterns/tree/main/patterns/permit2)
