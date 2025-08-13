// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ExecutorMessages} from "../../src/libraries/executor/ExecutorMessages.sol";

//from https://github.com/wormholelabs-xyz/example-messaging-executor/blob/ec5daea3c03f8860a62c23e28db5c6dc8771a9ce/evm/test/ExecutorMessages.t.sol
contract ExecutorMessagesTest is Test {
    function test_makeVAAv1Request() public {
        uint16 emitterChain = 7;
        bytes32 emitterAddress = bytes32(uint256(uint160(0xdeadbeef)));
        bytes memory expected = abi.encodePacked("ERV1", emitterChain, emitterAddress, uint64(42));
        bytes memory buf = ExecutorMessages.makeVAAv1Request(emitterChain, emitterAddress, 42);
        assertEq(expected, buf);
    }

    function test_makeNTTv1Request() public {
        uint16 srcChain = 7;
        bytes32 srcManager = bytes32(uint256(uint160(0xdeadbeef)));
        bytes32 messageId = bytes32(uint256(42));
        bytes memory expected = abi.encodePacked("ERN1", srcChain, srcManager, messageId);
        bytes memory buf = ExecutorMessages.makeNTTv1Request(srcChain, srcManager, messageId);
        assertEq(expected, buf);
    }

    function test_makeCCTPv1Request() public {
        uint32 srcDomain = 7;
        uint64 nonce = 42;
        bytes memory expected = abi.encodePacked("ERC1", srcDomain, nonce);
        bytes memory buf = ExecutorMessages.makeCCTPv1Request(srcDomain, nonce);
        assertEq(expected, buf);
    }

    function test_makeCCTPv2Request() public {
        bytes memory expected = abi.encodePacked("ERC2", uint8(1));
        bytes memory buf = ExecutorMessages.makeCCTPv2Request();
        assertEq(expected, buf);
    }
}
