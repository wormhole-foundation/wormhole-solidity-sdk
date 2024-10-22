// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {transferTokens} from "../TransferUtils.sol";
import {senderHasAuth} from "./AccessControl.sol";
import "./ids.sol";

abstract contract SweepTokens {
  using BytesParsing for bytes;

  /**
   * Dispatch an execute function. Execute functions almost always modify contract state.
   */
  function dispatchExecSweepTokens(bytes calldata data, uint256 offset, uint8 command) internal returns (bool, uint256) {
    if (command == SWEEP_TOKENS_ID)
      offset = _sweepTokens(data, offset);
    else return (false, offset);

    return (true, offset);
  }

  function _sweepTokens(
    bytes calldata commands,
    uint offset
  ) internal returns (uint) {
    senderHasAuth();

    address token;
    uint256 amount;
    (token,  offset) = commands.asAddressCdUnchecked(offset);
    (amount, offset) = commands.asUint256CdUnchecked(offset);

    transferTokens(token, msg.sender, amount);
    return offset;
  }
}