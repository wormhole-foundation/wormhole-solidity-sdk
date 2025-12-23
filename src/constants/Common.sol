// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │ NOTE: We can't define e.g. WORD_SIZE_MINUS_ONE via WORD_SIZE - 1 because     │
// │       of solc restrictions on what constants can be used in inline assembly. │
// └──────────────────────────────────────────────────────────────────────────────┘

uint256 constant WORD_SIZE = 32;
uint256 constant WORD_SIZE_MINUS_ONE = 31; //=0x1f=0b00011111
//see section "prefer `< MAX + 1` over `<= MAX` for const comparison" in docs/Optimization.md
uint256 constant WORD_SIZE_PLUS_ONE = 33;

uint256 constant SCRATCH_SPACE_PTR = 0x00;
uint256 constant SCRATCH_SPACE_SIZE = 64;

uint256 constant FREE_MEMORY_PTR = 0x40;
