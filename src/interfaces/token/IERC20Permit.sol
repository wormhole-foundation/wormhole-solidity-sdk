// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import "IERC20/IERC20.sol";

//https://eips.ethereum.org/EIPS/eip-2612
interface IERC20Permit is IERC20 {
  function permit(
    address owner,
    address spender,
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;
  function nonces(address owner) external view returns (uint);
  function DOMAIN_SEPARATOR() external view returns (bytes32);
}
