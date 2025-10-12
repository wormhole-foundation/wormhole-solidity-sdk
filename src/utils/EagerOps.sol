// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

//see Optimization.md for rationale on avoiding short-circuiting
function eagerAnd(bool lhs, bool rhs) pure returns (bool ret) {
  /// @solidity memory-safe-assembly
  assembly {
    ret := and(lhs, rhs)
  }
}

//see Optimization.md for rationale on avoiding short-circuiting
function eagerOr(bool lhs, bool rhs) pure returns (bool ret) {
  /// @solidity memory-safe-assembly
  assembly {
    ret := or(lhs, rhs)
  }
}
