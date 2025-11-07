// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "wormhole-sdk/constants/Common.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {BytesParsingTestWrapper} from "./generated/BytesParsingTestWrapper.sol";

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
    return string(abi.encodePacked(first, cd ? "Cd" : "Mem", checked ? "" : "Unchecked", second));
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

  //stores multiples of BASEWORD in ascending order in all full words
  function constructBytes(uint length, uint lowerBound) private view returns (bytes memory data) {
    length = bound(length, lowerBound, 256 * WORD_SIZE);
    data = new bytes(length);
    uint fullWords = length / WORD_SIZE;
    for (uint i = 0; i < fullWords; ++i)
      assembly ("memory-safe") {
        mstore(add(data, mul(add(i, 1), WORD_SIZE)), mul(add(i, 1), BASEWORD))
      }
    
    uint remainingBytes = length % WORD_SIZE;
    assembly ("memory-safe") {
      mstore(
        add(data, mul(add(fullWords, 1), WORD_SIZE)),
        and(BASEWORD, shl(mul(sub(WORD_SIZE, remainingBytes), 8), not(0)))
      )
    }
  }

  /// forge-config: default.fuzz.runs = 200
  function testFuzzBytes(uint length, uint shift) public {
    bytes memory data = constructBytes(length, WORD_SIZE);
    uint fullWords = data.length / WORD_SIZE;
    shift = bound(shift, 0, fullWords-1);
    (uint result, ) = data.asUint256MemUnchecked(shift);
    uint wordIndex = shift / WORD_SIZE + 1;  // +1 because constructBytes stores (i+1)*BASEWORD
    uint byteOffset = shift % WORD_SIZE;
    uint expected =
      (wordIndex * BASEWORD << 8*byteOffset) +
      ((wordIndex+1) * BASEWORD >> 8*(WORD_SIZE-byteOffset));
    assertEq(result, expected);
  }

  /// forge-config: default.fuzz.runs = 1000
  function testFuzzSlice(uint length, uint offset, uint size, bool cd, bool checked) public {
    bytes memory data = constructBytes(length, 1);
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
        (uint lhs, ) = data.asUint8MemUnchecked(offset+i);
        (uint rhs, ) = slice.asUint8MemUnchecked(i);
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
    uint length,
    uint offset,
    uint size,
    uint prefixSize,
    bool cd,
    bool checked
  ) public {
    bytes memory data = constructBytes(length, 4); // ensure we have enough bytes for the prefix
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
        (uint lhs, ) = data.asUint8MemUnchecked(offset+prefixSize+i);
        (uint rhs, ) = slice.asUint8MemUnchecked(i);
        assertEq(lhs, rhs, "wrong slice byte");
        if (lhs != rhs)
          return;
      }
    }
    else
      assertEq(encodedResult, encodedOutOfBounds(expectedNewOffset, data.length), "wrong error");
  }
}
