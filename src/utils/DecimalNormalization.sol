// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

uint constant TOKEN_BRIDGE_NORMALIZED_DECIMALS = 8;

function normalizeAmount(uint amount, uint decimals) pure returns (uint) { unchecked {
  if (decimals > TOKEN_BRIDGE_NORMALIZED_DECIMALS)
    amount /= 10 ** (decimals - TOKEN_BRIDGE_NORMALIZED_DECIMALS);

  return amount;
}}

function deNormalizeAmount(uint amount, uint decimals) pure returns (uint) { unchecked {
  if (decimals > TOKEN_BRIDGE_NORMALIZED_DECIMALS)
    amount *= 10 ** (decimals - TOKEN_BRIDGE_NORMALIZED_DECIMALS);

  return amount;
}}
