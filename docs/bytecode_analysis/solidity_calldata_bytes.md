code:
```
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

contract ByteCode {

  function test() external payable returns (uint offset, uint length) {
    bytes calldata slice = msg.data[4:];
    assembly {
      offset := slice.offset
      length := slice.length
    }
  }
}
```

compiler:
```
solc_version = "0.8.23"
optimizer = true
via_ir = true
```

deployed bytecode assembly + stack trace:
```
  0x80
  dup1
  0x40
  mstore
  jumpi(tag_1, iszero(lt(calldatasize, 0x04)))
  0x00
  dup1
  revert
tag_1:
  0x00  [0x80, 0x00]
  swap1 [0x00, 0x80]
  dup2
  calldataload
  0xe0
  shr
  0xf8a8fd6d
  eq
  tag_3
  jumpi
  0x00
  dup1
  revert
tag_3:   [0x00, 0x80]
  add(not(0x03), calldatasize) [0x00, 0x80, calldatasize-4]
  dup3   [0x00, 0x80, calldatasize-4, 0x00]
  dup2   [0x00, 0x80, calldatasize-4, 0x00, calldatasize-4]
  slt    [0x00, 0x80, calldatasize-4, calldatasize-4 < 0]
  tag_7
  jumpi
  jumpi(tag_7, gt(0x04, calldatasize))
  0x40   [0x00, 0x80, calldatasize-4, 0x40]
  swap3  [0x40, 0x80, calldatasize-4, 0x00]
  pop
  0x04   [0x40, 0x80, calldatasize-4, 0x04]
  dup3   [0x40, 0x80, calldatasize-4, 0x04, 0x80]
  mstore [0x40, 0x80, calldatasize-4] -> store 4 at 0x80
  0x20   [0x40, 0x80, calldatasize-4, 0x20]
  dup3   [0x40, 0x80, calldatasize-4, 0x20, 0x80]
  add    [0x40, 0x80, calldatasize-4, 0xA0]
  mstore [0x40, 0x80] -> store calldatasize-4 at 0xA0
  return -> return 64 bytes at 0x80
tag_7:
  dup3
  dup1
  revert
```

