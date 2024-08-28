// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.24;

struct ImplementationState {
  address implementation;
  bool    initialized;
}

// we use the designated eip1967 storage slot: keccak256("eip1967.proxy.implementation") - 1
bytes32 constant IMPLEMENTATION_SLOT =
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

function implementationState() pure returns (ImplementationState storage state) {
  assembly ("memory-safe") { state.slot := IMPLEMENTATION_SLOT }
}
