// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

error DuplicateItemFound();

function existsInArray(address[] memory array, address value) pure returns (bool) {
  for (uint256 i = 0; i < array.length; i++)
    if (array[i] == value)
      return true;
  return false;
}

function checkForDuplicates(address[] memory array) pure {
  for (uint256 i = 0; i < array.length; i++)
    for (uint256 j = i + 1; j < array.length; j++)
      if (array[i] == array[j])
        revert DuplicateItemFound();
}