// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import {ICustomConsistencyLevel} from "wormhole-sdk/interfaces/ICustomConsistencyLevel.sol";

//from https://github.com/wormhole-foundation/wormhole/blob/39081fa2936badf178f8b7e5eb63074d3308bf7d/ethereum/contracts/custom_consistency_level/libraries/ConfigMakers.sol
library CustomConsistencyLib {
  uint8   internal constant TYPE_ADDITIONAL_BLOCKS = 1;

  uint256 internal constant TYPE_SHIFT = 31*8; //type is the leftmost (most significant) byte

  uint256 internal constant AB_TYPE_SHIFTED = uint256(TYPE_ADDITIONAL_BLOCKS) << TYPE_SHIFT;
  uint256 internal constant AB_CONSISTENCY_LEVEL_SHIFT = TYPE_SHIFT - 8;
  uint256 internal constant AB_BLOCKS_TO_WAIT_SHIFT = AB_CONSISTENCY_LEVEL_SHIFT - 2*8;

  error TypeIdMismatch(uint256 received, uint256 expected);

  function setAdditionalBlocksConfig(
    address cclContract,
    uint8 consistencyLevel,
    uint16 blocksToWait
  ) internal {
    ICustomConsistencyLevel(cclContract).configure(
      encodeAdditionalBlocksConfig(consistencyLevel, blocksToWait)
    );
  }

  function getAdditionalBlocksConfig(
    address cclContract
  ) internal view returns (uint8 consistencyLevel, uint16 blocksToWait) {
    return decodeAdditionalBlocksConfig(
      ICustomConsistencyLevel(cclContract).getConfiguration(address(this))
    );
  }

  //blocksToWait specifies the number of additional blocks to wait
  //  _after_ the consistency level is reached
  function encodeAdditionalBlocksConfig(
    uint8 consistencyLevel,
    uint16 blocksToWait
  ) internal pure returns (bytes32) {
    return bytes32(
      AB_TYPE_SHIFTED                                           |
      (uint256(consistencyLevel) << AB_CONSISTENCY_LEVEL_SHIFT) |
      (uint256(blocksToWait)     << AB_BLOCKS_TO_WAIT_SHIFT   )
    );
  }

  function decodeAdditionalBlocksConfig(
    bytes32 config
  ) internal pure returns (uint8 consistencyLevel, uint16 blocksToWait) {
    uint256 config_ = uint256(config);
    uint256 typeId = config_ >> TYPE_SHIFT;
    if (typeId != uint256(TYPE_ADDITIONAL_BLOCKS))
      revert TypeIdMismatch(typeId, TYPE_ADDITIONAL_BLOCKS);

    consistencyLevel = uint8 (config_ >> AB_CONSISTENCY_LEVEL_SHIFT);
    blocksToWait     = uint16(config_ >> AB_BLOCKS_TO_WAIT_SHIFT   );
  }
}
