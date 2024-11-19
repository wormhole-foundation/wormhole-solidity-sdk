// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {tokenOrNativeTransfer} from "wormhole-sdk/utils/Transfer.sol";
import {senderAtLeastAdmin} from "wormhole-sdk/components/dispatcher/AccessControl.sol";
import {SWEEP_TOKENS_ID} from "wormhole-sdk/components/dispatcher/Ids.sol";

abstract contract SweepTokens {
  using BytesParsing for bytes;

  function dispatchExecSweepTokens(
    bytes calldata data,
    uint offset,
    uint8 command
  ) internal returns (bool, uint) {
    return command == SWEEP_TOKENS_ID
      ? (true, _sweepTokens(data, offset))
      : (false, offset);
  }

  function _sweepTokens(
    bytes calldata commands,
    uint offset
  ) internal returns (uint) {
    senderAtLeastAdmin();

    address token;
    uint256 amount;
    (token,  offset) = commands.asAddressCdUnchecked(offset);
    (amount, offset) = commands.asUint256CdUnchecked(offset);

    tokenOrNativeTransfer(token, msg.sender, amount);
    return offset;
  }
}