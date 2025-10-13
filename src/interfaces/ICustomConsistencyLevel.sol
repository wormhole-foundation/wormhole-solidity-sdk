// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

//from https://github.com/wormhole-foundation/wormhole/blob/39081fa2936badf178f8b7e5eb63074d3308bf7d/ethereum/contracts/custom_consistency_level/interfaces/ICustomConsistencyLevel.sol
interface ICustomConsistencyLevel {
  //topic0 0xa37f0112e03d41de27266c1680238ff1548c0441ad1e73c82917c000eefdd5ea
  event ConfigSet(address emitterAddress, bytes32 config);

  function configure(bytes32 config) external;

  function getConfiguration(address emitterAddress) external view returns (bytes32);
}
