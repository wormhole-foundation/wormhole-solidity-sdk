# Proxy

An opinionated, minimalist, efficient implementation for contract upgradability.

Based on [ERC-1967](https://eips.ethereum.org/EIPS/eip-1967), but skips all features that aren't strictly necessary for the most basic upgradeability use case (such as beacon, rollback, and admin slots/functionality) so as to provide the slimmest (in terms of bytecode), most straight-forward (in terms of readability and usability), no-nonsense solution.

I'm using the term "logic contract" here because it is a lot clearer/unambiguous than the more generic "implementation", while the actual code uses implementation to stick with the established terms within the context.

## Usage in a Nutshell

See test/Proxy.t.sol for a straight-forward example.

### Implementation

1. Implement a (logic) contract that inherits from `ProxyBase`.
2. Implement a constructor to initalize all `immutable` variables of your contract.
3. Override `_proxyConstructor` as necessary to initialize all storage variables of your contract as necessary (and don't forget to manually check `msg.value` since the constructor of `Proxy` is `payable`!).
4. Implement a function with a name (and access restrictions!) of your choosing that calls `_upgradeTo` internally. Make `payable` and emit an event as necessary/desired.

### Deployment

1. Deploy the your logic contract via its constructor.
2. Deploy `Proxy` with the address of your logic contract and `bytes` as required by `_proxyConstructor`.
Alternatively to step 2. you can also deploy a standard `ERC1967Proxy` (or through an `ERC1967Proxy` factory), in which case you have to manually encode the call to `checkedUpgrade`.

### Upgrade

1. Override `_contractUpgrade` in your new version of the logic contract and implement all migration logic there.
2. Invoke the upgrade through your own upgrade function (step 4 in the Implementation section).

## Rationale

There are enough upgradability standards, patterns, and libraries out there to make anyone's head spin:
* [ERC-1967](https://eips.ethereum.org/EIPS/eip-1967)
* [UUPS ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)
* [Diamond pattern ERC-2535](https://eips.ethereum.org/EIPS/eip-2535)

And then there's a bunch of implementations in the various EVM SDK repos:
* [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)
* [solmate](https://github.com/transmissions11/solmate)
* [solady](https://github.com/Vectorized/solady)

And especially OZ, which is very commonly used, has a bunch of patterns on top of that, requiring a separate [upgradeable repo](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) with its `init` and `init_unchained` functions, it's `initializer` and `reinitializer` modifiers, etc. etc.

While these cover all conceivable use cases (and then some), their inherent complexity and sheer amount of code can easily make a reader's eyes glaze over.

The goal of this proxy solution is to provide a concise, light-weight, easily understandable solution for the most common upgradeability use case.

And thus [a new implementation](https://xkcd.com/927/) is born.

## Design

### ProxyBase

Besides stripping all non-essential code, `ProxyBase` is opinionated in two ways:
1. It separates the act of construction from the act of upgrading via two `internal` `virtual` methods called `_proxyConstructor` and `_contractUpgrade` respectively.
2. It provides an external function called `checkedUpgrade` to execute these two methods, while automatically handling access control by automatically keeping track of an initialized flag (for construction) and by restricting external calls to `checkedUpgrade` to the proxy contract alone.

Additionally, `checkedUpgrade` has a high function selector (starts with `0xf4`) which saves gas on every other external function call on the contract, since any function with a selector lower than the one that is being invoked results in a gas overhead of 22 gas andless than 5 % of functions will, on average, have a selector higher than `checkedUpgrade`'s.

### Proxy

`Proxy` also strips all non-essential code and is the intended pairing of `ProxyBase`, though the latter is compatible with any `ERC-1967` proxy implementation (and can therefore also be used with any proxy factories that might have already been deployed on-chain). The advantage of using `Proxy` over other proxy implementations is that one does not have to encode the full initialization function call signature in the calldata, but only has to pack the arguments for `_proxyConstructor` and pass them along with the address of the logic contract.

## Limitations

### No Rollback Functionality

Since the upgrade mechanism isn't baked into the proxy itself but relies on the logic contract, it is possible to brick a contract with an upgrade to a faulty implementation. Simply supplying an incorrect address will not work, since the upgrade mechanism relies on the `checkedUpgrade` function to exist on the new contract, but if the upgrade mechanism of the new implementation is broken, then there's no way to roll back an upgrade.

Mitigation: See "git gud" creed. When it comes to upgradability, the #1 directive is: Avoid one-way door errors.

### No Version Checking

If there are several version of a given contract and the upgrades are meant to be applied sequentially, depending on the migration code of the individual version, it's possible to break/brick a contract by accidentally skip one of the upgrades.

Mitigation: Upgrade all your contracts whenever you release a new version. If this isn't an exceedingly rare event in the first place, perhaps you should take up a different occupation like farming, or crash test dummy.

### Self-destruct

If you are using the SELFDESTRUCT opcode (formerly known as SUICIDE before Ethereum's [most pointless EIP](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-6.md) got adopted) in your contract and are deploying to a chain that hasn't implemented [EIP-6780](https://eips.ethereum.org/EIPS/eip-6780) yet, you should really know what you are doing lest you are prepared to go the way of Parity Multisig.

Mitigation: Always treat guns as if they are loaded, point them in a safe direction, and keep the finger off the trigger.