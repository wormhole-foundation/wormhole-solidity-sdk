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

  function checkLength(uint encodedLength, uint expectedLength) internal pure {
    if (encodedLength != expectedLength)
      revert LengthMismatch(encodedLength, expectedLength);
  }

  //Summary of all remaining functions:
  //
  //Each function has 2*2=4 versions:
  //  1. unchecked - no bounds checking (uses suffix `Unchecked`)
  //  2. checked (no suffix)
  //and (since Solidity does not allow overloading based on data location)
  //  1. calldata input (uses tag `Cd` )
  //  2. memory input (uses tag `Mem`)
  //
  //The canoncial/recommended way of parsing data to be maximally gas efficient is to prefer the
  //  calldata variants over the memory variants and to use the unchecked variants with a manual
  //  length check at the end using `checkLength` to ensure that encoded data was consumed exactly.
  //
  //WARNING: Neither variant uses safe math! It is up to the dev to ensure that offset and length
  //  values are sensible. In other words, verify user inputs before passing them on. Preferably,
  //  the format that's being parsed does not allow for such overflows in the first place by e.g.
  //  encoding lengths using at most 4 bytes, etc.
  //
  //Functions:
  //  Unless stated otherwise, all functions take an `encoded` bytes calldata/memory and an `offset`
  //    as input and return the parsed value and the next offset (i.e. the offset pointing to the
  //    next, unparsed byte).
  //
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
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret.offset := add(encoded.offset, offset)
      ret.length := length
      nextOffset := add(offset, length)
    }
  }

  function sliceMemUnchecked(
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

/* -------------------------------------------------------------------------------------------------
Remaining library code below was auto-generated via the following js/node code:

const dlTag = dl => dl ? "Cd" : "Mem";
const dlType = dl =>dl ? "calldata" : "memory";

const funcs = [
  ...[8,16,32].map(n => [
    `sliceUint${n}Prefixed`,
    dl => [
      `uint${n} len;`,
      `(len, nextOffset) = asUint${n}${dlTag(dl)}Unchecked(encoded, offset);`,
      `(ret, nextOffset) = slice${dlTag(dl)}Unchecked(encoded, nextOffset, uint(len));`
    ],
    dl => `bytes ${dlType(dl)}`,
  ]), [
    `asAddress`,
    dl => [
      `uint160 tmp;`,
      `(tmp, nextOffset) = asUint160${dlTag(dl)}Unchecked(encoded, offset);`,
      `ret = address(tmp);`
    ],
    _ => `address`
  ], [
    `asBool`,
    dl => [
      `uint8 val;`,
      `(val, nextOffset) = asUint8${dlTag(dl)}Unchecked(encoded, offset);`,
      `if (val & 0xfe != 0)`,
      `  revert InvalidBoolVal(val);`,
      `uint cleanedVal = uint(val);`,
      `//skip 2x iszero opcode`,
      `/// @solidity memory-safe-assembly`,
      `assembly { ret := cleanedVal }`
    ],
    _ => `bool`
  ],
  ...Array.from({length: 32}, (_, i) => [
    `asUint${(i+1)*8}`,
    dl => [
      `/// @solidity memory-safe-assembly`,
      `assembly {`,
      `  nextOffset := add(offset, ${i+1})`,
      dl ? `  ret := shr(${256-(i+1)*8}, calldataload(add(encoded.offset, offset)))`
         : `  ret := mload(add(encoded, nextOffset))`,
      `}`
    ],
    _ => `uint${(i+1)*8}`
  ]),
  ...Array.from({length: 32}, (_, i) => [
    `asBytes${i+1}`,
    dl => [
      `/// @solidity memory-safe-assembly`,
      `assembly {`,
      `  ret := ${dl ? "calldataload" : "mload"}(add(encoded${dl ? ".offset" :""}, ${dl ? "offset" : "add(offset, WORD_SIZE)"}))`,
      `  nextOffset := add(offset, ${i+1})`,
      `}`
    ],
    _ => `bytes${i+1}`
  ]),
];

for (const dl of [true, false])
  console.log(
`function slice${dlTag(dl)}(
  bytes ${dlType(dl)} encoded,
  uint offset,
  uint length
) internal pure returns (bytes ${dlType(dl)} ret, uint nextOffset) {
  (ret, nextOffset) = slice${dlTag(dl)}Unchecked(encoded, offset, length);
  checkBound(nextOffset, encoded.length);
}
`);

for (const [name, code, ret] of funcs) {
  for (const dl of [true, false])
    console.log(
`function ${name}${dlTag(dl)}Unchecked(
  bytes ${dlType(dl)} encoded,
  uint offset
) internal pure returns (${ret(dl)} ret, uint nextOffset) {
  ${code(dl).join("\n  ")}
}

function ${name}${dlTag(dl)}(
  bytes ${dlType(dl)} encoded,
  uint offset
) internal pure returns (${ret(dl)} ret, uint nextOffset) {
  (ret, nextOffset) = ${name}${dlTag(dl)}Unchecked(encoded, offset);
  checkBound(nextOffset, encoded.length);
}
`);
}
------------------------------------------------------------------------------------------------- */

  function sliceCd(
    bytes calldata encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    (ret, nextOffset) = sliceCdUnchecked(encoded, offset, length);
    checkBound(nextOffset, encoded.length);
  }

  function sliceMem(
    bytes memory encoded,
    uint offset,
    uint length
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceMemUnchecked(encoded, offset, length);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint8PrefixedCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    uint8 len;
    (len, nextOffset) = asUint8CdUnchecked(encoded, offset);
    (ret, nextOffset) = sliceCdUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint8PrefixedCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint8PrefixedCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint8PrefixedMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint8 len;
    (len, nextOffset) = asUint8MemUnchecked(encoded, offset);
    (ret, nextOffset) = sliceMemUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint8PrefixedMem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint8PrefixedMemUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint16PrefixedCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    uint16 len;
    (len, nextOffset) = asUint16CdUnchecked(encoded, offset);
    (ret, nextOffset) = sliceCdUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint16PrefixedCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint16PrefixedCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint16PrefixedMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint16 len;
    (len, nextOffset) = asUint16MemUnchecked(encoded, offset);
    (ret, nextOffset) = sliceMemUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint16PrefixedMem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint16PrefixedMemUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint32PrefixedCdUnchecked(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    uint32 len;
    (len, nextOffset) = asUint32CdUnchecked(encoded, offset);
    (ret, nextOffset) = sliceCdUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint32PrefixedCd(
    bytes calldata encoded,
    uint offset
  ) internal pure returns (bytes calldata ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint32PrefixedCdUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }

  function sliceUint32PrefixedMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    uint32 len;
    (len, nextOffset) = asUint32MemUnchecked(encoded, offset);
    (ret, nextOffset) = sliceMemUnchecked(encoded, nextOffset, uint(len));
  }

  function sliceUint32PrefixedMem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes memory ret, uint nextOffset) {
    (ret, nextOffset) = sliceUint32PrefixedMemUnchecked(encoded, offset);
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

  function asAddressMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (address ret, uint nextOffset) {
    uint160 tmp;
    (tmp, nextOffset) = asUint160MemUnchecked(encoded, offset);
    ret = address(tmp);
  }

  function asAddressMem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (address ret, uint nextOffset) {
    (ret, nextOffset) = asAddressMemUnchecked(encoded, offset);
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

  function asBoolMemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bool ret, uint nextOffset) {
    uint8 val;
    (val, nextOffset) = asUint8MemUnchecked(encoded, offset);
    if (val & 0xfe != 0)
      revert InvalidBoolVal(val);
    uint cleanedVal = uint(val);
    //skip 2x iszero opcode
    /// @solidity memory-safe-assembly
    assembly { ret := cleanedVal }
  }

  function asBoolMem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bool ret, uint nextOffset) {
    (ret, nextOffset) = asBoolMemUnchecked(encoded, offset);
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

  function asUint8MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint8 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 1)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint8Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint8 ret, uint nextOffset) {
    (ret, nextOffset) = asUint8MemUnchecked(encoded, offset);
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

  function asUint16MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint16 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 2)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint16Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint16 ret, uint nextOffset) {
    (ret, nextOffset) = asUint16MemUnchecked(encoded, offset);
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

  function asUint24MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint24 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 3)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint24Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint24 ret, uint nextOffset) {
    (ret, nextOffset) = asUint24MemUnchecked(encoded, offset);
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

  function asUint32MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint32 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 4)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint32Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint32 ret, uint nextOffset) {
    (ret, nextOffset) = asUint32MemUnchecked(encoded, offset);
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

  function asUint40MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint40 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 5)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint40Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint40 ret, uint nextOffset) {
    (ret, nextOffset) = asUint40MemUnchecked(encoded, offset);
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

  function asUint48MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint48 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 6)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint48Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint48 ret, uint nextOffset) {
    (ret, nextOffset) = asUint48MemUnchecked(encoded, offset);
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

  function asUint56MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint56 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 7)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint56Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint56 ret, uint nextOffset) {
    (ret, nextOffset) = asUint56MemUnchecked(encoded, offset);
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

  function asUint64MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint64 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 8)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint64Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint64 ret, uint nextOffset) {
    (ret, nextOffset) = asUint64MemUnchecked(encoded, offset);
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

  function asUint72MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint72 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 9)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint72Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint72 ret, uint nextOffset) {
    (ret, nextOffset) = asUint72MemUnchecked(encoded, offset);
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

  function asUint80MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint80 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 10)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint80Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint80 ret, uint nextOffset) {
    (ret, nextOffset) = asUint80MemUnchecked(encoded, offset);
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

  function asUint88MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint88 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 11)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint88Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint88 ret, uint nextOffset) {
    (ret, nextOffset) = asUint88MemUnchecked(encoded, offset);
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

  function asUint96MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint96 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 12)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint96Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint96 ret, uint nextOffset) {
    (ret, nextOffset) = asUint96MemUnchecked(encoded, offset);
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

  function asUint104MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint104 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 13)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint104Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint104 ret, uint nextOffset) {
    (ret, nextOffset) = asUint104MemUnchecked(encoded, offset);
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

  function asUint112MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint112 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 14)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint112Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint112 ret, uint nextOffset) {
    (ret, nextOffset) = asUint112MemUnchecked(encoded, offset);
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

  function asUint120MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint120 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 15)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint120Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint120 ret, uint nextOffset) {
    (ret, nextOffset) = asUint120MemUnchecked(encoded, offset);
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

  function asUint128MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint128 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 16)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint128Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint128 ret, uint nextOffset) {
    (ret, nextOffset) = asUint128MemUnchecked(encoded, offset);
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

  function asUint136MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint136 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 17)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint136Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint136 ret, uint nextOffset) {
    (ret, nextOffset) = asUint136MemUnchecked(encoded, offset);
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

  function asUint144MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint144 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 18)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint144Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint144 ret, uint nextOffset) {
    (ret, nextOffset) = asUint144MemUnchecked(encoded, offset);
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

  function asUint152MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint152 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 19)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint152Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint152 ret, uint nextOffset) {
    (ret, nextOffset) = asUint152MemUnchecked(encoded, offset);
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

  function asUint160MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint160 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 20)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint160Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint160 ret, uint nextOffset) {
    (ret, nextOffset) = asUint160MemUnchecked(encoded, offset);
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

  function asUint168MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint168 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 21)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint168Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint168 ret, uint nextOffset) {
    (ret, nextOffset) = asUint168MemUnchecked(encoded, offset);
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

  function asUint176MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint176 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 22)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint176Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint176 ret, uint nextOffset) {
    (ret, nextOffset) = asUint176MemUnchecked(encoded, offset);
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

  function asUint184MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint184 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 23)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint184Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint184 ret, uint nextOffset) {
    (ret, nextOffset) = asUint184MemUnchecked(encoded, offset);
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

  function asUint192MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint192 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 24)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint192Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint192 ret, uint nextOffset) {
    (ret, nextOffset) = asUint192MemUnchecked(encoded, offset);
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

  function asUint200MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint200 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 25)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint200Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint200 ret, uint nextOffset) {
    (ret, nextOffset) = asUint200MemUnchecked(encoded, offset);
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

  function asUint208MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint208 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 26)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint208Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint208 ret, uint nextOffset) {
    (ret, nextOffset) = asUint208MemUnchecked(encoded, offset);
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

  function asUint216MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint216 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 27)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint216Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint216 ret, uint nextOffset) {
    (ret, nextOffset) = asUint216MemUnchecked(encoded, offset);
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

  function asUint224MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint224 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 28)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint224Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint224 ret, uint nextOffset) {
    (ret, nextOffset) = asUint224MemUnchecked(encoded, offset);
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

  function asUint232MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint232 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 29)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint232Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint232 ret, uint nextOffset) {
    (ret, nextOffset) = asUint232MemUnchecked(encoded, offset);
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

  function asUint240MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint240 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 30)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint240Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint240 ret, uint nextOffset) {
    (ret, nextOffset) = asUint240MemUnchecked(encoded, offset);
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

  function asUint248MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint248 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 31)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint248Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint248 ret, uint nextOffset) {
    (ret, nextOffset) = asUint248MemUnchecked(encoded, offset);
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

  function asUint256MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint256 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      nextOffset := add(offset, 32)
      ret := mload(add(encoded, nextOffset))
    }
  }

  function asUint256Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (uint256 ret, uint nextOffset) {
    (ret, nextOffset) = asUint256MemUnchecked(encoded, offset);
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

  function asBytes1MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes1 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 1)
    }
  }

  function asBytes1Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes1 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes1MemUnchecked(encoded, offset);
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

  function asBytes2MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes2 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 2)
    }
  }

  function asBytes2Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes2 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes2MemUnchecked(encoded, offset);
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

  function asBytes3MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes3 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 3)
    }
  }

  function asBytes3Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes3 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes3MemUnchecked(encoded, offset);
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

  function asBytes4MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes4 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 4)
    }
  }

  function asBytes4Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes4 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes4MemUnchecked(encoded, offset);
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

  function asBytes5MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes5 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 5)
    }
  }

  function asBytes5Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes5 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes5MemUnchecked(encoded, offset);
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

  function asBytes6MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes6 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 6)
    }
  }

  function asBytes6Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes6 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes6MemUnchecked(encoded, offset);
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

  function asBytes7MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes7 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 7)
    }
  }

  function asBytes7Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes7 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes7MemUnchecked(encoded, offset);
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

  function asBytes8MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes8 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 8)
    }
  }

  function asBytes8Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes8 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes8MemUnchecked(encoded, offset);
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

  function asBytes9MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes9 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 9)
    }
  }

  function asBytes9Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes9 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes9MemUnchecked(encoded, offset);
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

  function asBytes10MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes10 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 10)
    }
  }

  function asBytes10Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes10 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes10MemUnchecked(encoded, offset);
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

  function asBytes11MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes11 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 11)
    }
  }

  function asBytes11Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes11 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes11MemUnchecked(encoded, offset);
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

  function asBytes12MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes12 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 12)
    }
  }

  function asBytes12Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes12 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes12MemUnchecked(encoded, offset);
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

  function asBytes13MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes13 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 13)
    }
  }

  function asBytes13Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes13 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes13MemUnchecked(encoded, offset);
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

  function asBytes14MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes14 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 14)
    }
  }

  function asBytes14Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes14 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes14MemUnchecked(encoded, offset);
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

  function asBytes15MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes15 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 15)
    }
  }

  function asBytes15Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes15 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes15MemUnchecked(encoded, offset);
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

  function asBytes16MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes16 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 16)
    }
  }

  function asBytes16Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes16 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes16MemUnchecked(encoded, offset);
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

  function asBytes17MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes17 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 17)
    }
  }

  function asBytes17Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes17 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes17MemUnchecked(encoded, offset);
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

  function asBytes18MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes18 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 18)
    }
  }

  function asBytes18Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes18 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes18MemUnchecked(encoded, offset);
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

  function asBytes19MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes19 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 19)
    }
  }

  function asBytes19Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes19 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes19MemUnchecked(encoded, offset);
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

  function asBytes20MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes20 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 20)
    }
  }

  function asBytes20Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes20 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes20MemUnchecked(encoded, offset);
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

  function asBytes21MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes21 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 21)
    }
  }

  function asBytes21Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes21 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes21MemUnchecked(encoded, offset);
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

  function asBytes22MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes22 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 22)
    }
  }

  function asBytes22Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes22 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes22MemUnchecked(encoded, offset);
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

  function asBytes23MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes23 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 23)
    }
  }

  function asBytes23Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes23 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes23MemUnchecked(encoded, offset);
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

  function asBytes24MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes24 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 24)
    }
  }

  function asBytes24Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes24 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes24MemUnchecked(encoded, offset);
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

  function asBytes25MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes25 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 25)
    }
  }

  function asBytes25Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes25 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes25MemUnchecked(encoded, offset);
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

  function asBytes26MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes26 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 26)
    }
  }

  function asBytes26Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes26 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes26MemUnchecked(encoded, offset);
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

  function asBytes27MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes27 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 27)
    }
  }

  function asBytes27Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes27 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes27MemUnchecked(encoded, offset);
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

  function asBytes28MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes28 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 28)
    }
  }

  function asBytes28Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes28 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes28MemUnchecked(encoded, offset);
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

  function asBytes29MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes29 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 29)
    }
  }

  function asBytes29Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes29 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes29MemUnchecked(encoded, offset);
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

  function asBytes30MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes30 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 30)
    }
  }

  function asBytes30Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes30 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes30MemUnchecked(encoded, offset);
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

  function asBytes31MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes31 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 31)
    }
  }

  function asBytes31Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes31 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes31MemUnchecked(encoded, offset);
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

  function asBytes32MemUnchecked(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes32 ret, uint nextOffset) {
    /// @solidity memory-safe-assembly
    assembly {
      ret := mload(add(encoded, add(offset, WORD_SIZE)))
      nextOffset := add(offset, 32)
    }
  }

  function asBytes32Mem(
    bytes memory encoded,
    uint offset
  ) internal pure returns (bytes32 ret, uint nextOffset) {
    (ret, nextOffset) = asBytes32MemUnchecked(encoded, offset);
    checkBound(nextOffset, encoded.length);
  }
}
