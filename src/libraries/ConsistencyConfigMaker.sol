// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

//from https://github.com/wormhole-foundation/wormhole/blob/39081fa2936badf178f8b7e5eb63074d3308bf7d/ethereum/contracts/custom_consistency_level/libraries/ConfigMakers.sol
library ConsistencyConfigMaker {
    uint8 public constant TYPE_ADDITIONAL_BLOCKS = 1;

    //blocksToWait specifies the number of additional blocks to wait after the consistency level is reached.
    function makeAdditionalBlocksConfig(uint8 consistencyLevel, uint16 blocksToWait)
        internal
        pure
        returns (bytes32)
    {
        return bytes32((((
          uint256(TYPE_ADDITIONAL_BLOCKS)
          << 8) | uint256(consistencyLevel))
          << 16) | uint256(blocksToWait))
          << 224;
    }
}
