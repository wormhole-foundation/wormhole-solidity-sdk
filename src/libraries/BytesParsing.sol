// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

library BytesParsing {
  uint256 private constant _FREE_MEMORY_PTR = 0x40;
  uint256 private constant _WORD_SIZE = 32;

  error OutOfBounds(uint256 offset, uint256 length);
  error LengthMismatch(uint256 encodedLength, uint256 expectedLength);
  error InvalidBoolVal(uint8 val);

  function checkBound(uint offset, uint length) internal pure {
    if (offset > length)
      revert OutOfBounds(offset, length);
  }

  function checkLength(bytes memory encoded, uint256 expected) internal pure {
    if (encoded.length != expected)
      revert LengthMismatch(encoded.length, expected);
  }

  //Summary of all remaining functions:
  //
  //Each function has two versions:
  // 1. unchecked - no bounds checking (uses suffix `Unchecked`)
  // 2. checked (no suffix)
  //
  //The canoncial/recommended way of parsing data to be maximally gas efficient is to use the
  //  unchecked versions and do a manual check at the end using `checkLength` to ensure that
  //  encoded data was consumed exactly (neither too short nor too long).
  //
  //Functions:
  // * slice
  // * sliceUint<n>Prefixed - n in {8, 16, 32} - parses n bytes of length prefix followed by data
  // * asAddress
  // * asBool
  // * asUint<8*n> - n in {1, ..., 32}, i.e. asUint8, asUint16, ..., asUint256
  // * asBytes<n>  - n in {1, ..., 32}, i.e. asBytes1, asBytes2, ..., asBytes32

  function sliceUnchecked(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    //bail early for degenerate case
    if (length == 0)
      return (new bytes(0), offset);

    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, length)
      ret := mload(_FREE_MEMORY_PTR)

      //Explanation on how we copy data here:
      //  The bytes type has the following layout in memory:
      //    [length: 32 bytes, data: length bytes]
      //  So if we allocate `bytes memory foo = new bytes(1);` then `foo` will be a pointer to 33
      //    bytes where the first 32 bytes contain the length and the last byte is the actual data.
      //  Since mload always loads 32 bytes of memory at once, we use our shift variable to align
      //    our reads so that our last read lines up exactly with the last 32 bytes of `encoded`.
      //  However this also means that if the length of `encoded` is not a multiple of 32 bytes, our
      //    first read will necessarily partly contain bytes from `encoded`'s 32 length bytes that
      //    will be written into the length part of our `ret` slice.
      //  We remedy this issue by writing the length of our `ret` slice at the end, thus
      //    overwritting those garbage bytes.
      let shift := and(length, 31) //equivalent to `mod(length, 32)` but 2 gas cheaper
      if iszero(shift) {
        shift := _WORD_SIZE
      }

      let dest := add(ret, shift)
      let end := add(dest, length)
      for {
        let src := add(add(encoded, shift), offset)
      } lt(dest, end) {
        src := add(src, _WORD_SIZE)
        dest := add(dest, _WORD_SIZE)
      } {
        mstore(dest, mload(src))
      }

      mstore(ret, length)
      //When compiling with --via-ir then normally allocated memory (i.e. via new) will have 32 byte
      //  memory alignment and so we enforce the same memory alignment here.
      mstore(_FREE_MEMORY_PTR, and(add(dest, 31), not(31)))
    }
  }

  function sliceUint8PrefixedUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory, uint) {
    (uint8 len, uint nextOffset) = asUint8Unchecked(encoded, offset);
    return sliceUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint16PrefixedUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory, uint) {
    (uint16 len, uint nextOffset) = asUint16Unchecked(encoded, offset);
    return sliceUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint32PrefixedUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory, uint) {
    (uint32 len, uint nextOffset) = asUint32Unchecked(encoded, offset);
    return sliceUnchecked(encoded, nextOffset, uint(len));
  }

  function asAddressUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (address, uint) {
    (uint160 ret, uint nextOffset) = asUint160Unchecked(encoded, offset);
    return (address(ret), nextOffset);
  }

  function asBoolUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bool, uint) {
    (uint8 val, uint nextOffset) = asUint8Unchecked(encoded, offset);
    if (val & 0xfe != 0)
      revert InvalidBoolVal(val);

    uint cleanedVal = uint(val);
    bool ret;
    //skip 2x iszero opcode
    /// @solidity memory-safe-assembly
    assembly {
      ret := cleanedVal
    }
    return (ret, nextOffset);
  }

  //checked functions

  function slice(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUnchecked(encoded, offset, length);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint8Prefixed(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint8PrefixedUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint16Prefixed(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint16PrefixedUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint32Prefixed(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint32PrefixedUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asAddress(
    bytes memory encoded,
    uint offset
  ) internal pure returns (address ret, uint nextOffset) {
    (ret, nextOffset) = asAddressUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBool(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bool ret, uint nextOffset) {
    (ret, nextOffset) = asBoolUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

/* -------------------------------------------------------------------------------------------------
Remaining library code below was auto-generated by via the following js/node code:

for (let bytes = 1; bytes <= 32; ++bytes) {
  const bits = bytes*8;
  console.log(
`function asUint${bits}Unchecked(
  bytes memory encoded,
  uint offset
) internal pure returns (uint${bits} ret, uint nextOffset) {
  /// @solidity memory-safe-assembly
  assembly {
    nextOffset := add(offset, ${bytes})
    ret := mload(add(encoded, nextOffset))
  }
}

function asUint${bits}(
  bytes memory encoded,
  uint offset
) internal pure returns (uint${bits} ret, uint nextOffset) {
  (ret, nextOffset) = asUint${bits}Unchecked(encoded, offset);
  checkBound(nextOffset, encoded.length);
}

function asBytes${bytes}Unchecked(
  bytes memory encoded,
  uint offset
) internal pure returns (bytes${bytes} ret, uint nextOffset) {
  /// @solidity memory-safe-assembly
  assembly {
    ret := mload(add(encoded, add(offset, _WORD_SIZE)))
    nextOffset := add(offset, ${bytes})
  }
}

function asBytes${bytes}(
  bytes memory encoded,
  uint offset
) internal pure returns (bytes${bytes} ret, uint nextOffset) {
  (ret, nextOffset) = asBytes${bytes}Unchecked(encoded, offset);
  checkBound(nextOffset, encoded.length);
}
`
  );
}
------------------------------------------------------------------------------------------------- */

  function asUint8Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint8 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 1)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint8(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint8 ret, uint nextOffset) {
    (ret, nextOffset) = asUint8Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes1Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes1 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 1)
    }
  }

  function asBytes1(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes1 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes1Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint16Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint16 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 2)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint16(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint16 ret, uint nextOffset) {
    (ret, nextOffset) = asUint16Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes2Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes2 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 2)
    }
  }

  function asBytes2(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes2 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes2Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint24Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint24 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 3)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint24(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint24 ret, uint nextOffset) {
    (ret, nextOffset) = asUint24Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes3Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes3 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 3)
    }
  }

  function asBytes3(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes3 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes3Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint32Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint32 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 4)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint32(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint32 ret, uint nextOffset) {
    (ret, nextOffset) = asUint32Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes4Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes4 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 4)
    }
  }

  function asBytes4(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes4 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes4Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint40Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint40 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 5)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint40(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint40 ret, uint nextOffset) {
    (ret, nextOffset) = asUint40Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes5Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes5 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 5)
    }
  }

  function asBytes5(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes5 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes5Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint48Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint48 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 6)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint48(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint48 ret, uint nextOffset) {
    (ret, nextOffset) = asUint48Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes6Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes6 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 6)
    }
  }

  function asBytes6(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes6 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes6Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint56Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint56 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 7)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint56(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint56 ret, uint nextOffset) {
    (ret, nextOffset) = asUint56Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes7Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes7 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 7)
    }
  }

  function asBytes7(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes7 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes7Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint64Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint64 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 8)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint64(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint64 ret, uint nextOffset) {
    (ret, nextOffset) = asUint64Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes8Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes8 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 8)
    }
  }

  function asBytes8(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes8 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes8Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint72Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint72 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 9)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint72(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint72 ret, uint nextOffset) {
    (ret, nextOffset) = asUint72Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes9Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes9 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 9)
    }
  }

  function asBytes9(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes9 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes9Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint80Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint80 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 10)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint80(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint80 ret, uint nextOffset) {
    (ret, nextOffset) = asUint80Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes10Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes10 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 10)
    }
  }

  function asBytes10(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes10 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes10Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint88Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint88 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 11)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint88(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint88 ret, uint nextOffset) {
    (ret, nextOffset) = asUint88Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes11Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes11 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 11)
    }
  }

  function asBytes11(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes11 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes11Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint96Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint96 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 12)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint96(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint96 ret, uint nextOffset) {
    (ret, nextOffset) = asUint96Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes12Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes12 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 12)
    }
  }

  function asBytes12(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes12 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes12Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint104Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint104 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 13)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint104(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint104 ret, uint nextOffset) {
    (ret, nextOffset) = asUint104Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes13Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes13 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 13)
    }
  }

  function asBytes13(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes13 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes13Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint112Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint112 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 14)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint112(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint112 ret, uint nextOffset) {
    (ret, nextOffset) = asUint112Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes14Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes14 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 14)
    }
  }

  function asBytes14(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes14 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes14Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint120Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint120 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 15)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint120(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint120 ret, uint nextOffset) {
    (ret, nextOffset) = asUint120Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes15Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes15 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 15)
    }
  }

  function asBytes15(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes15 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes15Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint128Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint128 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 16)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint128(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint128 ret, uint nextOffset) {
    (ret, nextOffset) = asUint128Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes16Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes16 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 16)
    }
  }

  function asBytes16(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes16 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes16Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint136Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint136 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 17)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint136(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint136 ret, uint nextOffset) {
    (ret, nextOffset) = asUint136Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes17Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes17 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 17)
    }
  }

  function asBytes17(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes17 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes17Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint144Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint144 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 18)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint144(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint144 ret, uint nextOffset) {
    (ret, nextOffset) = asUint144Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes18Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes18 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 18)
    }
  }

  function asBytes18(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes18 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes18Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint152Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint152 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 19)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint152(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint152 ret, uint nextOffset) {
    (ret, nextOffset) = asUint152Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes19Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes19 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 19)
    }
  }

  function asBytes19(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes19 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes19Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint160Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint160 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 20)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint160(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint160 ret, uint nextOffset) {
    (ret, nextOffset) = asUint160Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes20Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes20 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 20)
    }
  }

  function asBytes20(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes20 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes20Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint168Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint168 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 21)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint168(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint168 ret, uint nextOffset) {
    (ret, nextOffset) = asUint168Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes21Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes21 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 21)
    }
  }

  function asBytes21(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes21 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes21Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint176Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint176 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 22)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint176(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint176 ret, uint nextOffset) {
    (ret, nextOffset) = asUint176Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes22Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes22 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 22)
    }
  }

  function asBytes22(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes22 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes22Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint184Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint184 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 23)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint184(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint184 ret, uint nextOffset) {
    (ret, nextOffset) = asUint184Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes23Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes23 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 23)
    }
  }

  function asBytes23(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes23 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes23Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint192Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint192 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 24)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint192(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint192 ret, uint nextOffset) {
    (ret, nextOffset) = asUint192Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes24Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes24 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 24)
    }
  }

  function asBytes24(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes24 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes24Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint200Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint200 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 25)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint200(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint200 ret, uint nextOffset) {
    (ret, nextOffset) = asUint200Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes25Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes25 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 25)
    }
  }

  function asBytes25(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes25 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes25Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint208Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint208 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 26)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint208(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint208 ret, uint nextOffset) {
    (ret, nextOffset) = asUint208Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes26Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes26 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 26)
    }
  }

  function asBytes26(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes26 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes26Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint216Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint216 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 27)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint216(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint216 ret, uint nextOffset) {
    (ret, nextOffset) = asUint216Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes27Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes27 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 27)
    }
  }

  function asBytes27(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes27 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes27Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint224Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint224 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 28)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint224(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint224 ret, uint nextOffset) {
    (ret, nextOffset) = asUint224Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes28Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes28 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 28)
    }
  }

  function asBytes28(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes28 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes28Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint232Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint232 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 29)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint232(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint232 ret, uint nextOffset) {
    (ret, nextOffset) = asUint232Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes29Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes29 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 29)
    }
  }

  function asBytes29(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes29 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes29Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint240Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint240 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 30)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint240(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint240 ret, uint nextOffset) {
    (ret, nextOffset) = asUint240Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes30Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes30 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 30)
    }
  }

  function asBytes30(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes30 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes30Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint248Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint248 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 31)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint248(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint248 ret, uint nextOffset) {
    (ret, nextOffset) = asUint248Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes31Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes31 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 31)
    }
  }

  function asBytes31(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes31 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes31Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint256Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint256 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 32)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint256(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint256 ret, uint nextOffset) {
    (ret, nextOffset) = asUint256Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes32Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes32 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, _WORD_SIZE)))
      nextOffset := add(offset, 32)
    }
  }

  function asBytes32(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes32 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes32Unchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }
}
