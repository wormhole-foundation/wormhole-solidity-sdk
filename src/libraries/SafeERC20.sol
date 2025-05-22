// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

import {IERC20} from "../interfaces/token/IERC20.sol";
import {WORD_SIZE, SCRATCH_SPACE_PTR} from "../constants/Common.sol";

//Like OpenZeppelin's SafeERC20.sol, but slimmed down and more gas efficient.
//
//The main difference to OZ's implementation (besides the missing functions) is that we skip the
//  EXTCODESIZE check that OZ does upon successful calls to ensure that an actual contract was
//  called. The rationale for omitting this check is that ultimately the contract using the token
//  has to verify that it "makes sense" for its use case regardless. Otherwise, a random token, or
//  even just a contract that always returns true, could be passed, which makes this check
//  superfluous in the final analysis.
//
//We also save on code size by not duplicating the assembly code in two separate functions.
//  Otoh, we simply swallow revert reasons of failing token operations instead of bubbling them up.
//  This is less clean and makes debugging harder, but is likely still a worthwhile trade-off
//    given the cost in gas and code size.
library SafeERC20 {
  error SafeERC20FailedOperation(address token);

  function safeTransfer(IERC20 token, address to, uint256 value) internal {
    _revertOnFailure(token, abi.encodeCall(token.transfer, (to, value)));
  }

  function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
    _revertOnFailure(token, abi.encodeCall(token.transferFrom, (from, to, value)));
  }

  function forceApprove(IERC20 token, address spender, uint256 value) internal {
    bytes memory approveCall = abi.encodeCall(token.approve, (spender, value));

    if (!_callWithOptionalReturnCheck(token, approveCall)) {
      _revertOnFailure(token, abi.encodeCall(token.approve, (spender, 0)));
      _revertOnFailure(token, approveCall);
    }
  }

  function _callWithOptionalReturnCheck(
    IERC20 token,
    bytes memory encodedCall
  ) private returns (bool success) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(SCRATCH_SPACE_PTR, 0)
      success := call( //see https://www.evm.codes/?fork=cancun#f1
        gas(),                       //gas
        token,                       //callee
        0,                           //value
        add(encodedCall, WORD_SIZE), //input ptr
        mload(encodedCall),          //input size
        SCRATCH_SPACE_PTR,           //output ptr
        WORD_SIZE                    //output size
      )
      //calls to addresses without code are always successful
      if success {
        success := or(iszero(returndatasize()), mload(SCRATCH_SPACE_PTR))
      }
    }
  }

  function _revertOnFailure(IERC20 token, bytes memory encodedCall) private {
    if (!_callWithOptionalReturnCheck(token, encodedCall))
      revert SafeERC20FailedOperation(address(token));
  }
}
