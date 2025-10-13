// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

//see https://wormhole.com/docs/products/reference/consistency-levels/
uint8 constant CONSISTENCY_LEVEL_INSTANT   = 200;
uint8 constant CONSISTENCY_LEVEL_SAFE      = 201;
uint8 constant CONSISTENCY_LEVEL_FINALIZED =   1; //alternatively 202 is used
//see ICustomConsistencyLevel and ConsistencyConfigLib:
uint8 constant CONSISTENCY_LEVEL_CUSTOM    = 203;
