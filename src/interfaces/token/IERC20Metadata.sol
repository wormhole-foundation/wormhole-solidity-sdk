// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./IERC20.sol";

//https://eips.ethereum.org/EIPS/eip-20
interface IERC20Metadata is IERC20 {
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function decimals() external view returns (uint8);
}
