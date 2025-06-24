// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.24;

// optional default implementation of eip1967 admin storage
//
// examples of natural extensions/overrides are:
//  - additional pendingAdmin for 2-step ownership transfers
//  - storing additional roles (after the admin slot)

struct AdminState {
  address admin;
}

// we use the designated eip1967 admin storage slot: keccak256("eip1967.proxy.admin") - 1
bytes32 constant ADMIN_SLOT =
  0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

function adminState() pure returns (AdminState storage state) {
  assembly ("memory-safe") { state.slot := ADMIN_SLOT }
}
