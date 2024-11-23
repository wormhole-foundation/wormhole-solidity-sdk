// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

error NotAnEvmAddress(bytes32);

function toUniversalAddress(address addr) pure returns (bytes32 universalAddr) {
  universalAddr = bytes32(uint256(uint160(addr)));
}

function fromUniversalAddress(bytes32 universalAddr) pure returns (address addr) {
  if (bytes12(universalAddr) != 0)
    revert NotAnEvmAddress(universalAddr);

  assembly ("memory-safe") {
    addr := universalAddr
  }
}
