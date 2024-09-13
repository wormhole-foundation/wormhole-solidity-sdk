// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "wormhole-sdk/constants/Common.sol";
import { BytesParsing } from "wormhole-sdk/libraries/BytesParsing.sol";
import { BytesParsingTestWrapper } from "./generated/BytesParsingTestWrapper.sol";

contract TestBytesParsing is Test {
  using BytesParsing for bytes;

  BytesParsingTestWrapper wrapper;

  mapping (uint => string) strVal;

  function uintToString(uint value) private pure returns (string memory) {
    if (value == 0)
      return "0";

    uint digits;
    for (uint temp = value; temp != 0; temp /= 10)
      ++digits;

    bytes memory buffer = new bytes(digits);
    while (value != 0) {
      --digits;
      buffer[digits] = bytes1(uint8(48 + (value % 10))); // 48 is the ASCII code for '0'
      value /= 10;
    }

    return string(buffer);
  }

  function setUp() public { unchecked {
    wrapper = new BytesParsingTestWrapper();
    for (uint i = 1; i < WORD_SIZE_PLUS_ONE; ++i) {
      strVal[i]   = uintToString(i);
      strVal[8*i] = uintToString(8*i);
    }
  }}

  function toFunctionSignature(
    string memory first,
    bool cd,
    bool checked,
    string memory second
  ) private pure returns (string memory) {
    return string(abi.encodePacked(first, cd ? "Cd" : "", checked ? "" : "Unchecked", second));
  }

  function encodedOutOfBounds(
    uint expectedNewOffset,
    uint dataLength
  ) private pure returns (bytes memory) {
    return abi.encodeWithSelector(BytesParsing.OutOfBounds.selector, expectedNewOffset, dataLength);
  }

  /// forge-config: default.fuzz.runs = 20000
  function testFuzzUintAndBytesParsing(
    bytes calldata data,
    uint size,
    uint offset,
    bool uintOrBytes,
    bool cd,
    bool checked
  ) public { unchecked {
    size = bound(size, 1, WORD_SIZE);
    offset = bound(offset, 0, data.length);
    uint expectedNewOffset = offset + size;
    string memory funcSig = toFunctionSignature(
      string(abi.encodePacked(
        uintOrBytes ? "asUint" : "asBytes",
        strVal[(uintOrBytes ? 8 : 1) * size]
      )),
      cd,
      checked,
      "(bytes,uint256)"
    );
    (bool success, bytes memory encodedResult) =
      address(wrapper).call(abi.encodeWithSignature(funcSig, data, offset));

    assertEq(success, !checked || expectedNewOffset <= data.length, "call success mismatch");
    if (success) {
      (uint result, uint newOffset) = abi.decode(encodedResult, (uint, uint));
      assertEq(newOffset, expectedNewOffset, "wrong offset");

      if (newOffset > data.length)
        return;

      uint expected;
      for (uint i = 0; i < size; ++i)
        expected |= uint(uint8(data[offset + i])) << 8*(size-1-i);

      if (!uintOrBytes)
        expected <<= 8*(WORD_SIZE-size);

      assertEq(result, expected, "wrong result");

    }
    else
      assertEq(encodedResult, encodedOutOfBounds(expectedNewOffset, data.length), "wrong error");
  }}

  uint constant BASEWORD = 0x0101010101010101010101010101010101010101010101010101010101010101;

  function largeBytes() private pure returns (bytes memory data) {
    data = new bytes(256 * WORD_SIZE);
    for (uint i = 1; i < 256; ++i)
      assembly ("memory-safe") { mstore(add(data, mul(add(i,1),WORD_SIZE)), mul(i, BASEWORD)) }
  }

  /// forge-config: default.fuzz.runs = 20
  function testFuzzLargeBytes(uint word, uint shift) public {
    bytes memory data = largeBytes();
    assertEq(data.length, 256*WORD_SIZE, "wrong size");
    word = bound(word, 0, WORD_SIZE_MINUS_ONE);
    shift = bound(word, 0, WORD_SIZE_MINUS_ONE);
    (uint result, ) = data.asUint256Unchecked(word*WORD_SIZE + shift);
    assertEq(result, (word*BASEWORD << 8*shift) + ((word+1)*BASEWORD >> 8*(WORD_SIZE-shift)));
  }

  /// forge-config: default.fuzz.runs = 1000
  function testfuzzSlice(uint offset, uint size, bool cd, bool checked) public {
    bytes memory data = largeBytes();
    offset = bound(offset, 0, data.length);
    //we increase the upper bound of size by 25 % beyond what can be correctly read
    //  hence resulting in an out of bounds error 20% of the time
    size = bound(size, 0, (data.length - offset) * 5/4);
    uint expectedNewOffset = offset + size;

    string memory funcSig = toFunctionSignature("slice", cd, checked, "(bytes,uint256,uint256)");
    (bool success, bytes memory encodedResult) =
      address(wrapper).call(abi.encodeWithSignature(funcSig, data, offset, size));

    assertEq(success, !checked || expectedNewOffset <= data.length, "call success mismatch");
    if (success) {
      (bytes memory slice, uint newOffset) = abi.decode(encodedResult, (bytes, uint));
      assertEq(slice.length, size, "wrong slice size");
      assertEq(newOffset, expectedNewOffset, "wrong offset");
      uint upperValid = data.length - offset;
      if (upperValid > size)
        upperValid = size;
      for (uint i = 0; i < upperValid; ++i) {
        (uint lhs, ) = data.asUint8Unchecked(offset+i);
        (uint rhs, ) = slice.asUint8Unchecked(i);
        assertEq(lhs, rhs, "wrong slice byte");
        if (lhs != rhs)
          return;
      }
    }
    else
      assertEq(encodedResult, encodedOutOfBounds(expectedNewOffset, data.length), "wrong error");
  }

  /// forge-config: default.fuzz.runs = 1000
  function testFuzzPrefixedSlice(
    uint offset,
    uint size,
    uint prefixSize,
    bool cd,
    bool checked
  ) public {
    bytes memory data = largeBytes();
    prefixSize = 2**bound(prefixSize, 0, 2); //=1, 2, 4
    offset = bound(offset, 0, data.length-prefixSize);
    //we increase the upper bound of size by 25 % beyond what can be correctly read
    //  hence resulting in an out of bounds error 20% of the time
    size = bound(size, 0, (data.length - offset) * 5/4);
    size = bound(size, 0, 2**(8*prefixSize)-1);
    uint expectedNewOffset = offset + prefixSize + size;
    for (uint i = 0; i < prefixSize; ++i)
      data[offset+i] = bytes1(uint8(size >> 8*(prefixSize-1-i)));

    string memory funcSig = toFunctionSignature(
      string(abi.encodePacked("sliceUint", strVal[8*prefixSize], "Prefixed")),
      cd,
      checked,
      "(bytes,uint256)"
    );
    (bool success, bytes memory encodedResult) =
      address(wrapper).call(abi.encodeWithSignature(funcSig, data, offset));

    assertEq(success, !checked || expectedNewOffset <= data.length, "call success mismatch");
    if (success) {
      (bytes memory slice, uint newOffset) = abi.decode(encodedResult, (bytes, uint));
      assertEq(slice.length, size, "wrong slice size");
      assertEq(newOffset, expectedNewOffset, "wrong offset");
      if (data.length < (offset + prefixSize))
        return;

      uint upperValid = data.length - (offset + prefixSize);
      if (upperValid > size)
        upperValid = size;
      for (uint i = 0; i < upperValid; ++i) {
        (uint lhs, ) = data.asUint8Unchecked(offset+prefixSize+i);
        (uint rhs, ) = slice.asUint8Unchecked(i);
        assertEq(lhs, rhs, "wrong slice byte");
        if (lhs != rhs)
          return;
      }
    }
    else
      assertEq(encodedResult, encodedOutOfBounds(expectedNewOffset, data.length), "wrong error");
  }
}