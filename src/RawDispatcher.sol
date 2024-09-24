// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

//TL;DR:
//  Allows implementing custom call dispatching logic that is more efficient both in terms
//    of gas (only when using the via-IR pipeline!) and calldata size than Solidity's default
//    encoding and dispatching.
//
//  The numbers in the function names of this contract are meaningless and only serve the
//    purpose of yielding a low selector that will guarantee that these functions will come
//    first in Solidity's default function sorting _when using the via-IR pipeline_.
//
//See docs/RawDispatcher.md for details.
abstract contract RawDispatcher {

  //selector: 00000eb6
  function exec768() external payable returns (bytes memory) {
    return _exec(msg.data[4:]);
  }

  //selector: 0008a112
  function get1959() external view returns (bytes memory) {
    return _get(msg.data[4:]);
  }

  function _exec(bytes calldata data) internal virtual returns (bytes memory);

  function _get(bytes calldata data) internal view virtual returns (bytes memory);
}
