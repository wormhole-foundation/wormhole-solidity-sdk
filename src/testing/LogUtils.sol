// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";

library LogUtils {
  function filter(
    Vm.Log[] memory logs,
    address emitter
  ) internal pure returns (Vm.Log[] memory) {
    return filter(logs, emitter, bytes32(0), _noDataFilter);
  }

  function filter(
    Vm.Log[] memory logs,
    bytes32 topic
  ) internal pure returns (Vm.Log[] memory) {
    return filter(logs, address(0), topic, _noDataFilter);
  }

  function filter(
    Vm.Log[] memory logs,
    address emitter,
    bytes32 topic
  ) internal pure returns (Vm.Log[] memory) {
    return filter(logs, emitter, topic, _noDataFilter);
  }

  function filter(
    Vm.Log[] memory logs,
    address emitter,
    bytes32 topic,
    function(bytes memory) pure returns (bool) dataFilter
  ) internal pure returns (Vm.Log[] memory ret) { unchecked {
    ret = new Vm.Log[](logs.length);
    uint count;
    for (uint i; i < logs.length; ++i)
      if ((topic == bytes32(0) || logs[i].topics[0] == topic) &&
          (emitter == address(0) || logs[i].emitter == emitter) &&
          dataFilter(logs[i].data))
        ret[count++] = logs[i];

    //trim length
    assembly { mstore(ret, count) }
  }}

  function _noDataFilter(bytes memory) private pure returns (bool) {
    return true;
  }
}
