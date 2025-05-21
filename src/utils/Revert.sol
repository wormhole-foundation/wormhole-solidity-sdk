// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {WORD_SIZE} from "../constants/Common.sol";

//bubble up errors from low level calls
function reRevert(bytes memory err) pure {
  assembly ("memory-safe") {
    revert(add(err, WORD_SIZE), mload(err))
  }
}
