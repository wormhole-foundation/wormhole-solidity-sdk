// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {CONSISTENCY_LEVEL_SAFE} from "../src/constants/ConsistencyLevel.sol";
import {ConsistencyConfigMaker} from "../src/libraries/ConsistencyConfigMaker.sol";

//from https://github.com/wormhole-foundation/wormhole/blob/39081fa2936badf178f8b7e5eb63074d3308bf7d/ethereum/forge-test/CustomConsistencyLevel.t.sol
contract CustomConsistencyLevelTest is Test {
    function test_makeAdditionalBlocksConfig() public {
        bytes32 expected = 0x01c9002a00000000000000000000000000000000000000000000000000000000;
        bytes32 result = ConsistencyConfigMaker.makeAdditionalBlocksConfig(CONSISTENCY_LEVEL_SAFE, 42);
        assertEq(expected, result);
    }
}
