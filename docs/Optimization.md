# Compiler Optimization

List of ways to avoid short-comings of the current optimizer which lead to suboptimal byte code

## for loop array length checking

```
function iterate(uint[] memory myArray) {
  uint len = myArray.length;
  for (uint i; i < len; ++i) { /*...*/}
}
```
is more efficient than
```
function iterate(uint[] memory myArray) {
  for (uint i; i < myArray.length; ++i) { /*...*/}
}
```
even if it is trivial for the optimizer to check that `myArray`'s length can't possibly change as part of the loop.

If `myArray` uses `calldata` instead of `memory`, both versions produce the same bytecode.

## prefer `< MAX + 1` over `<= MAX` for const comparison

Given that the EVM only supports `LT` and `GT` but not `LTE` or `GTE`, solc implements `x<=y` as `!(x>y)`. However, given a constant `MAX`, since solc resolves `MAX + 1` at compile time, `< MAX + 1` saves one `ISZERO` opcode.