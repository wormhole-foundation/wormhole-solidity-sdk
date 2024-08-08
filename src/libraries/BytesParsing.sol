// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

import "../constants/Common.sol";

//This file appears comically large, but all unused functions are removed by the compiler.
library BytesParsing {
  error OutOfBounds(uint256 offset, uint256 length);
  error LengthMismatch(uint256 encodedLength, uint256 expectedLength);
  error InvalidBoolVal(uint8 val);

  /**
   * Implements runtime check of logic that accesses memory.
   * @param pastTheEndOffset The offset past the end relative to the accessed memory fragment.
   * @param length The length of the memory fragment accessed.
   */
  function checkBound(uint pastTheEndOffset, uint length) internal pure {
    if (pastTheEndOffset > length)
      revert OutOfBounds(pastTheEndOffset, length);
  }

  //Summary of all remaining functions:
  //
  //Each function has 2*2=4 versions:
  //  1. unchecked - no bounds checking (uses suffix `Unchecked`)
  //  2. checked (no suffix)
  //and
  //  1. calldata input (uses suffix `Cd` (can't overload based on storage location))
  //  2. memory input (no suffix)
  //
  //The canoncial/recommended way of parsing data to be maximally gas efficient is to use the
  //  unchecked versions and do a manual check at the end using `checkLength` to ensure that
  //  encoded data was consumed exactly (neither too short nor too long).
  //
  //WARNING: Neither version uses safe math! It is up to the dev to ensure that offset and length
  //  values are sensible. In other words, verify user inputs before passing them on. Preferably,
  //  the format that's being parsed does not allow for such overflows in the first place by e.g.
  //  encoding lengths using at most 4 bytes, etc.
  //
  //Functions:
  //  Unless stated otherwise, all functions take an `encoded` bytes calldata/memory and an `offset`
  //    as input and return the parsed value and the next offset (i.e. the offset pointing to the
  //    next, unparsed byte).
  //
  // * checkLength(encoded, expected) - no return, reverts if encoded.length != expected
  // * slice(encoded, offset, length)
  // * sliceUint<n>Prefixed - n in {8, 16, 32} - parses n bytes of length prefix followed by data
  // * asAddress
  // * asBool
  // * asUint<8*n> - n in {1, ..., 32}, i.e. asUint8, asUint16, ..., asUint256
  // * asBytes<n>  - n in {1, ..., 32}, i.e. asBytes1, asBytes2, ..., asBytes32

  function sliceCdUnchecked(
    bytes calldata encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, length)
      ret := mload(FREE_MEMORY_PTR)

      mstore(ret, length)
      let retStart := add(ret, WORD_SIZE)
      let sliceStart := add(encoded.offset, offset)
      calldatacopy(retStart, sliceStart, length)
      //When compiling with --via-ir then normally allocated memory (i.e. via new) will have 32 byte
      //  memory alignment and so we enforce the same memory alignment here.
      mstore(
        FREE_MEMORY_PTR,
        and(add(add(retStart, length), WORD_SIZE_MINUS_ONE), not(WORD_SIZE_MINUS_ONE))
      )
    }
  }

  function sliceUnchecked(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, length)
      ret := mload(FREE_MEMORY_PTR)

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

      //and(length, 31) is equivalent to `mod(length, 32)`, but 2 gas cheaper
      let shift := and(length, WORD_SIZE_MINUS_ONE)
      if iszero(shift) {
        shift := WORD_SIZE
      }

      let dest := add(ret, shift)
      let end := add(dest, length)
      for {
        let src := add(add(encoded, shift), offset)
      } lt(dest, end) {
        src := add(src, WORD_SIZE)
        dest := add(dest, WORD_SIZE)
      } {
        mstore(dest, mload(src))
      }

      mstore(ret, length)
      //When compiling with --via-ir then normally allocated memory (i.e. via new) will have 32 byte
      //  memory alignment and so we enforce the same memory alignment here.
      mstore(
        FREE_MEMORY_PTR,
        and(add(dest, WORD_SIZE_MINUS_ONE), not(WORD_SIZE_MINUS_ONE))
      )
    }
  }

  /**
   * Hashes subarray of the buffer.
   * The user of this function is responsible for ensuring the subarray is within bounds of the buffer.
   * @param encoded Buffer that contains the subarray to be hashed.
   * @param offset Starting offset of the subarray to be hashed.
   * @param length Size in bytes of the subarray to be hashed.
   */
  function keccak256SubarrayUnchecked(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes32 hash) {
    /// @solidity memory-safe-assembly
    assembly {
      // The length of the bytes type `length` field is that of a word in memory
      let data := add(add(encoded, offset), WORD_SIZE)
      hash := keccak256(data, length)
    }
  }

  /**
   * Hashes subarray of the buffer.
   * @param encoded Buffer that contains the subarray to be hashed.
   * @param offset Starting offset of the subarray to be hashed.
   * @param length Size in bytes of the subarray to be hashed.
   */
  function keccak256Subarray(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes32 hash) {
    uint pastTheEndOffset = offset + length;
    checkBound(pastTheEndOffset, encoded.length);
    hash = keccak256SubarrayUnchecked(encoded, offset, length);
  }

/* -------------------------------------------------------------------------------------------------
Remaining library code below was auto-generated via the following js/node code:

for (const cd of ["Cd", ""])
  console.log(
`function checkLength${cd}(
  bytes ${cd ? "calldata" : "memory"} encoded,
  uint256 expected
) internal pure {
  if (encoded.length != expected)
    revert LengthMismatch(encoded.length, expected);
}

function slice${cd}(
  bytes ${cd ? "calldata" : "memory"} encoded,
  uint offset,
  uint length
) internal pure returns (bytes memory ret, uint nextOffset) {
  (ret, nextOffset) = slice${cd}Unchecked(encoded, offset, length);
  checkBound(nextOffset, encoded.length);
}
`);

const funcs = [
  ...[8,16,32].map(n => [
    `sliceUint${n}Prefixed`,
    cd => [
      `uint${n} len;`,
      `(len, nextOffset) = asUint${n}${cd}Unchecked(encoded, offset);`,
      `(ret, nextOffset) = slice${cd}Unchecked(encoded, nextOffset, uint(len));`
    ],
    `bytes memory`,
  ]), [
    `asAddress`,
    cd => [
      `uint160 tmp;`,
      `(tmp, nextOffset) = asUint160${cd}Unchecked(encoded, offset);`,
      `ret = address(tmp);`
    ],
    `address`
  ], [
    `asBool`,
    cd => [
      `uint8 val;`,
      `(val, nextOffset) = asUint8${cd}Unchecked(encoded, offset);`,
      `if (val & 0xfe != 0)`,
      `  revert InvalidBoolVal(val);`,
      `uint cleanedVal = uint(val);`,
      `//skip 2x iszero opcode`,
      `/// @solidity memory-safe-assembly`,
      `assembly { ret := cleanedVal }`
    ],
    `bool`
  ],
  ...Array.from({length: 32}, (_, i) => [
    `asUint${(i+1)*8}`,
    cd => [
      `/// @solidity memory-safe-assembly`,
      `assembly {`,
      `  nextOffset := add(offset, ${i+1})`,
      cd ? `  ret := shr(${256-(i+1)*8}, calldataload(add(encoded.offset, offset)))`
         : `  ret := mload(add(encoded, nextOffset))`,
      `}`
    ],
    `uint${(i+1)*8}`
  ]),
  ...Array.from({length: 32}, (_, i) => [
    `asBytes${i+1}`,
    cd => [
      `/// @solidity memory-safe-assembly`,
      `assembly {`,
      `  ret := ${cd ? "calldataload" : "mload"}(add(encoded${cd ? ".offset" :""}, ${cd ? "offset" : "add(offset, WORD_SIZE)"}))`,
      `  nextOffset := add(offset, ${i+1})`,
      `}`
    ],
    `bytes${i+1}`
  ]),
];

for (const [name, code, ret] of funcs) {
  for (const cd of ["Cd", ""])
    console.log(
`function ${name}${cd}Unchecked(
  bytes ${cd ? "calldata" : "memory"} encoded,
  uint offset
) internal pure returns (${ret} ret, uint nextOffset) {
  ${code(cd).join("\n  ")}
}

function ${name}${cd}(
  bytes ${cd ? "calldata" : "memory"} encoded,
  uint offset
) internal pure returns (${ret} ret, uint nextOffset) {
  (ret, nextOffset) = ${name}${cd}Unchecked(encoded, offset);
  checkBound(nextOffset, encoded.length);
}
`);
}
------------------------------------------------------------------------------------------------- */

  function checkLengthCd(
    bytes calldata encoded,
    uint256 expected
  ) internal pure {
    if (encoded.length != expected)
      revert LengthMismatch(encoded.length, expected);
  }

  function sliceCd(
    bytes calldata encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceCdUnchecked(encoded, offset, length);
    checkBound(nextOffset, encoded.length);
  }

  function checkLength(
    bytes memory encoded,
    uint256 expected
  ) internal pure {
    if (encoded.length != expected)
      revert LengthMismatch(encoded.length, expected);
  }

  function slice(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUnchecked(encoded, offset, length);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint8PrefixedCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint8 len;
    (len, nextOffset) = asUint8CdUnchecked(encoded, offset);
    (ret, nextOffset) = sliceCdUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint8PrefixedCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint8PrefixedCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint8PrefixedUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint8 len;
    (len, nextOffset) = asUint8Unchecked(encoded, offset);
    (ret, nextOffset) = sliceUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint8Prefixed(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint8PrefixedUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint16PrefixedCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint16 len;
    (len, nextOffset) = asUint16CdUnchecked(encoded, offset);
    (ret, nextOffset) = sliceCdUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint16PrefixedCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint16PrefixedCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint16PrefixedUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint16 len;
    (len, nextOffset) = asUint16Unchecked(encoded, offset);
    (ret, nextOffset) = sliceUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint16Prefixed(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint16PrefixedUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint32PrefixedCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint32 len;
    (len, nextOffset) = asUint32CdUnchecked(encoded, offset);
    (ret, nextOffset) = sliceCdUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint32PrefixedCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint32PrefixedCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint32PrefixedUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint32 len;
    (len, nextOffset) = asUint32Unchecked(encoded, offset);
    (ret, nextOffset) = sliceUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint32Prefixed(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint32PrefixedUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asAddressCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (address ret, uint nextOffset) {
    uint160 tmp;
    (tmp, nextOffset) = asUint160CdUnchecked(encoded, offset);
    ret = address(tmp);
  }

  function asAddressCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (address ret, uint nextOffset) {
    (ret, nextOffset) = asAddressCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asAddressUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (address ret, uint nextOffset) {
    uint160 tmp;
    (tmp, nextOffset) = asUint160Unchecked(encoded, offset);
    ret = address(tmp);
  }

  function asAddress(
    bytes memory encoded,
    uint offset
  ) internal pure returns (address ret, uint nextOffset) {
    (ret, nextOffset) = asAddressUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBoolCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bool ret, uint nextOffset) {
    uint8 val;
    (val, nextOffset) = asUint8CdUnchecked(encoded, offset);
    if (val & 0xfe != 0)
      revert InvalidBoolVal(val);
    uint cleanedVal = uint(val);
    //skip 2x iszero opcode
    /// @solidity memory-safe-assembly
    assembly { ret := cleanedVal }
  }

  function asBoolCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bool ret, uint nextOffset) {
    (ret, nextOffset) = asBoolCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBoolUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bool ret, uint nextOffset) {
    uint8 val;
    (val, nextOffset) = asUint8Unchecked(encoded, offset);
    if (val & 0xfe != 0)
      revert InvalidBoolVal(val);
    uint cleanedVal = uint(val);
    //skip 2x iszero opcode
    /// @solidity memory-safe-assembly
    assembly { ret := cleanedVal }
  }

  function asBool(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bool ret, uint nextOffset) {
    (ret, nextOffset) = asBoolUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asUint8CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint8 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 1)
      ret := shr(248, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint8Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint8 ret, uint nextOffset) {
    (ret, nextOffset) = asUint8CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

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

  function asUint16CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint16 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 2)
      ret := shr(240, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint16Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint16 ret, uint nextOffset) {
    (ret, nextOffset) = asUint16CdUnchecked(encoded, offset);
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

  function asUint24CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint24 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 3)
      ret := shr(232, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint24Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint24 ret, uint nextOffset) {
    (ret, nextOffset) = asUint24CdUnchecked(encoded, offset);
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

  function asUint32CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint32 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 4)
      ret := shr(224, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint32Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint32 ret, uint nextOffset) {
    (ret, nextOffset) = asUint32CdUnchecked(encoded, offset);
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

  function asUint40CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint40 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 5)
      ret := shr(216, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint40Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint40 ret, uint nextOffset) {
    (ret, nextOffset) = asUint40CdUnchecked(encoded, offset);
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

  function asUint48CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint48 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 6)
      ret := shr(208, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint48Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint48 ret, uint nextOffset) {
    (ret, nextOffset) = asUint48CdUnchecked(encoded, offset);
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

  function asUint56CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint56 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 7)
      ret := shr(200, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint56Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint56 ret, uint nextOffset) {
    (ret, nextOffset) = asUint56CdUnchecked(encoded, offset);
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

  function asUint64CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint64 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 8)
      ret := shr(192, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint64Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint64 ret, uint nextOffset) {
    (ret, nextOffset) = asUint64CdUnchecked(encoded, offset);
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

  function asUint72CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint72 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 9)
      ret := shr(184, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint72Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint72 ret, uint nextOffset) {
    (ret, nextOffset) = asUint72CdUnchecked(encoded, offset);
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

  function asUint80CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint80 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 10)
      ret := shr(176, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint80Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint80 ret, uint nextOffset) {
    (ret, nextOffset) = asUint80CdUnchecked(encoded, offset);
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

  function asUint88CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint88 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 11)
      ret := shr(168, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint88Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint88 ret, uint nextOffset) {
    (ret, nextOffset) = asUint88CdUnchecked(encoded, offset);
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

  function asUint96CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint96 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 12)
      ret := shr(160, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint96Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint96 ret, uint nextOffset) {
    (ret, nextOffset) = asUint96CdUnchecked(encoded, offset);
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

  function asUint104CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint104 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 13)
      ret := shr(152, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint104Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint104 ret, uint nextOffset) {
    (ret, nextOffset) = asUint104CdUnchecked(encoded, offset);
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

  function asUint112CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint112 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 14)
      ret := shr(144, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint112Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint112 ret, uint nextOffset) {
    (ret, nextOffset) = asUint112CdUnchecked(encoded, offset);
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

  function asUint120CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint120 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 15)
      ret := shr(136, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint120Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint120 ret, uint nextOffset) {
    (ret, nextOffset) = asUint120CdUnchecked(encoded, offset);
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

  function asUint128CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint128 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 16)
      ret := shr(128, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint128Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint128 ret, uint nextOffset) {
    (ret, nextOffset) = asUint128CdUnchecked(encoded, offset);
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

  function asUint136CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint136 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 17)
      ret := shr(120, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint136Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint136 ret, uint nextOffset) {
    (ret, nextOffset) = asUint136CdUnchecked(encoded, offset);
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

  function asUint144CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint144 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 18)
      ret := shr(112, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint144Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint144 ret, uint nextOffset) {
    (ret, nextOffset) = asUint144CdUnchecked(encoded, offset);
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

  function asUint152CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint152 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 19)
      ret := shr(104, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint152Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint152 ret, uint nextOffset) {
    (ret, nextOffset) = asUint152CdUnchecked(encoded, offset);
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

  function asUint160CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint160 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 20)
      ret := shr(96, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint160Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint160 ret, uint nextOffset) {
    (ret, nextOffset) = asUint160CdUnchecked(encoded, offset);
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

  function asUint168CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint168 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 21)
      ret := shr(88, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint168Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint168 ret, uint nextOffset) {
    (ret, nextOffset) = asUint168CdUnchecked(encoded, offset);
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

  function asUint176CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint176 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 22)
      ret := shr(80, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint176Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint176 ret, uint nextOffset) {
    (ret, nextOffset) = asUint176CdUnchecked(encoded, offset);
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

  function asUint184CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint184 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 23)
      ret := shr(72, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint184Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint184 ret, uint nextOffset) {
    (ret, nextOffset) = asUint184CdUnchecked(encoded, offset);
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

  function asUint192CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint192 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 24)
      ret := shr(64, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint192Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint192 ret, uint nextOffset) {
    (ret, nextOffset) = asUint192CdUnchecked(encoded, offset);
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

  function asUint200CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint200 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 25)
      ret := shr(56, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint200Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint200 ret, uint nextOffset) {
    (ret, nextOffset) = asUint200CdUnchecked(encoded, offset);
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

  function asUint208CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint208 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 26)
      ret := shr(48, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint208Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint208 ret, uint nextOffset) {
    (ret, nextOffset) = asUint208CdUnchecked(encoded, offset);
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

  function asUint216CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint216 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 27)
      ret := shr(40, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint216Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint216 ret, uint nextOffset) {
    (ret, nextOffset) = asUint216CdUnchecked(encoded, offset);
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

  function asUint224CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint224 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 28)
      ret := shr(32, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint224Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint224 ret, uint nextOffset) {
    (ret, nextOffset) = asUint224CdUnchecked(encoded, offset);
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

  function asUint232CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint232 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 29)
      ret := shr(24, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint232Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint232 ret, uint nextOffset) {
    (ret, nextOffset) = asUint232CdUnchecked(encoded, offset);
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

  function asUint240CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint240 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 30)
      ret := shr(16, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint240Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint240 ret, uint nextOffset) {
    (ret, nextOffset) = asUint240CdUnchecked(encoded, offset);
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

  function asUint248CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint248 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 31)
      ret := shr(8, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint248Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint248 ret, uint nextOffset) {
    (ret, nextOffset) = asUint248CdUnchecked(encoded, offset);
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

  function asUint256CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint256 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 32)
      ret := shr(0, calldataload(add(encoded.offset, offset)))
    }
  }

  function asUint256Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (uint256 ret, uint nextOffset) {
    (ret, nextOffset) = asUint256CdUnchecked(encoded, offset);
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

  function asBytes1CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes1 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 1)
    }
  }

  function asBytes1Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes1 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes1CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes1Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes1 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes2CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes2 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 2)
    }
  }

  function asBytes2Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes2 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes2CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes2Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes2 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes3CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes3 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 3)
    }
  }

  function asBytes3Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes3 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes3CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes3Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes3 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes4CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes4 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 4)
    }
  }

  function asBytes4Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes4 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes4CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes4Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes4 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes5CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes5 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 5)
    }
  }

  function asBytes5Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes5 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes5CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes5Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes5 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes6CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes6 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 6)
    }
  }

  function asBytes6Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes6 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes6CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes6Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes6 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes7CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes7 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 7)
    }
  }

  function asBytes7Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes7 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes7CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes7Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes7 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes8CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes8 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 8)
    }
  }

  function asBytes8Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes8 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes8CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes8Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes8 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes9CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes9 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 9)
    }
  }

  function asBytes9Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes9 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes9CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes9Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes9 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes10CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes10 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 10)
    }
  }

  function asBytes10Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes10 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes10CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes10Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes10 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes11CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes11 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 11)
    }
  }

  function asBytes11Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes11 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes11CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes11Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes11 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes12CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes12 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 12)
    }
  }

  function asBytes12Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes12 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes12CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes12Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes12 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes13CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes13 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 13)
    }
  }

  function asBytes13Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes13 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes13CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes13Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes13 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes14CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes14 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 14)
    }
  }

  function asBytes14Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes14 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes14CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes14Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes14 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes15CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes15 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 15)
    }
  }

  function asBytes15Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes15 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes15CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes15Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes15 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes16CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes16 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 16)
    }
  }

  function asBytes16Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes16 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes16CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes16Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes16 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes17CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes17 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 17)
    }
  }

  function asBytes17Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes17 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes17CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes17Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes17 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes18CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes18 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 18)
    }
  }

  function asBytes18Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes18 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes18CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes18Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes18 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes19CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes19 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 19)
    }
  }

  function asBytes19Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes19 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes19CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes19Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes19 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes20CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes20 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 20)
    }
  }

  function asBytes20Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes20 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes20CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes20Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes20 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes21CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes21 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 21)
    }
  }

  function asBytes21Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes21 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes21CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes21Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes21 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes22CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes22 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 22)
    }
  }

  function asBytes22Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes22 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes22CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes22Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes22 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes23CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes23 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 23)
    }
  }

  function asBytes23Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes23 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes23CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes23Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes23 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes24CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes24 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 24)
    }
  }

  function asBytes24Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes24 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes24CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes24Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes24 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes25CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes25 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 25)
    }
  }

  function asBytes25Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes25 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes25CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes25Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes25 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes26CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes26 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 26)
    }
  }

  function asBytes26Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes26 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes26CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes26Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes26 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes27CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes27 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 27)
    }
  }

  function asBytes27Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes27 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes27CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes27Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes27 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes28CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes28 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 28)
    }
  }

  function asBytes28Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes28 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes28CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes28Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes28 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes29CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes29 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 29)
    }
  }

  function asBytes29Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes29 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes29CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes29Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes29 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes30CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes30 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 30)
    }
  }

  function asBytes30Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes30 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes30CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes30Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes30 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes31CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes31 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 31)
    }
  }

  function asBytes31Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes31 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes31CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes31Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes31 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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

  function asBytes32CdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes32 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := calldataload(add(encoded.offset, offset))
      nextOffset := add(offset, 32)
    }
  }

  function asBytes32Cd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes32 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes32CdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function asBytes32Unchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes32 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
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
