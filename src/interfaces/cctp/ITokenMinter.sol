// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

/**
 * @title ITokenMinter
 * @notice interface for minter of tokens that are mintable, burnable, and interchangeable
 * across domains.
 */
interface ITokenMinter {
	function tokenController() external view returns (address);

	function burnLimitsPerMessage(address token) external view returns (uint256);

	function remoteTokensToLocalTokens(bytes32 sourceIdHash) external view returns (address);

	function linkTokenPair(address localToken, uint32 remoteDomain, bytes32 remoteToken) external;
}
