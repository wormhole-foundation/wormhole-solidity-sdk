// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

address constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

uint256 constant DEVNET_GUARDIAN_PRIVATE_KEY =
  0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
//corresponding guardian address: 0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe
//should be programmatically recovered via vm.addr(DEVNET_GUARDIAN_PRIVATE_KEY);