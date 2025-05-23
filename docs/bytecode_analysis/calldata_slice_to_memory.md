code:
```
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

contract ByteCode {
  function foo(
    bytes calldata encoded,
    uint offset,
    uint length
  ) public payable returns (bytes memory) { unchecked {
    return encoded[offset:offset + length];
  }}
}
```

compiler:
```
solc_version = "0.8.23"
optimizer = true
via_ir = true
```

run with eg:
`forge debug --debug src/ByteCode.sol --sig "foo(bytes,uint256,uint256)" "00010203040506" 2 3`

deployed bytecode assembly + stack trace:
```
/* \"src/ByteCode.sol\":65:268  contract ByteCode {... */
  0x80
  0x04
  calldatasize [0x80, 4, calldatasize]
  lt
  iszero       [0x80, calldataTooShortForSelector]
  tag_1        [0x80, calldataTooShortForSelector, tag_1]
  jumpi        /*revert if calldata too short*/
  0x00
  dup1
  revert
tag_1:
  0x00         [0x80, 0]
  dup1         [0x80, 0, 0]
  calldataload [0x80, 0, cd[0:32]]
  0xe0         [0x80, 0, cd[0:32], 0xe0 (=224=256-32)]
  shr          [0x80, 0, cd[0:4]]
  0xb422824d   [0x80, 0, cd[0:4], foo.selector]
  eq
  tag_3        [0x80, 0, isFooSelector, tag_3]
  jumpi        /*revert if function selector is not foo*/
  0x00
  dup1
  revert
tag_3:
  calldatasize
  0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc /*-4*/
  add          /*why not sub 4 instead of add -4?!? we even already know that calldatasize >= 4 (not that it matters)!*/
  0x60         /* 3*32: encoded, offset, size */
  slt          /*signed less than */
  tag_9
  jumpi        /*revert if calldata too short for foo (must be at least 3 words)*/
  calldataload(0x04) [0x80, 0, cd[4:36] (=encodedPO)]
  swap1        [0x80, encodedPO, 0]
  0xffffffffffffffff [0x80, encodedPO, 0, 0xffffffffffffffff (=2^64-1)]
  swap1        [0x80, encodedPO, 2^64-1, 0]
  dup2         [0x80, encodedPO, 2^64-1, 0, 2^64-1]
  dup4         [0x80, encodedPO, 2^64-1, 0, 2^64-1, encodedPO]
  gt
  tag_9
  jumpi        /*revert if encodedPO points to something beyond 2^64-1 in calldata*/
  calldatasize [0x80, encodedPO, 2^64-1, 0, calldatasize]
  0x23         [0x80, encodedPO, 2^64-1, 0, calldatasize, 0x23 (=35)]
  dup5         [0x80, encodedPO, 2^64-1, 0, calldatasize, 35, encodedPO]
  add          [0x80, encodedPO, 2^64-1, 0, calldatasize, encodedPO+35]
  slt
  iszero
  tag_9        /*revert if encodedPO points outside of calldata (I think? not sure why 35 and not 36=32+4)*/
  jumpi
  dup3         [0x80, encodedPO, 2^64-1, 0, encodedPO]
  0x04         [0x80, encodedPO, 2^64-1, 0, encodedPO, 4]
  add          [0x80, encodedPO, 2^64-1, 0, encodedPO+4]
  calldataload [0x80, encodedPO, 2^64-1, 0, encode.length]
  dup3         [0x80, encodedPO, 2^64-1, 0, encode.length, 2^64-1]
  dup2         [0x80, encodedPO, 2^64-1, 0, encode.length, 2^64-1, encode.length]
  gt           
  tag_11
  jumpi        /*revert if encode.length is larger than 2^64-1*/
  0x24         [0x80, encodedPO, 2^64-1, 0, encode.length, 0x24 (=36)]
  swap4        [0x80, 36, 2^64-1, 0, encode.length, encodedPO]
  calldatasize [0x80, 36, 2^64-1, 0, encode.length, encodedPO, calldatasize]
  dup6         [0x80, 36, 2^64-1, 0, encode.length, encodedPO, calldatasize, 36]
  dup4         [0x80, 36, 2^64-1, 0, encode.length, encodedPO, calldatasize, 36, encode.length]
  dup4         [0x80, 36, 2^64-1, 0, encode.length, encodedPO, calldatasize, 36, encode.length, encodedPO]
  add
  add          [0x80, 36, 2^64-1, 0, encode.length, encodedPO, calldatasize, 36+encode.length+encodedPO]
  gt           [0x80, 36, 2^64-1, 0, encode.length, encodedPO, encodedExceedsCalldata]
  tag_13
  jumpi        /*revert if encodedPO+encode.length exceeds calldata*/
  dup5         [0x80, 36, 2^64-1, 0, encode.length, encodedPO, 36]
  calldataload [0x80, 36, 2^64-1, 0, encode.length, encodedPO, offset]
  swap1        [0x80, 36, 2^64-1, 0, encode.length, offset, encodedPO]
  0x44         
  calldataload [0x80, 36, 2^64-1, 0, encode.length, offset, encodedPO, length]
  dup3         [0x80, 36, 2^64-1, 0, encode.length, offset, encodedPO, length, offset]
  add          [0x80, 36, 2^64-1, 0, encode.length, offset, encodedPO, length+offset]
  swap3        [0x80, 36, 2^64-1, 0, length+offset, offset, encodedPO, encode.length]
  dup4         [0x80, 36, 2^64-1, 0, length+offset, offset, encodedPO, encode.length, length+offset]
  dup4         [0x80, 36, 2^64-1, 0, length+offset, offset, encodedPO, encode.length, length+offset, offset]
  gt
  tag_23
  jumpi        /*pointless check that reverts if offset > length+offset */
  dup4         [0x80, 36, 2^64-1, 0, length+offset, offset, encodedPO, encode.length, length+offset]
  gt
  tag_17
  jumpi        /*revert if length+offset > encode.length*/
  dup2         [0x80, 36, 2^64-1, 0, length+offset, offset, encodedPO, offset]
  add          [0x80, 36, 2^64-1, 0, length+offset, offset, encodedPO+offset]
  swap2        [0x80, 36, 2^64-1, 0, encodedPO+offset, offset, length+offset]
  sub          [0x80, 36, 2^64-1, 0, encodedPO+offset, length]
  dup4         [0x80, 36, 2^64-1, 0, encodedPO+offset, length, 2^64-1]
  dup2         [0x80, 36, 2^64-1, 0, encodedPO+offset, length, 2^64-1, length]
  gt
  tag_19
  jumpi        /*revert if length > 2^64-1*/
  2^256-31     [0x80, 36, 2^64-1, 0, encodedPO+offset, length, 2^256-31]
  swap5        [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36]
  0x1f         [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, 31]
  dup3         [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, 31, length]
  add          [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, 31+length]
  dup7         [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, 31+length, 2^256-31]
  and          [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, (31+length)lower5bits=0]
  0x3f         [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, (31+length)lower5bits=0, 63]
  add          [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, ((31+length)lower5bits=0)+63]
  dup7         [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, ((31+length)lower5bits=0)+63, 2^256-31]
  and          [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, (((31+length)lower5bits=0)+63)lower5bits=0]
  dup8         [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, (((31+length)lower5bits=0)+63)lower5bits=0, 0x80]
  add          [0x80, 2^256-31, 2^64-1, 0, encodedPO+offset, length, 36, (((31+length)lower5bits=0)+63)lower5bits=0+0x80]
  swap5        [0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 2^64-1]
  dup6         [0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 2^64-1, (((31+length)lower5bits=0)+63)lower5bits=0+0x80]
  gt           /*idiotic gt*/[0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 0]
  dup8         [0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 0, 0x80]
  dup7         [0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 0, 0x80, (((31+length)lower5bits=0)+63)lower5bits=0+0x80]
  lt           /*idiotic lt - known at compile time*/ [0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 0, 0]
  or           [0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 1]
  tag_21
  jumpi        /*revert if applicable with Panic(0x41) = oversized allocation*/
  0x40         [0x80, 2^256-31, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 0, encodedPO+offset, length, 36, 64]
  swap5        [0x80, 2^256-31, 64, 0, encodedPO+offset, length, 36, (((31+length)lower5bits=0)+63)lower5bits=0+0x80]
  0x40         [0x80, 2^256-31, 64, 0, encodedPO+offset, length, 36, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 64]
  mstore       /*write to free memory ptr*/ [0x80, 2^256-31, 64, 0, encodedPO+offset, length, 36, (((31+length)lower5bits=0)+63)lower5bits=0+0x80, 64]
  dup2         [0x80, 2^256-31, 64, 0, encodedPO+offset, length, 36, length]
  dup8         [0x80, 2^256-31, 64, 0, encodedPO+offset, length, 36, length, 0x80]
  mstore       /*store length at 0x80*/ [0x80, 2^256-31, 64, 0, encodedPO+offset, length, 36]
  0x20         [0x80, 2^256-31, 64, 0, encodedPO+offset, length, 36, 32]
  swap3        [0x80, 2^256-31, 64, 0, 32, length, 36, encodedPO+offset]
  calldatasize [0x80, 2^256-31, 64, 0, 32, length, 36, encodedPO+offset, calldatasize]
  dup3         [0x80, 2^256-31, 64, 0, 32, length, 36, encodedPO+offset, calldatasize, 36]
  dup5         [0x80, 2^256-31, 64, 0, 32, length, 36, encodedPO+offset, calldatasize, 36, length]
  dup4         [0x80, 2^256-31, 64, 0, 32, length, 36, encodedPO+offset, calldatasize, 36, length, encodedPO+offset]
  add          [0x80, 2^256-31, 64, 0, 32, length, 36, encodedPO+offset, calldatasize, 36, length+encodedPO+offset]
  add          [0x80, 2^256-31, 64, 0, 32, length, 36, encodedPO+offset, calldatasize, 36+length+encodedPO+offset]
  gt
  tag_23
  jumpi        /*revert if we read past calldata*/
  swap2        [0x80, 2^256-31, 64, 0, 32, encodedPO+offset, 36, length]
  dup1         [0x80, 2^256-31, 64, 0, 32, encodedPO+offset, 36, length, length]
  dup5         [0x80, 2^256-31, 64, 0, 32, encodedPO+offset, 36, length, length, 32]
  swap9        [32, 2^256-31, 64, 0, 32, encodedPO+offset, 36, length, length, 0x80]
  swap7        [32, 2^256-31, 0x80, 0, 32, encodedPO+offset, 36, length, length, 64]
  swap6        [32, 2^256-31, 0x80, 64, 32, encodedPO+offset, 36, length, length, 0]
  swap5        [32, 2^256-31, 0x80, 64, 0, encodedPO+offset, 36, length, length, 32]
  swap3        [32, 2^256-31, 0x80, 64, 0, encodedPO+offset, 32, length, length, 36]
  dup6         [32, 2^256-31, 0x80, 64, 0, encodedPO+offset, 32, length, length, 36, 0]
  swap5        [32, 2^256-31, 0x80, 64, 0, 0, 32, length, length, 36, encodedPO+offset]
  add          [32, 2^256-31, 0x80, 64, 0, 0, 32, length, length, 36+encodedPO+offset]
  dup4         [32, 2^256-31, 0x80, 64, 0, 0, 32, length, length, 36+encodedPO+offset, 32]
  dup9         [32, 2^256-31, 0x80, 64, 0, 0, 32, length, length, 36+encodedPO+offset, 32, 0x80]
  add          [32, 2^256-31, 0x80, 64, 0, 0, 32, length, length, 36+encodedPO+offset, 0xA0]
  calldatacopy /*actually copy slice*/ [32, 2^256-31, 0x80, 64, 0, 0, 32, length]
  dup6         [32, 2^256-31, 0x80, 64, 0, 0, 32, length, 0x80]
  add          [32, 2^256-31, 0x80, 64, 0, 0, 32, length+0x80]
  add          [32, 2^256-31, 0x80, 64, 0, 0, length+0xA0]
  mstore       /*rather pointless write of zeros after slice*/ [32, 2^256-31, 0x80, 64, 0]
  mload(0x40)  /*load free memory ptr*/ [32, 2^256-31, 0x80, 64, 0, freeMemPtr(the ugly expression from before)]
  swap5        [freeMemPtr, 2^256-31, 0x80, 64, 0, 32]
  dup6         [freeMemPtr, 2^256-31, 0x80, 64, 0, 32, freeMemPtr]
  swap4        [freeMemPtr, 2^256-31, freeMemPtr, 64, 0, 32, 0x80]
  dup2         [freeMemPtr, 2^256-31, freeMemPtr, 64, 0, 32, 0x80, 32]
  dup6         [freeMemPtr, 2^256-31, freeMemPtr, 64, 0, 32, 0x80, 32, freeMemPtr]
  mstore       [freeMemPtr, 2^256-31, freeMemPtr, 64, 0, 32, 0x80]
  dup1         [freeMemPtr, 2^256-31, freeMemPtr, 64, 0, 32, 0x80, 0x80]
  mload        [freeMemPtr, 2^256-31, freeMemPtr, 64, 0, 32, 0x80, length]
  swap4        [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64]
  dup5         [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, length]
  dup4         [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, length, 32]
  dup8         [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, length, 32, freeMemPtr]
  add          [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, length, 32+freeMemPtr]
  mstore       /*store length in next free memory word*/ [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64]
  dup4         [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, 0]
tag_25:
  dup6         [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, 0, length]
  dup2         [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, 0, length, 0]
  lt           /*insanely pointless 0<length check*/ [freeMemPtr, 2^256-31, freeMemPtr, length, 0, 32, 0x80, 64, 0, 1]
  tag_26
  jumpi        /*detour to tag_26 - stopping here and just looking at the rest in the debugger*/
  dup7
  0x40
  dup2
  dup11
  0x1f
  dup11
  dup11
  dup6
  dup3
  dup7
  add
  add
  mstore
  add
  and
  dup2
  add
  sub
  add
  swap1
  return
tag_26:
  dup3
  dup2
  add
  dup5
  add
  mload
  dup10
  dup3
  add
  dup4
  add
  mstore
  dup9
  swap7
  pop
  dup4
  add
  jump(tag_25)
tag_23:
  dup5
  dup1
  revert
tag_21:
  dup4
  0x4e487b7100000000000000000000000000000000000000000000000000000000
  dup2
  mstore
  mstore(0x04, 0x41)
  revert
tag_19:
  dup5
  dup4
  0x4e487b7100000000000000000000000000000000000000000000000000000000
  dup2
  mstore
  mstore(0x04, 0x41)
  revert
tag_17:
  dup4
  dup1
  revert
tag_13:
  dup3
  dup1
  revert
tag_11:
  pop
  dup1
  revert
tag_9:
  dup1
  revert
```
