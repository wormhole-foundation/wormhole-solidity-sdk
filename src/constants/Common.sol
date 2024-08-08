// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

//see https://docs.soliditylang.org/en/v0.8.4/internals/layout_in_memory.html
uint256 constant SCRATCH_SPACE_PTR = 0x00;
uint256 constant FREE_MEMORY_PTR = 0x40;
uint256 constant WORD_SIZE = 32;
//we can't define _WORD_SIZE_MINUS_ONE via _WORD_SIZE - 1 because of solc restrictions
//  what constants can be used in inline assembly
uint256 constant WORD_SIZE_MINUS_ONE = 31; //=0x1f=0b00011111

//see section "prefer `< MAX + 1` over `<= MAX` for const comparison" in docs/Optimization.md
uint256 constant WORD_SIZE_PLUS_ONE = 33;
