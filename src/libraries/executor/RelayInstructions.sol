// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

//from https://github.com/wormholelabs-xyz/example-messaging-executor/blob/ec5daea3c03f8860a62c23e28db5c6dc8771a9ce/evm/src/libraries/RelayInstructions.sol
library RelayInstructions {
    uint8 private constant RECV_INST_TYPE_GAS = uint8(1);
    uint8 private constant RECV_INST_TYPE_DROP_OFF = uint8(2);

    //this instruction may be specified more than once. If so, the relayer should sum the values.
    function encodeGas(uint128 gasLimit, uint128 msgVal) internal pure returns (bytes memory) {
        return abi.encodePacked(RECV_INST_TYPE_GAS, gasLimit, msgVal);
    }

    function encodeGasDropOffInstructions(uint128 dropOff, bytes32 recipient) internal pure returns (bytes memory) {
        return abi.encodePacked(RECV_INST_TYPE_DROP_OFF, dropOff, recipient);
    }
}
