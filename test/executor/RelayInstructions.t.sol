// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RelayInstructions} from "../../src/libraries/executor/RelayInstructions.sol";

//from https://github.com/wormholelabs-xyz/example-messaging-executor/blob/ec5daea3c03f8860a62c23e28db5c6dc8771a9ce/evm/test/RelayInstructions.t.sol
contract RelayInstructionsTest is Test {
    function test_encodeGas() public {
        uint128 gasLimit = 123456000;
        uint128 msgVal = 42000;
        bytes memory expected = abi.encodePacked(uint8(1), gasLimit, msgVal);
        bytes memory buf = RelayInstructions.encodeGas(gasLimit, msgVal);
        assertEq(expected, buf);
    }

    function test_encodeGasDropOffInstructions() public {
        uint128 dropOff = 123456000;
        bytes32 recipient = bytes32(uint256(uint160(0xdeadbeef)));
        bytes memory expected = abi.encodePacked(uint8(2), dropOff, recipient);
        bytes memory buf = RelayInstructions.encodeGasDropOffInstructions(dropOff, recipient);
        assertEq(expected, buf);
    }

    function test_multipleInstructions() public {
        uint128 gasLimit = 123456000;
        uint128 msgVal = 42000;
        uint128 dropOff = 123456000;
        bytes32 recipient = bytes32(uint256(uint160(0xdeadbeef)));
        bytes memory expected = abi.encodePacked(uint8(1), gasLimit, msgVal, uint8(2), dropOff, recipient);
        bytes memory buf = abi.encodePacked(
            RelayInstructions.encodeGas(gasLimit, msgVal),
            RelayInstructions.encodeGasDropOffInstructions(dropOff, recipient)
        );
        assertEq(expected, buf);
    }
}
