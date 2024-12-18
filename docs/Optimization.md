# Compiler Optimization

List of ways to avoid short-comings of the current optimizer which lead to suboptimal byte code.

## for loop array length checking

```solidity
function iterate(uint[] memory myArray) {
  uint len = myArray.length;
  for (uint i; i < len; ++i) { /*...*/}
}
```
is more efficient than
```solidity
function iterate(uint[] memory myArray) {
  for (uint i; i < myArray.length; ++i) { /*...*/}
}
```
even if it is trivial for the optimizer to check that `myArray`'s length can't possibly change as part of the loop.

If `myArray` uses `calldata` instead of `memory`, both versions produce the same bytecode.

## prefer `< MAX + 1` over `<= MAX` for const comparison

Given that the EVM only supports `LT` and `GT` but not `LTE` or `GTE`, solc implements `x<=y` as `!(x>y)`. However, given a constant `MAX`, since solc resolves `MAX + 1` at compile time, `< MAX + 1` saves one `ISZERO` opcode.

## consider using `eagerAnd` and `eagerOr` over short-curcuiting `&&` and `||`

Short-circuiting `lhs && rhs` requires _at least_ the insertion of:

| OpCode/ByteCode | Size | Gas | Explanation                                                 |
| --------------- | :--: | :-: | ----------------------------------------------------------- |
| `DUP1`          |  1   |  3  | copy result of `lhs` which currently is on top of the stack |
| `PUSH2`         |  1   |  3  | push location for code to eval/load `rhs`                   |
| jump offset     |  2   |  0  | points to **second** `JUMPDST`                              |
| `JUMPI`         |  1   | 10  | if `lhs` is `true` eval `rhs` too, otherwise short-circuit  |
| `JUMPDST`       |  1   |  1  | proceed here with the result on top of the stack            |
| --------------- | ---- | --- | ----------------------------------------------------------- |
| `JUMPDST`       |  1   |  1  | code to eval/load `rhs` starts here                         |
| `POP`           |  1   |  3  | remove duplicated `true` from stack                        |
| --------------- | ---- | --- | ----------------------------------------------------------- |
| `PUSH2`         |  1   |  3  | push location to jump back to where we proceed              |
| jump offest     |  2   |  0  | points to **first** jump offset (after `JUMPI`)             |
| `JUMP`          |  1   |  8  | jump back after evaluating `rhs`                            |
| --------------- | ---- | --- | ----------------------------------------------------------- |
| Total           | 12   | 32  |                                                             |

So our code will always bloat by at least 12 bytes, and even if the short-circuiting triggers, we still pay for the `PUSH`, the `JUMPI`, and stepping over the subsequent `JUMPDST` for a total of 17 gas, when the alternative can be as cheap as a single `AND` for 1 byte and 3 gas (if we just check a boolean thats already on the stack).

This is particularly unnecessary when checking that a bunch of variables all have their expected values, and where short-circuiting would _at best_ make the failing path cheaper, while always introducing the gas overhead on our precious happy path.

The way to avoid this is using the `eagerAnd` and `eagerOr` utility functions:

```solidity
function eagerAnd(bool lhs, bool rhs) internal pure returns (bool ret) {
  assembly ("memory-safe") {
    ret := and(lhs, rhs)
  }
}
```

Thankfully, while solc is not smart enough to consider the cost/side-effects of evaluating the right hand side before deciding whether to implement short-circuiting or not, but simply _always_ short-circuits, it will at least inline `eagerAnd` and `eagerOr`.
