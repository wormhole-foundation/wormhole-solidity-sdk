// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import "wormhole-sdk/interfaces/ICoreBridge.sol";
import "wormhole-sdk/libraries/VaaLib.sol";
import "wormhole-sdk/libraries/TokenBridgeMessages.sol";
import "./generated/VaaLibTestWrapper.sol";
import "./generated/TokenBridgeMessagesTestWrapper.sol";

contract WormholeMessagesTest is Test {
  using VaaLib for CoreBridgeVM;

  // ------------ Test Data ------------

  // ---- Transfer VAA

  bytes transferVaaHeader = hex"01000000040d000d9706bcb3a4069e51fc83bfb4056eb080cf412a87384deda904f317aa986cf61f0fdcebf63230a158d42120069321206aaa078ad60bb682031203b4e6b1b2910001f2249a2a93433f48870b6db4d7b41691988ea9f40719bb0dbe3528db37645bf770885087ef5dceb6ef6eb66554a86f442a406121f018e95b161cff512c503c8a010584dbd7d3720ba02e0e9211162742a07b4bf213528f7625df44f0feb3bb4ed4722d92050f2856c25292654f9320e3e783eb0c492bf2aec1b1a5393c4c2f279f26000667d3444e661e1ac6e360e6a0f8679b6ea99f740238be463046c8d727a71fd6e519d26eb6dee985d2f774fc0e8a9a2343cbaf5c265f668d60ab74415c3dd02f860107ce39722a65635d7a9f15a2ea8784cddcfbd88d00c6a89daac2a87548c8e0012d3923a74e4dcebfccebff601e2349923ca2a77d45089619b9e927001ce80e34260008cb06b678a2d78b66a8ef7743cf46f348ad53e36acb9832e9bfd584609ce84db406537259de7244d9d7bd616f028cb56fdf328d71362656ed49381194a9c0db1200094e717815bb93c323311d579b1dab05c87cd7cc4f0ba943f62fb7c1ab1bd174a17aa1507ffd148d7351f1a755b2293f4b146c8a2930fe7c118846af9379d784b7000a16a32494fc02533081afb4d7cf83e9bb579e0018cb2fb94a5b6b988067a75fe34f1697c0bad93cff45e5351e33a8ba5b94be6330c4a07749a5980d6ab4531be8000da6ea6337801ce2479410b14243c5ac4c8b228fae17ef03882dfced6b65c2b13b63a3ee5e1cd4179098712b312bc836b08db29450e917777ee509adeac40a5d2f010ec3ee8c0183486d12137c7f4e6b0c07b0528526376aa8f7c13e103b17803329d96f0af7c4015ba64f2fe32e43449ae6e528c7765d8be866c2fca4b8f5d22e123e001052971d98a3a903ab900901df4d88014baf0497792c797e38a973213d8e924d0165149e5e2298e13274b8becbd73a573e24a0f2a0769fe81da781f5ac051b03f9011101e6ac72622a785481b4e5541557bccfa3e224448b82109d5928037353ddf2d86f677e7eccafb25b073227d06d286f4c5a2efe6436a86fb444c119c40b6b8839001278ee1a77cd29d5a6f19b3008a7f92bcf04aa7a169f572202c697712f26d0ff2a5e361542e7e5175e52633e914557e34004824d3038809496c53046773a6eb86201";
  bytes transferVaaEnvelope = hex"678765c068e534680001ec7372995d5cc8732397fb0ad35c0121e0eaa90d26f828a534cab54391b3a4f500000000001141b520";
  bytes transferVaaPayload = hex"01000000000000000000000000000000000000000000000000000000000d2136ef069b8857feab8184fb687f634618c035dac439dc1aeb3b5598a0f000000000010001000000000000000000000000fc99f58a8974a4bc36e60e2d490bb8d72899ee9f00020000000000000000000000000000000000000000000000000000000000000000";

  bytes32 transferSingleHash = 0x9a949aeb4b73b188f29a9eeb4e61e3d4738fe55ae6e3ba6d4353b987e866b8d2;
  bytes32 transferDoubleHash = 0xe6697be620697826affc7c35bb1067a1fa2492aea7afe797a6c9481adc6a098b;

  function transferVaa() private view returns (bytes memory) {
    return abi.encodePacked(transferVaaHeader, transferVaaEnvelope, transferVaaPayload);
  }

  function transferVaaSignatures() private pure returns (GuardianSignature[] memory signatures) {
    signatures = new GuardianSignature[](13);
    signatures[0] = GuardianSignature({
      r: bytes32(0x0d9706bcb3a4069e51fc83bfb4056eb080cf412a87384deda904f317aa986cf6),
      s: bytes32(0x1f0fdcebf63230a158d42120069321206aaa078ad60bb682031203b4e6b1b291),
      v: 27,
      guardianIndex: 0
    });
    signatures[1] = GuardianSignature({
      r: bytes32(0xf2249a2a93433f48870b6db4d7b41691988ea9f40719bb0dbe3528db37645bf7),
      s: bytes32(0x70885087ef5dceb6ef6eb66554a86f442a406121f018e95b161cff512c503c8a),
      v: 28,
      guardianIndex: 1
    });
    signatures[2] = GuardianSignature({
      r: bytes32(0x84dbd7d3720ba02e0e9211162742a07b4bf213528f7625df44f0feb3bb4ed472),
      s: bytes32(0x2d92050f2856c25292654f9320e3e783eb0c492bf2aec1b1a5393c4c2f279f26),
      v: 27,
      guardianIndex: 5
    });
    signatures[3] = GuardianSignature({
      r: bytes32(0x67d3444e661e1ac6e360e6a0f8679b6ea99f740238be463046c8d727a71fd6e5),
      s: bytes32(0x19d26eb6dee985d2f774fc0e8a9a2343cbaf5c265f668d60ab74415c3dd02f86),
      v: 28,
      guardianIndex: 6
    });
    signatures[4] = GuardianSignature({
      r: bytes32(0xce39722a65635d7a9f15a2ea8784cddcfbd88d00c6a89daac2a87548c8e0012d),
      s: bytes32(0x3923a74e4dcebfccebff601e2349923ca2a77d45089619b9e927001ce80e3426),
      v: 27,
      guardianIndex: 7
    });
    signatures[5] = GuardianSignature({
      r: bytes32(0xcb06b678a2d78b66a8ef7743cf46f348ad53e36acb9832e9bfd584609ce84db4),
      s: bytes32(0x06537259de7244d9d7bd616f028cb56fdf328d71362656ed49381194a9c0db12),
      v: 27,
      guardianIndex: 8
    });
    signatures[6] = GuardianSignature({
      r: bytes32(0x4e717815bb93c323311d579b1dab05c87cd7cc4f0ba943f62fb7c1ab1bd174a1),
      s: bytes32(0x7aa1507ffd148d7351f1a755b2293f4b146c8a2930fe7c118846af9379d784b7),
      v: 27,
      guardianIndex: 9
    });
    signatures[7] = GuardianSignature({
      r: bytes32(0x16a32494fc02533081afb4d7cf83e9bb579e0018cb2fb94a5b6b988067a75fe3),
      s: bytes32(0x4f1697c0bad93cff45e5351e33a8ba5b94be6330c4a07749a5980d6ab4531be8),
      v: 27,
      guardianIndex: 10
    });
    signatures[8] = GuardianSignature({
      r: bytes32(0xa6ea6337801ce2479410b14243c5ac4c8b228fae17ef03882dfced6b65c2b13b),
      s: bytes32(0x63a3ee5e1cd4179098712b312bc836b08db29450e917777ee509adeac40a5d2f),
      v: 28,
      guardianIndex: 13
    });
    signatures[9] = GuardianSignature({
      r: bytes32(0xc3ee8c0183486d12137c7f4e6b0c07b0528526376aa8f7c13e103b17803329d9),
      s: bytes32(0x6f0af7c4015ba64f2fe32e43449ae6e528c7765d8be866c2fca4b8f5d22e123e),
      v: 27,
      guardianIndex: 14
    });
    signatures[10] = GuardianSignature({
      r: bytes32(0x52971d98a3a903ab900901df4d88014baf0497792c797e38a973213d8e924d01),
      s: bytes32(0x65149e5e2298e13274b8becbd73a573e24a0f2a0769fe81da781f5ac051b03f9),
      v: 28,
      guardianIndex: 16
    });
    signatures[11] = GuardianSignature({
      r: bytes32(0x01e6ac72622a785481b4e5541557bccfa3e224448b82109d5928037353ddf2d8),
      s: bytes32(0x6f677e7eccafb25b073227d06d286f4c5a2efe6436a86fb444c119c40b6b8839),
      v: 27,
      guardianIndex: 17
    });
    signatures[12] = GuardianSignature({
      r: bytes32(0x78ee1a77cd29d5a6f19b3008a7f92bcf04aa7a169f572202c697712f26d0ff2a),
      s: bytes32(0x5e361542e7e5175e52633e914557e34004824d3038809496c53046773a6eb862),
      v: 28,
      guardianIndex: 18
    });
  }

  function transferVaaVm() private view returns (CoreBridgeVM memory) {
    return CoreBridgeVM({
      version: 1,
      guardianSetIndex: 4,
      signatures: transferVaaSignatures(),
      timestamp: 1736926656,
      nonce: 1759851624,
      emitterChainId: 1,
      emitterAddress: bytes32(0xec7372995d5cc8732397fb0ad35c0121e0eaa90d26f828a534cab54391b3a4f5),
      sequence: 1130933,
      consistencyLevel: 32,
      payload: transferVaaPayload,
      hash: transferDoubleHash
    });
  }

  function decodedTransferStruct() private pure returns (TokenBridgeTransfer memory) {
    return TokenBridgeTransfer({
      normalizedAmount: 220280559,
      tokenAddress: bytes32(0x069b8857feab8184fb687f634618c035dac439dc1aeb3b5598a0f00000000001),
      tokenChainId: 1,
      toAddress: bytes32(0x000000000000000000000000fc99f58a8974a4bc36e60e2d490bb8d72899ee9f),
      toChainId: 2
    });
  }

  // ---- Transfer With Payload VAA

  bytes twpVaaHeader = hex"010000000001003fc0ef6fd9c137bfa4f35198f2cb7f7a9963ea1df4d12abc610506fd251e1809741981a389bd7019f615bff4dd791f16bc0cd3461082798cf3cded10d367058f01";
  bytes twpVaaEnvelope = hex"64e5ad49083c010000060000000000000000000000000e082F06FF657D94310cB8cE8B0D9a04541d80520000000000001d6701";
  bytes twpVaaPayloadNo3 = hex"0300000000000000000000000000000000000000000000000000000000001e84800000000000000000000000009c3c9283d3e44854697cd22d3faa240cfb03288900056d9ae6b2d333c1d65301a59da3eed388ca5dc60cb12496584b75cbe6b15fdbed0020000000000000000000000000d493066498ace409059fda4c1bcd2e73d8cffe01";
  bytes twpVaaPayload3 = hex"7b2262617369635f726563697069656e74223a7b22726563697069656e74223a22633256704d54526a4e5755335a585a325933426f64576f306144687563586c6b5a6d357a4d7a49774f585a6d616e526d616d52775a54686a227d7d";

  bytes32 twpSingleHash = 0x11f8d4f421cb592afe5d9204fd9cc345efb80f400853f82188f402963a68756f;
  bytes32 twpDoubleHash = 0xe788dce73c57ddd396c4eb5f5c16199decd8f7318a8524fe37febf10ac2d4aad;

  function twpVaa() private view returns (bytes memory) {
    return abi.encodePacked(twpVaaHeader, twpVaaEnvelope, twpVaaPayloadNo3, twpVaaPayload3);
  }

  function twpVaaPayload() private view returns (bytes memory) {
    return abi.encodePacked(twpVaaPayloadNo3, twpVaaPayload3);
  }

  function twpVaaSignatures() private pure returns (GuardianSignature[] memory) {
    GuardianSignature[] memory signatures = new GuardianSignature[](1);
    signatures[0] = GuardianSignature({
      r: bytes32(0x3fc0ef6fd9c137bfa4f35198f2cb7f7a9963ea1df4d12abc610506fd251e1809),
      s: bytes32(0x741981a389bd7019f615bff4dd791f16bc0cd3461082798cf3cded10d367058f),
      v: 28,
      guardianIndex: 0
    });
    return signatures;
  }

  function twpVaaVm() private view returns (CoreBridgeVM memory) {
    return CoreBridgeVM({
      version: 1,
      guardianSetIndex: 0,
      signatures: twpVaaSignatures(),
      timestamp: 1692773705,
      nonce: 138150144,
      emitterChainId: 6,
      emitterAddress: bytes32(0x0000000000000000000000000e082F06FF657D94310cB8cE8B0D9a04541d8052),
      sequence: 7527,
      consistencyLevel: 1,
      payload: twpVaaPayload(),
      hash: twpDoubleHash
    });
  }

  function decodedTwpStruct() private view returns (TokenBridgeTransferWithPayload memory) {
    return TokenBridgeTransferWithPayload({
      normalizedAmount: 2000000,
      tokenAddress: bytes32(0x0000000000000000000000009c3c9283d3e44854697cd22d3faa240cfb032889),
      tokenChainId: 5,
      toAddress: bytes32(0x6d9ae6b2d333c1d65301a59da3eed388ca5dc60cb12496584b75cbe6b15fdbed),
      toChainId: 32,
      fromAddress: bytes32(0x000000000000000000000000d493066498ace409059fda4c1bcd2e73d8cffe01),
      payload: twpVaaPayload3
    });
  }

  // ---- AttestMeta VAA

  bytes amVaaHeader = hex"01000000000100258085e22c07380831e348d937e2e4e88d41732888e94c50a6192485efd3962708e606cea327c0d3b4448085b2f285a4dd8b4a4e0270671487e9ec6f49ebf5e600";
  bytes amVaaEnvelope = hex"642c4220d1780000000e00000000000000000000000005ca6037ec51f8b712ed2e6fa72219feae74e15300000000000000d601";
  bytes amVaaPayload = hex"02000000000000000000000000f194afdf50b03e69bd7d057c1aa9e10c9954e4c9000e1243454c4f0000000000000000000000000000000000000000000000000000000043656c6f206e6174697665206173736574000000000000000000000000000000";

  bytes32 amSingleHash = 0xe86ff721a31b17ad1a70bed86ac0a306cc0be55687a3d67b0ecee2c7eb4e046d;
  bytes32 amDoubleHash = 0x52eb27c9f34ed757cf0f0ef927ae4defcd640e1a90bcc3e2fb7526e78fa2e815;

  function amVaa() private view returns (bytes memory) {
    return abi.encodePacked(amVaaHeader, amVaaEnvelope, amVaaPayload);
  }

  function amVaaSignatures() private pure returns (GuardianSignature[] memory) {
    GuardianSignature[] memory signatures = new GuardianSignature[](1);
    signatures[0] = GuardianSignature({
      r: bytes32(0x258085e22c07380831e348d937e2e4e88d41732888e94c50a6192485efd39627),
      s: bytes32(0x08e606cea327c0d3b4448085b2f285a4dd8b4a4e0270671487e9ec6f49ebf5e6),
      v: 27,
      guardianIndex: 0
    });
    return signatures;
  }

  function amVaaVm() private view returns (CoreBridgeVM memory) {
    return CoreBridgeVM({
      version: 1,
      guardianSetIndex: 0,
      signatures: amVaaSignatures(),
      timestamp: 1680622112,
      nonce: 3514302464,
      emitterChainId: 14,
      emitterAddress: bytes32(0x00000000000000000000000005ca6037ec51f8b712ed2e6fa72219feae74e153),
      sequence: 214,
      consistencyLevel: 1,
      payload: amVaaPayload,
      hash: amDoubleHash
    });
  }

  function decodedAmStruct() private pure returns (TokenBridgeAttestMeta memory) {
    return TokenBridgeAttestMeta({
      tokenAddress: bytes32(0x000000000000000000000000f194afdf50b03e69bd7d057c1aa9e10c9954e4c9),
      tokenChainId: 14,
      decimals: 18,
      symbol: bytes32(0x43454c4f00000000000000000000000000000000000000000000000000000000),
      name: bytes32(0x43656c6f206e6174697665206173736574000000000000000000000000000000)
    });
  }

  // ------------ Test Code ------------

  address vaaLibWrapper;
  address tbLibWrapper;

  function setUp() public {
    vaaLibWrapper = address(new VaaLibTestWrapper());
    tbLibWrapper = address(new TokenBridgeMessageLibTestWrapper());
  }

  function withDataLocationTag(
    string memory functionName,
    bool cd,
    bool uc,
    string memory parameters
  ) private pure returns (string memory) {
    return string(abi.encodePacked(
      functionName,
      cd ? "Cd" : "Mem",
      uc ? "Unchecked" : "",
      parameters
    ));
  }

  function callWithBytes(
    address wrapper,
    string memory functionName,
    bool cd,
    bytes memory encoded,
    bool expectSuccess
  ) private returns (bytes memory) {
    return callWithBytes(wrapper, functionName, cd, false, encoded, expectSuccess);
  }

  function callWithBytes(
    address wrapper,
    string memory functionName,
    bool cd,
    bool uc,
    bytes memory encoded,
    bool expectSuccess
  ) private returns (bytes memory) {
    (bool success, bytes memory encodedResult) =
      wrapper.staticcall(abi.encodeWithSignature(
        withDataLocationTag(functionName, cd, uc, "(bytes)"),
        encoded
      ));
    assertEq(success, expectSuccess);
    return encodedResult;
  }

  function callWithBytesAndOffset(
    address wrapper,
    string memory functionName,
    bool cd,
    bool uc,
    bytes memory encoded,
    uint offset,
    bool expectSuccess
  ) private returns (bytes memory) {
    (bool success, bytes memory encodedResult) =
      wrapper.staticcall(abi.encodeWithSignature(
        withDataLocationTag(functionName, cd, uc, "(bytes,uint256)"),
        encoded, offset
      ));
    assertEq(success, expectSuccess);
    return encodedResult;
  }

  function callWithBytesOffsetAndLength(
    address wrapper,
    string memory functionName,
    bool cd,
    bool uc,
    bytes memory encoded,
    uint offset,
    uint length,
    bool expectSuccess
  ) private returns (bytes memory) {
    (bool success, bytes memory encodedResult) =
      wrapper.staticcall(abi.encodeWithSignature(
        withDataLocationTag(functionName, cd, uc, "(bytes,uint256,uint256)"),
        encoded, offset, length
      ));
    assertEq(success, expectSuccess);
    return encodedResult;
  }

  function compareSignatures(
    GuardianSignature[] memory signatures,
    GuardianSignature[] memory expectedSignatures
  ) internal {
    assertEq(signatures.length, expectedSignatures.length);
    for (uint i = 0; i < signatures.length; i++) {
      assertEq(signatures[i].r, expectedSignatures[i].r);
      assertEq(signatures[i].s, expectedSignatures[i].s);
      assertEq(signatures[i].v, expectedSignatures[i].v);
      assertEq(signatures[i].guardianIndex, expectedSignatures[i].guardianIndex);
    }
  }

  function compareVms(CoreBridgeVM memory vm, CoreBridgeVM memory expectedVm) internal {
    assertEq(vm.version, expectedVm.version);
    assertEq(vm.guardianSetIndex, expectedVm.guardianSetIndex);
    compareSignatures(vm.signatures, expectedVm.signatures);
    assertEq(vm.timestamp, expectedVm.timestamp);
    assertEq(vm.nonce, expectedVm.nonce);
    assertEq(vm.emitterChainId, expectedVm.emitterChainId);
    assertEq(vm.emitterAddress, expectedVm.emitterAddress);
    assertEq(vm.sequence, expectedVm.sequence);
    assertEq(vm.consistencyLevel, expectedVm.consistencyLevel);
    assertEq(vm.payload, expectedVm.payload);
    assertEq(vm.hash, expectedVm.hash);
  }

  function vmToVaa(CoreBridgeVM memory vm) internal pure returns (Vaa memory vaa) {
    vaa.header.guardianSetIndex = vm.guardianSetIndex;
    vaa.header.signatures = vm.signatures;
    vaa.envelope.timestamp = vm.timestamp;
    vaa.envelope.nonce = vm.nonce;
    vaa.envelope.emitterChainId = vm.emitterChainId;
    vaa.envelope.emitterAddress = vm.emitterAddress;
    vaa.envelope.sequence = vm.sequence;
    vaa.envelope.consistencyLevel = vm.consistencyLevel;
    vaa.payload = vm.payload;
  }

  function compareVaaVm(Vaa memory vaa, CoreBridgeVM memory expectedVm) internal {
    assertEq(vaa.header.guardianSetIndex, expectedVm.guardianSetIndex);
    compareSignatures(vaa.header.signatures, expectedVm.signatures);
    assertEq(vaa.envelope.timestamp, expectedVm.timestamp);
    assertEq(vaa.envelope.nonce, expectedVm.nonce);
    assertEq(vaa.envelope.emitterChainId, expectedVm.emitterChainId);
    assertEq(vaa.envelope.emitterAddress, expectedVm.emitterAddress);
    assertEq(vaa.envelope.sequence, expectedVm.sequence);
    assertEq(vaa.envelope.consistencyLevel, expectedVm.consistencyLevel);
    assertEq(vaa.payload, expectedVm.payload);
  }

  function runBoth(function(bool) test) internal {
    test(true);
    test(false);
  }

  function testEncodingTransferVaa() public {
    assertEq(transferVaaVm().encode(), transferVaa());
    assertEq(vmToVaa(transferVaaVm()).encode(), transferVaa());
  }

  function testEncodingTwpVaa() public {
    assertEq(twpVaaVm().encode(), twpVaa());
    assertEq(vmToVaa(twpVaaVm()).encode(), twpVaa());
  }

  function testEncodingAmVaa() public {
    assertEq(amVaaVm().encode(), amVaa());
    assertEq(vmToVaa(amVaaVm()).encode(), amVaa());
  }

  // ----

  function testVaaHash() public {
    assertEq(VaaLib.calcSingleHash(vmToVaa(transferVaaVm())), transferSingleHash);
    assertEq(VaaLib.calcDoubleHash(vmToVaa(transferVaaVm())), transferDoubleHash);
    assertEq(keccak256Word(transferSingleHash), transferDoubleHash);
    assertEq(VaaLib.calcSingleHash(vmToVaa(twpVaaVm())), twpSingleHash);
    assertEq(VaaLib.calcDoubleHash(vmToVaa(twpVaaVm())), twpDoubleHash);
    assertEq(keccak256Word(twpSingleHash), twpDoubleHash);
    assertEq(VaaLib.calcSingleHash(vmToVaa(amVaaVm())), amSingleHash);
    assertEq(VaaLib.calcDoubleHash(vmToVaa(amVaaVm())), amDoubleHash);
    assertEq(keccak256Word(amSingleHash), amDoubleHash);
  }

  function checkBytesHash(
    bool cd,
    bytes memory encoded,
    bytes32 expectedSingle,
    bytes32 expectedDouble
  ) internal {
    uint envelopeOffset = abi.decode(cd
      ? callWithBytes(vaaLibWrapper, "skipVaaHeader", true, true, encoded, true)
      : callWithBytesAndOffset(vaaLibWrapper, "skipVaaHeader", false, true, encoded, 0, true),
      (uint)
    );

    for (uint i = 0; i < 2; ++i) {
      string memory times = i == 0 ? "Single" : "Double";
      string memory functionName = string(abi.encodePacked("calcVaa", times, "Hash"));
      bytes32 expectedHash = i == 0 ? expectedSingle : expectedDouble;

      bytes32 hash = abi.decode(cd
        ? callWithBytesAndOffset(
          vaaLibWrapper, functionName, cd, false, encoded, envelopeOffset, true
        )
        : callWithBytesOffsetAndLength(
          vaaLibWrapper, functionName, cd, false, encoded, envelopeOffset, encoded.length, true
        ),
        (bytes32)
      );
      assertEq(hash, expectedHash);
    }
  }
  function bytesHash(bool cd) internal {
    checkBytesHash(cd, transferVaa(), transferSingleHash, transferDoubleHash);
    checkBytesHash(cd, twpVaa(),      twpSingleHash,      twpDoubleHash     );
    checkBytesHash(cd, amVaa(),       amSingleHash,       amDoubleHash      );
  }
  function testBytesHash() public { runBoth(bytesHash); }

  // ----

  function decodingTransferVaaVm(bool cd) internal {
    compareVms(
      abi.decode(
        callWithBytes(vaaLibWrapper, "decodeVmStruct", cd, transferVaa(), true),
        (CoreBridgeVM)
      ),
      transferVaaVm()
    );
  }
  function testDecodingTransferVaaVm() public { runBoth(decodingTransferVaaVm); }

  function decodingTransferVaaStruct(bool cd) internal {
    compareVaaVm(
      abi.decode(
        callWithBytes(vaaLibWrapper, "decodeVaaStruct", cd, transferVaa(), true),
        (Vaa)
      ),
      transferVaaVm()
    );
  }
  function testDecodingTransferVaaStruct() public { runBoth(decodingTransferVaaStruct); }

  function decodingTransferPayload(bool cd) internal {
    TokenBridgeTransfer memory transfer = abi.decode(
      callWithBytes(tbLibWrapper, "decodeTransferStruct", cd, transferVaaPayload, true),
      (TokenBridgeTransfer)
    );
    TokenBridgeTransfer memory expected = decodedTransferStruct();

    assertEq(transfer.normalizedAmount, expected.normalizedAmount);
    assertEq(transfer.tokenAddress, expected.tokenAddress);
    assertEq(transfer.tokenChainId, expected.tokenChainId);
    assertEq(transfer.toAddress, expected.toAddress);
    assertEq(transfer.toChainId, expected.toChainId);
  }
  function testDecodingTransferPayload() public { runBoth(decodingTransferPayload); }

  // ----

  function decodingTwpVaaVm(bool cd) internal {
    compareVms(
      abi.decode(
        callWithBytes(vaaLibWrapper, "decodeVmStruct", cd, twpVaa(), true),
        (CoreBridgeVM)
      ),
      twpVaaVm()
    );
  }
  function testDecodingTwpVaaVm() public { runBoth(decodingTwpVaaVm); }

  function decodingTwpVaaStruct(bool cd) internal {
    compareVaaVm(
      abi.decode(
        callWithBytes(vaaLibWrapper, "decodeVaaStruct", cd, twpVaa(), true),
        (Vaa)
      ),
      twpVaaVm()
    );
  }
  function testDecodingTwpVaaStruct() public { runBoth(decodingTwpVaaStruct); }

  function decodingTwpPayload(bool cd) internal {
    TokenBridgeTransferWithPayload memory transfer = abi.decode(
      callWithBytes(tbLibWrapper, "decodeTransferWithPayloadStruct", cd, twpVaaPayload(), true),
      (TokenBridgeTransferWithPayload)
    );
    TokenBridgeTransferWithPayload memory expected = decodedTwpStruct();

    assertEq(transfer.normalizedAmount, expected.normalizedAmount);
    assertEq(transfer.tokenAddress, expected.tokenAddress);
    assertEq(transfer.tokenChainId, expected.tokenChainId);
    assertEq(transfer.toAddress, expected.toAddress);
    assertEq(transfer.toChainId, expected.toChainId);
    assertEq(transfer.fromAddress, expected.fromAddress);
    assertEq(transfer.payload, expected.payload);
  }
  function testDecodingTwpPayload() public { runBoth(decodingTwpPayload); }

  function decodingTwpPayloadEssentials(bool cd) internal {
    TokenBridgeTransferWithPayloadEssentials memory transfer = abi.decode(
      callWithBytes(tbLibWrapper, "decodeTransferWithPayloadEssentialsStruct", cd, twpVaaPayload(), true),
      (TokenBridgeTransferWithPayloadEssentials)
    );
    TokenBridgeTransferWithPayload memory expected = decodedTwpStruct();

    assertEq(transfer.normalizedAmount, expected.normalizedAmount);
    assertEq(transfer.tokenAddress, expected.tokenAddress);
    assertEq(transfer.tokenChainId, expected.tokenChainId);
    assertEq(transfer.fromAddress, expected.fromAddress);
    assertEq(transfer.payload, expected.payload);
  }
  function testDecodingTwpPayloadEssentials() public { runBoth(decodingTwpPayloadEssentials); }

  // ----

  function decodingAmVaaVm(bool cd) internal {
    compareVms(
      abi.decode(
        callWithBytes(vaaLibWrapper, "decodeVmStruct", cd, amVaa(), true),
        (CoreBridgeVM)
      ),
      amVaaVm()
    );
  }
  function testDecodingAmVaaVm() public { runBoth(decodingAmVaaVm); }

  function decodingAmVaaStruct(bool cd) internal {
    compareVaaVm(
      abi.decode(
        callWithBytes(vaaLibWrapper, "decodeVaaStruct", cd, amVaa(), true),
        (Vaa)
      ),
      amVaaVm()
    );
  }
  function testDecodingAmVaaStruct() public { runBoth(decodingAmVaaStruct); }

  function decodingAmPayload(bool cd) internal {
    CoreBridgeVM memory vm = abi.decode(
      callWithBytes(vaaLibWrapper, "decodeVmStruct", cd, amVaa(), true),
      (CoreBridgeVM)
    );

    compareVms(vm, amVaaVm());

    TokenBridgeAttestMeta memory transfer = abi.decode(
      callWithBytes(tbLibWrapper, "decodeAttestMetaStruct", cd, vm.payload, true),
      (TokenBridgeAttestMeta)
    );
    TokenBridgeAttestMeta memory expected = decodedAmStruct();

    assertEq(transfer.tokenAddress, expected.tokenAddress);
    assertEq(transfer.tokenChainId, expected.tokenChainId);
    assertEq(transfer.decimals, expected.decimals);
    assertEq(transfer.symbol, expected.symbol);
    assertEq(transfer.name, expected.name);
  }
  function testDecodingAmPayload() public { runBoth(decodingAmPayload); }

  function decodingEmitterChainAndPayload(bool cd) internal {
    uint16 emitterChainId;
    bytes memory payload;
    (emitterChainId, payload) = abi.decode(
      callWithBytes(vaaLibWrapper, "decodeEmitterChainAndPayload", cd, true, amVaa(), true),
      (uint16, bytes)
    );

    assertEq(emitterChainId, amVaaVm().emitterChainId);
    assertEq(payload, amVaaVm().payload);
  }
  function testDecodingEmitterChainAndPayload() public { runBoth(decodingEmitterChainAndPayload); }
}
