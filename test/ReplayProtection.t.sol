// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {AlreadyProcessed} from "wormhole-sdk/libraries/ReplayProtection.sol";
import {VaaLib} from "wormhole-sdk/libraries/VaaLib.sol";
import {
  SequenceReplayProtectionLibTestWrapper,
  HashReplayProtectionLibTestWrapper
} from "./generated/ReplayProtectionTestWrapper.sol";

contract ReplayProtectionTest is Test {
  SequenceReplayProtectionLibTestWrapper srpl;
  HashReplayProtectionLibTestWrapper hrpl;

  bytes transferVaaHeader = hex"01000000040d000d9706bcb3a4069e51fc83bfb4056eb080cf412a87384deda904f317aa986cf61f0fdcebf63230a158d42120069321206aaa078ad60bb682031203b4e6b1b2910001f2249a2a93433f48870b6db4d7b41691988ea9f40719bb0dbe3528db37645bf770885087ef5dceb6ef6eb66554a86f442a406121f018e95b161cff512c503c8a010584dbd7d3720ba02e0e9211162742a07b4bf213528f7625df44f0feb3bb4ed4722d92050f2856c25292654f9320e3e783eb0c492bf2aec1b1a5393c4c2f279f26000667d3444e661e1ac6e360e6a0f8679b6ea99f740238be463046c8d727a71fd6e519d26eb6dee985d2f774fc0e8a9a2343cbaf5c265f668d60ab74415c3dd02f860107ce39722a65635d7a9f15a2ea8784cddcfbd88d00c6a89daac2a87548c8e0012d3923a74e4dcebfccebff601e2349923ca2a77d45089619b9e927001ce80e34260008cb06b678a2d78b66a8ef7743cf46f348ad53e36acb9832e9bfd584609ce84db406537259de7244d9d7bd616f028cb56fdf328d71362656ed49381194a9c0db1200094e717815bb93c323311d579b1dab05c87cd7cc4f0ba943f62fb7c1ab1bd174a17aa1507ffd148d7351f1a755b2293f4b146c8a2930fe7c118846af9379d784b7000a16a32494fc02533081afb4d7cf83e9bb579e0018cb2fb94a5b6b988067a75fe34f1697c0bad93cff45e5351e33a8ba5b94be6330c4a07749a5980d6ab4531be8000da6ea6337801ce2479410b14243c5ac4c8b228fae17ef03882dfced6b65c2b13b63a3ee5e1cd4179098712b312bc836b08db29450e917777ee509adeac40a5d2f010ec3ee8c0183486d12137c7f4e6b0c07b0528526376aa8f7c13e103b17803329d96f0af7c4015ba64f2fe32e43449ae6e528c7765d8be866c2fca4b8f5d22e123e001052971d98a3a903ab900901df4d88014baf0497792c797e38a973213d8e924d0165149e5e2298e13274b8becbd73a573e24a0f2a0769fe81da781f5ac051b03f9011101e6ac72622a785481b4e5541557bccfa3e224448b82109d5928037353ddf2d86f677e7eccafb25b073227d06d286f4c5a2efe6436a86fb444c119c40b6b8839001278ee1a77cd29d5a6f19b3008a7f92bcf04aa7a169f572202c697712f26d0ff2a5e361542e7e5175e52633e914557e34004824d3038809496c53046773a6eb86201";
  bytes transferVaaEnvelope = hex"678765c068e534680001ec7372995d5cc8732397fb0ad35c0121e0eaa90d26f828a534cab54391b3a4f500000000001141b520";
  bytes transferVaaPayload = hex"01000000000000000000000000000000000000000000000000000000000d2136ef069b8857feab8184fb687f634618c035dac439dc1aeb3b5598a0f000000000010001000000000000000000000000fc99f58a8974a4bc36e60e2d490bb8d72899ee9f00020000000000000000000000000000000000000000000000000000000000000000";

  function transferVaa() private view returns (bytes memory) {
    return abi.encodePacked(transferVaaHeader, transferVaaEnvelope, transferVaaPayload);
  }

  function setUp() public {
    srpl = new SequenceReplayProtectionLibTestWrapper();
    hrpl = new HashReplayProtectionLibTestWrapper();
  }

  function test_sequenceReplayProtection() public {
    uint16 emitterChainId = 1;
    bytes32 emitterAddress = bytes32(uint256(1));
    uint64 sequence = 3;
    assertFalse(srpl.isReplayProtected(emitterChainId, emitterAddress, sequence));
    srpl.replayProtect(emitterChainId, emitterAddress, sequence);
    assertTrue(srpl.isReplayProtected(emitterChainId, emitterAddress, sequence));
    vm.expectRevert(AlreadyProcessed.selector);
    srpl.replayProtect(emitterChainId, emitterAddress, sequence);
  }

  function test_hashReplayProtection() public {
    bytes memory encodedVaa = transferVaa();
    bytes32 vaaHash = VaaLib.calcVaaSingleHashMem(encodedVaa);
    assertFalse(hrpl.isReplayProtected(encodedVaa));
    assertFalse(hrpl.isReplayProtected(vaaHash));
    hrpl.replayProtect(encodedVaa);
    assertTrue(hrpl.isReplayProtected(encodedVaa));
    assertTrue(hrpl.isReplayProtected(vaaHash));
    vm.expectRevert(AlreadyProcessed.selector);
    hrpl.replayProtect(vaaHash);
  }
}