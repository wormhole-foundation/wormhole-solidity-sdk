// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

// ----------- Dispatcher Ids -----------

// Execute commands

uint8 constant ACCESS_CONTROL_ID = 0x60;
uint8 constant ACQUIRE_OWNERSHIP_ID = 0x61;
uint8 constant UPGRADE_CONTRACT_ID = 0x62;
uint8 constant SWEEP_TOKENS_ID = 0x63;

// Query commands

uint8 constant ACCESS_CONTROL_QUERIES_ID = 0xe0;
uint8 constant IMPLEMENTATION_ID = 0xe1;

// ----------- Access Control Ids -----------

// Execute commands

//admin:
uint8 constant REVOKE_ADMIN_ID = 0x00;

//owner only:
uint8 constant PROPOSE_OWNERSHIP_TRANSFER_ID = 0x10;
uint8 constant RELINQUISH_OWNERSHIP_ID = 0x11;
uint8 constant ADD_ADMIN_ID = 0x12;

// Query commands

uint8 constant OWNER_ID = 0x80;
uint8 constant PENDING_OWNER_ID = 0x81;
uint8 constant IS_ADMIN_ID = 0x82;
uint8 constant ADMINS_ID = 0x83;