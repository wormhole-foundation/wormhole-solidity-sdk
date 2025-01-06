// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import "forge-std/Test.sol";


import "wormhole-sdk/libraries/QueryResponse.sol";
import "wormhole-sdk/testing/QueryRequestBuilder.sol";
import "wormhole-sdk/testing/WormholeOverride.sol";
import "./generated/QueryResponseTestWrapper.sol";

contract QueryResponseTest is Test {
  using AdvancedWormholeOverride for IWormhole;

  // Some happy case defaults
  uint8 version = 0x01;
  uint16 senderChainId = 0x0000;
  bytes signature = hex"ff0c222dc9e3655ec38e212e9792bf1860356d1277462b6bf747db865caca6fc08e6317b64ee3245264e371146b1d315d38c867fe1f69614368dc4430bb560f200";
  uint32 queryRequestLen = 0x00000053;
  uint8 queryRequestVersion = 0x01;
  uint32 queryRequestNonce = 0xdd9914c6;
  uint8 numPerChainQueries = 0x01;
  bytes perChainQueries = hex"0005010000004600000009307832613631616334020d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000406fdde030d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000418160ddd";
  bytes perChainQueriesInner = hex"00000009307832613631616334020d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000406fdde030d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000418160ddd";
  uint8 numPerChainResponses = 0x01;
  bytes perChainResponses = hex"000501000000b90000000002a61ac4c1adff9f6e180309e7d0d94c063338ddc61c1c4474cd6957c960efe659534d040005ff312e4f90c002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d57726170706564204d6174696300000000000000000000000000000000000000000000200000000000000000000000000000000000000000007ae5649beabeddf889364a";
  bytes perChainResponsesInner = hex"00000009307832613631616334020d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000406fdde030d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000418160ddd";

  bytes solanaAccountSignature = hex"acb1d93cdfe60f9776e3e05d7fafaf9d83a1d14db70317230f6b0b6f3a60708a1a64dddac02d3843f4c516f2509b89454a2e73c360fea47beee1c1a091ff9f3201";
  uint32 solanaAccountQueryRequestLen = 0x00000073;
  uint8 solanaAccountQueryRequestVersion = 0x01;
  uint32 solanaAccountQueryRequestNonce = 0x0000002a;
  uint8 solanaAccountNumPerChainQueries = 0x01;
  bytes solanaAccountPerChainQueries = hex"000104000000660000000966696e616c697a656400000000000000000000000000000000000000000000000002165809739240a0ac03b98440fe8985548e3aa683cd0d4d9df5b5659669faa3019c006c48c8cbf33849cb07a3f936159cc523f9591cb1999abd45890ec5fee9b7";
  bytes solanaAccountPerChainQueriesInner = hex"0000000966696e616c697a656400000000000000000000000000000000000000000000000002165809739240a0ac03b98440fe8985548e3aa683cd0d4d9df5b5659669faa3019c006c48c8cbf33849cb07a3f936159cc523f9591cb1999abd45890ec5fee9b7";
  uint8 solanaAccountNumPerChainResponses = 0x01;
  bytes solanaAccountPerChainResponses = hex"010001040000013f000000000000d85f00060f3e9915ddc03a8de2b1de609020bb0a0dcee594a8c06801619cf9ea2a498b9d910f9a25772b020000000000164d6000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a90000005201000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d0000e8890423c78a09010000000000000000000000000000000000000000000000000000000000000000000000000000000000164d6000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a90000005201000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d01000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000";
  bytes solanaAccountPerChainResponsesInner = hex"000000000000d85f00060f3e9915ddc03a8de2b1de609020bb0a0dcee594a8c06801619cf9ea2a498b9d910f9a25772b020000000000164d6000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a90000005201000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d0000e8890423c78a09010000000000000000000000000000000000000000000000000000000000000000000000000000000000164d6000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a90000005201000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d01000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000";

  bytes solanaPdaSignature = hex"0c8418d81c00aad6283ba3eb30e141ccdd9296e013ca44e5cc713418921253004b93107ba0d858a548ce989e2bca4132e4c2f9a57a9892e3a87a8304cdb36d8f00";
  uint32 solanaPdaQueryRequestLen = 0x0000006b;
  uint8 solanaPdaQueryRequestVersion = 0x01;
  uint32 solanaPdaQueryRequestNonce = 0x0000002b;
  uint8 solanaPdaNumPerChainQueries = 0x01;
  bytes solanaPdaPerChainQueries = hex"010001050000005e0000000966696e616c697a656400000000000008ff000000000000000c00000000000000140102c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa020000000b477561726469616e5365740000000400000000";
  bytes solanaPdaPerChainQueriesInner = hex"0000000966696e616c697a656400000000000008ff000000000000000c00000000000000140102c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa020000000b477561726469616e5365740000000400000000";
  uint8 solanaPdaNumPerChainResponses = 0x01;
  bytes solanaPdaPerChainResponses = hex"0001050000009b00000000000008ff0006115e3f6d7540e05035785e15056a8559815e71343ce31db2abf23f65b19c982b68aee7bf207b014fa9188b339cfd573a0778c5deaeeee94d4bcfb12b345bf8e417e5119dae773efd0000000000116ac000000000000000000002c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa0000001457cd18b7f8a4d91a2da9ab4af05d0fbece2dcd65";
  bytes solanaPdaPerChainResponsesInner = hex"00000000000008ff0006115e3f6d7540e05035785e15056a8559815e71343ce31db2abf23f65b19c982b68aee7bf207b014fa9188b339cfd573a0778c5deaeeee94d4bcfb12b345bf8e417e5119dae773efd0000000000116ac000000000000000000002c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa0000001457cd18b7f8a4d91a2da9ab4af05d0fbece2dcd65";

  address wormhole;
  QueryResponseLibTestWrapper wrapper;

  function _withDataLocationTag(
    string memory functionName,
    bool cd,
    string memory parameters
  ) private pure returns (string memory) {
    return string(abi.encodePacked(functionName, cd ? "Cd" : "Mem", parameters));
  }

  function _verifyQueryResponseRaw(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs
  ) internal view returns (bool success, bytes memory encodedResult) {
    return address(wrapper).staticcall(abi.encodeWithSignature(
      _withDataLocationTag(
        "verifyQueryResponse",
        cd,
        "(address,bytes,(bytes32,bytes32,uint8,uint8)[])"
      ),
      wormhole, resp, sigs
    ));
  }

  function _verifyQueryResponse(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs
  ) internal {
    (bool success, ) = _verifyQueryResponseRaw(cd, resp, sigs);
    assertEq(success, true);
  }

  function _expectRevertVerifyQueryResponse(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs
  ) internal returns (bytes memory encodedResult) {
    bool success;
    (success, encodedResult) = _verifyQueryResponseRaw(cd, resp, sigs);
    assertEq(success, false);
    return encodedResult;
  }

  function _expectRevertVerifyQueryResponse(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs,
    bytes memory expectedRevert
  ) internal {
    bytes memory encodedResult = _expectRevertVerifyQueryResponse(cd, resp, sigs);
    assertEq(encodedResult, expectedRevert);
  }

  function _decodeAndVerifyQueryResponseRaw(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs
  ) internal view returns (bool success, bytes memory encodedResult) {
    return address(wrapper).staticcall(abi.encodeWithSignature(
      _withDataLocationTag(
        "decodeAndVerifyQueryResponse",
        cd,
        "(address,bytes,(bytes32,bytes32,uint8,uint8)[])"
      ),
      wormhole, resp, sigs
    ));
  }

  function _decodeAndVerifyQueryResponse(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs
  ) internal returns (QueryResponse memory) {
    (bool success, bytes memory encodedResult) =
      _decodeAndVerifyQueryResponseRaw(cd, resp, sigs);
    assertEq(success, true);
    return abi.decode(encodedResult, (QueryResponse));
  }

  function _expectRevertDecodeAndVerifyQueryResponse(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs
  ) internal returns (bytes memory encodedResult) {
    bool success;
    (success, encodedResult) = _decodeAndVerifyQueryResponseRaw(cd, resp, sigs);
    assertEq(success, false);
    return encodedResult;
  }

  function _expectRevertDecodeAndVerifyQueryResponse(
    bool cd,
    bytes memory resp,
    GuardianSignature[] memory sigs,
    bytes memory expectedRevert
  ) internal {
    bytes memory encodedResult = _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sigs);
    assertEq(encodedResult, expectedRevert);
  }

  function setUp() public {
    vm.createSelectFork(vm.envString("TEST_RPC_URL"));
    wormhole = vm.envAddress("TEST_WORMHOLE_ADDRESS");
    IWormhole(wormhole).setUpOverride();
    wrapper = new QueryResponseLibTestWrapper();
  }

  function sign(
    bytes memory response
  ) internal view returns (GuardianSignature[] memory signatures) {
    return IWormhole(wormhole).sign(QueryResponseLib.calcPrefixedResponseHashMem(response));
  }

  function concatenateQueryResponseBytesOffChain(
    uint8 _version,
    uint16 _senderChainId,
    bytes memory _signature,
    uint8 _queryRequestVersion,
    uint32 _queryRequestNonce,
    uint8 _numPerChainQueries,
    bytes memory _perChainQueries,
    uint8 _numPerChainResponses,
    bytes memory _perChainResponses
  ) internal pure returns (bytes memory){
    bytes memory queryRequest = QueryRequestBuilder.buildOffChainQueryRequestBytes(
      _queryRequestVersion,
      _queryRequestNonce,
      _numPerChainQueries,
      _perChainQueries
    );
    return QueryRequestBuilder.buildQueryResponseBytes(
      _version,
      _senderChainId,
      _signature,
      queryRequest,
      _numPerChainResponses,
      _perChainResponses
    );
  }

  function test_calcPrefixedResponseHash(bool cd) public {
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);

    (bool success, bytes memory encodedResult) =
      address(wrapper).call(abi.encodeWithSignature(
        _withDataLocationTag("calcPrefixedResponseHash", cd, "(bytes)"),
        resp
      ));
    assertEq(success, true);
    bytes32 digest = abi.decode(encodedResult, (bytes32));
    bytes32 expectedDigest = 0x5b84b19c68ee0b37899230175a92ee6eda4c5192e8bffca1d057d811bb3660e2;
    assertEq(digest, expectedDigest);
  }

  function test_verifyQueryResponse(bool cd) public {
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    _verifyQueryResponse(cd, resp, sign(resp));
  }

  function test_decodeAndVerifyQueryResponse(bool cd) public {
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    QueryResponse memory r = _decodeAndVerifyQueryResponse(cd, resp, sign(resp));
    assertEq(r.version, 1);
    assertEq(r.senderChainId, 0);
    assertEq(r.requestId, hex"ff0c222dc9e3655ec38e212e9792bf1860356d1277462b6bf747db865caca6fc08e6317b64ee3245264e371146b1d315d38c867fe1f69614368dc4430bb560f200");
    assertEq(r.nonce, 3717797062);
    assertEq(r.responses.length, 1);
    assertEq(r.responses[0].chainId, 5);
    assertEq(r.responses[0].queryType, 1);
    assertEq(r.responses[0].request, hex"00000009307832613631616334020d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000406fdde030d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000418160ddd");
    assertEq(r.responses[0].response, hex"0000000002a61ac4c1adff9f6e180309e7d0d94c063338ddc61c1c4474cd6957c960efe659534d040005ff312e4f90c002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d57726170706564204d6174696300000000000000000000000000000000000000000000200000000000000000000000000000000000000000007ae5649beabeddf889364a");
  }

  function test_decodeEthCallQueryResponse() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 5,
      queryType: 1,
      request: hex"00000009307832613631616334020d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000406fdde030d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000418160ddd",
      response: hex"0000000002a61ac4c1adff9f6e180309e7d0d94c063338ddc61c1c4474cd6957c960efe659534d040005ff312e4f90c002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d57726170706564204d6174696300000000000000000000000000000000000000000000200000000000000000000000000000000000000000007ae5649beabeddf889364a"
    });

    EthCallQueryResponse memory eqr = wrapper.decodeEthCallQueryResponse(r);
    assertEq(eqr.requestBlockId, hex"307832613631616334");
    assertEq(eqr.blockNum, 44440260);
    assertEq(eqr.blockHash, hex"c1adff9f6e180309e7d0d94c063338ddc61c1c4474cd6957c960efe659534d04");
    assertEq(eqr.blockTime, 1687961579000000);
    assertEq(eqr.results.length, 2);

    assertEq(eqr.results[0].contractAddress, address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270));
    assertEq(eqr.results[0].callData, hex"06fdde03");
    assertEq(eqr.results[0].result, hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d57726170706564204d6174696300000000000000000000000000000000000000");

    assertEq(eqr.results[1].contractAddress, address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270));
    assertEq(eqr.results[1].callData, hex"18160ddd");
    assertEq(eqr.results[1].result, hex"0000000000000000000000000000000000000000007ae5649beabeddf889364a");
  }

  function test_decodeEthCallQueryResponseRevertWrongQueryType() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 5,
      queryType: 2,
      request: hex"00000009307832613631616334020d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000406fdde030d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000418160ddd",
      response: hex"0000000002a61ac4c1adff9f6e180309e7d0d94c063338ddc61c1c4474cd6957c960efe659534d040005ff312e4f90c002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d57726170706564204d6174696300000000000000000000000000000000000000000000200000000000000000000000000000000000000000007ae5649beabeddf889364a"
    });

    vm.expectRevert(abi.encodeWithSelector(QueryResponseLib.WrongQueryType.selector, 2, QueryType.ETH_CALL));
    wrapper.decodeEthCallQueryResponse(r);
  }

  function test_decodeEthCallQueryResponseComparison() public {
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 23,
      queryType: 1,
      request: hex"00000009307832376433333433013ce792601c936b1c81f73ea2fa77208c0a478bae00000004916d5743",
      response: hex"00000000027d3343b9848f128b3658a0b9b50aa174e3ddc15ac4e54c84ee534b6d247adbdfc300c90006056cda47a84001000000200000000000000000000000000000000000000000000000000000000000000004"
    });

    EthCallQueryResponse memory eqr = wrapper.decodeEthCallQueryResponse(r);
    assertEq(eqr.requestBlockId, "0x27d3343");
    assertEq(eqr.blockNum, 0x27d3343);
    assertEq(eqr.blockHash, hex"b9848f128b3658a0b9b50aa174e3ddc15ac4e54c84ee534b6d247adbdfc300c9");
    vm.warp(1694814937);
    assertEq(eqr.blockTime / 1_000_000, block.timestamp);
    assertEq(eqr.results.length, 1);

    assertEq(eqr.results[0].contractAddress, address(0x3ce792601c936b1c81f73Ea2fa77208C0A478BaE));
    assertEq(eqr.results[0].callData, hex"916d5743");
    bytes memory callData = eqr.results[0].callData;
    bytes4 callSignature;
    assembly { callSignature := mload(add(callData, 32)) }
    assertEq(callSignature, bytes4(keccak256("getMyCounter()")));
    assertEq(eqr.results[0].result, hex"0000000000000000000000000000000000000000000000000000000000000004");
    assertEq(abi.decode(eqr.results[0].result, (uint256)), 4);
  }

  function test_decodeEthCallByTimestampQueryResponse() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 2,
      queryType: 2,
      request: hex"00000003f4810cc0000000063078343237310000000630783432373202ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000406fdde03ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000418160ddd",
      response: hex"0000000000004271ec70d2f70cf1933770ae760050a75334ce650aa091665ee43a6ed488cd154b0800000003f4810cc000000000000042720b1608c2cddfd9d7fb4ec94f79ec1389e2410e611a2c2bbde94e9ad37519ebbb00000003f4904f0002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
    });

    EthCallByTimestampQueryResponse memory eqr = wrapper.decodeEthCallByTimestampQueryResponse(r);
    assertEq(eqr.requestTargetBlockIdHint, hex"307834323731");
    assertEq(eqr.requestFollowingBlockIdHint, hex"307834323732");
    assertEq(eqr.requestTargetTimestamp, 0x03f4810cc0);
    assertEq(eqr.targetBlockNum, 0x0000000000004271);
    assertEq(eqr.targetBlockHash, hex"ec70d2f70cf1933770ae760050a75334ce650aa091665ee43a6ed488cd154b08");
    assertEq(eqr.targetBlockTime, 0x03f4810cc0);
    assertEq(eqr.followingBlockNum, 0x0000000000004272);
    assertEq(eqr.followingBlockHash, hex"0b1608c2cddfd9d7fb4ec94f79ec1389e2410e611a2c2bbde94e9ad37519ebbb");
    assertEq(eqr.followingBlockTime, 0x03f4904f00);
    assertEq(eqr.results.length, 2);

    assertEq(eqr.results[0].contractAddress, address(0xDDb64fE46a91D46ee29420539FC25FD07c5FEa3E));
    assertEq(eqr.results[0].callData, hex"06fdde03");
    assertEq(eqr.results[0].result, hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000");

    assertEq(eqr.results[1].contractAddress, address(0xDDb64fE46a91D46ee29420539FC25FD07c5FEa3E));
    assertEq(eqr.results[1].callData, hex"18160ddd");
    assertEq(eqr.results[1].result, hex"0000000000000000000000000000000000000000000000000000000000000000");
  }

  function test_decodeEthCallByTimestampQueryResponseRevertWrongQueryType() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 2,
      queryType: 1,
      request: hex"00000003f4810cc0000000063078343237310000000630783432373202ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000406fdde03ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000418160ddd",
      response: hex"0000000000004271ec70d2f70cf1933770ae760050a75334ce650aa091665ee43a6ed488cd154b0800000003f4810cc000000000000042720b1608c2cddfd9d7fb4ec94f79ec1389e2410e611a2c2bbde94e9ad37519ebbb00000003f4904f0002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
    });

    vm.expectRevert(abi.encodeWithSelector(QueryResponseLib.WrongQueryType.selector, 1, QueryType.ETH_CALL_BY_TIMESTAMP));
    wrapper.decodeEthCallByTimestampQueryResponse(r);
  }

  function test_decodeEthCallWithFinalityQueryResponse() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 2,
      queryType: 3,
      request: hex"000000063078363032390000000966696e616c697a656402ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000406fdde03ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000418160ddd",
      response: hex"00000000000060299eb9c56ffdae81214867ed217f5ab37e295c196b4f04b23a795d3e4aea6ff3d700000005bb1bd58002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
    });

    EthCallWithFinalityQueryResponse memory eqr = wrapper.decodeEthCallWithFinalityQueryResponse(r);
    assertEq(eqr.requestBlockId, hex"307836303239");
    assertEq(eqr.requestFinality, hex"66696e616c697a6564");
    assertEq(eqr.blockNum, 0x6029);
    assertEq(eqr.blockHash, hex"9eb9c56ffdae81214867ed217f5ab37e295c196b4f04b23a795d3e4aea6ff3d7");
    assertEq(eqr.blockTime, 0x05bb1bd580);
    assertEq(eqr.results.length, 2);

    assertEq(eqr.results[0].contractAddress, address(0xDDb64fE46a91D46ee29420539FC25FD07c5FEa3E));
    assertEq(eqr.results[0].callData, hex"06fdde03");
    assertEq(eqr.results[0].result, hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000");

    assertEq(eqr.results[1].contractAddress, address(0xDDb64fE46a91D46ee29420539FC25FD07c5FEa3E));
    assertEq(eqr.results[1].callData, hex"18160ddd");
    assertEq(eqr.results[1].result, hex"0000000000000000000000000000000000000000000000000000000000000000");
  }

  function test_decodeEthCallWithFinalityQueryResponseRevertWrongQueryType() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 2,
      queryType: 1,
      request: hex"000000063078363032390000000966696e616c697a656402ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000406fdde03ddb64fe46a91d46ee29420539fc25fd07c5fea3e0000000418160ddd",
      response: hex"00000000000060299eb9c56ffdae81214867ed217f5ab37e295c196b4f04b23a795d3e4aea6ff3d700000005bb1bd58002000000600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000d5772617070656420457468657200000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
    });

    vm.expectRevert(abi.encodeWithSelector(
      QueryResponseLib.WrongQueryType.selector,
      1,
      QueryType.ETH_CALL_WITH_FINALITY
    ));
    wrapper.decodeEthCallWithFinalityQueryResponse(r);
  }

  // Start of Solana Stuff ///////////////////////////////////////////////////////////////////////////

  function test_verifyQueryResponseForSolana(bool cd) public {
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, solanaAccountSignature, solanaAccountQueryRequestVersion, solanaAccountQueryRequestNonce, solanaAccountNumPerChainQueries, solanaAccountPerChainQueries, solanaAccountNumPerChainResponses, solanaAccountPerChainResponses);
    _verifyQueryResponse(cd, resp, sign(resp));
  }

  function test_decodeSolanaAccountQueryResponse() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 4,
      request: solanaAccountPerChainQueriesInner,
      response: solanaAccountPerChainResponsesInner
    });

    SolanaAccountQueryResponse memory sar = wrapper.decodeSolanaAccountQueryResponse(r);

    assertEq(sar.requestCommitment, "finalized");
    assertEq(sar.requestMinContextSlot, 0);
    assertEq(sar.requestDataSliceOffset, 0);
    assertEq(sar.requestDataSliceLength, 0);
    assertEq(sar.slotNumber, 0xd85f);
    assertEq(sar.blockTime, 0x00060f3e9915ddc0);
    assertEq(sar.blockHash, hex"3a8de2b1de609020bb0a0dcee594a8c06801619cf9ea2a498b9d910f9a25772b");
    assertEq(sar.results.length, 2);

    assertEq(sar.results[0].account, hex"165809739240a0ac03b98440fe8985548e3aa683cd0d4d9df5b5659669faa301");
    assertEq(sar.results[0].lamports, 0x164d60);
    assertEq(sar.results[0].rentEpoch, 0);
    assertEq(sar.results[0].executable, false);
    assertEq(sar.results[0].owner, hex"06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9");
    assertEq(sar.results[0].data, hex"01000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d0000e8890423c78a0901000000000000000000000000000000000000000000000000000000000000000000000000");

    assertEq(sar.results[1].account, hex"9c006c48c8cbf33849cb07a3f936159cc523f9591cb1999abd45890ec5fee9b7");
    assertEq(sar.results[1].lamports, 0x164d60);
    assertEq(sar.results[1].rentEpoch, 0);
    assertEq(sar.results[1].executable, false);
    assertEq(sar.results[1].owner, hex"06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9");
    assertEq(sar.results[1].data, hex"01000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d01000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000");
  }

  function test_decodeSolanaAccountQueryResponseRevertWrongQueryType() public {
    // Pass an ETH per chain response into the Solana decoder.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 2,
      queryType: 1,
      request: solanaAccountPerChainQueriesInner,
      response: solanaAccountPerChainResponsesInner
    });

    vm.expectRevert(abi.encodeWithSelector(
      QueryResponseLib.WrongQueryType.selector,
      1,
      QueryType.SOLANA_ACCOUNT
    ));
    wrapper.decodeSolanaAccountQueryResponse(r);
  }

  function test_decodeSolanaAccountQueryResponseRevertUnexpectedNumberOfResults() public {
    // Only one account on the request but two in the response.
    bytes memory requestWithOnlyOneAccount = hex"0000000966696e616c697a656400000000000000000000000000000000000000000000000001165809739240a0ac03b98440fe8985548e3aa683cd0d4d9df5b5659669faa301";
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 4,
      request: requestWithOnlyOneAccount,
      response: solanaAccountPerChainResponsesInner
    });

    vm.expectRevert(QueryResponseLib.UnexpectedNumberOfResults.selector);
    wrapper.decodeSolanaAccountQueryResponse(r);
  }

  function test_decodeSolanaAccountQueryResponseExtraRequestBytesRevertInvalidPayloadLength() public {
    // Extra bytes at the end of the request.
    bytes memory requestWithExtraBytes = hex"0000000966696e616c697a656400000000000000000000000000000000000000000000000002165809739240a0ac03b98440fe8985548e3aa683cd0d4d9df5b5659669faa3019c006c48c8cbf33849cb07a3f936159cc523f9591cb1999abd45890ec5fee9b7DEADBEEF";
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 4,
      request: requestWithExtraBytes,
      response: solanaAccountPerChainResponsesInner
    });

    vm.expectRevert(abi.encodeWithSelector(
      QueryResponseLib.InvalidPayloadLength.selector,
      106,
      102
    ));
    wrapper.decodeSolanaAccountQueryResponse(r);
  }

  function test_decodeSolanaAccountQueryResponseExtraResponseBytesRevertInvalidPayloadLength() public {
    // Extra bytes at the end of the response.
    bytes memory responseWithExtraBytes = hex"000000000000d85f00060f3e9915ddc03a8de2b1de609020bb0a0dcee594a8c06801619cf9ea2a498b9d910f9a25772b020000000000164d6000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a90000005201000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d0000e8890423c78a09010000000000000000000000000000000000000000000000000000000000000000000000000000000000164d6000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a90000005201000000574108aed69daf7e625a361864b1f74d13702f2ca56de9660e566d1d8691848d01000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000DEADBEEF";
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 4,
      request: solanaAccountPerChainQueriesInner,
      response: responseWithExtraBytes
    });

    vm.expectRevert(abi.encodeWithSelector(
      QueryResponseLib.InvalidPayloadLength.selector,
      323,
      319
    ));
    wrapper.decodeSolanaAccountQueryResponse(r);
  }

  function test_decodeSolanaPdaQueryResponse() public {
    // Take the data extracted by the previous test and break it down even further.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 5,
      request: solanaPdaPerChainQueriesInner,
      response: solanaPdaPerChainResponsesInner
    });

    SolanaPdaQueryResponse memory sar = wrapper.decodeSolanaPdaQueryResponse(r);

    assertEq(sar.requestCommitment, "finalized");
    assertEq(sar.requestMinContextSlot, 2303);
    assertEq(sar.requestDataSliceOffset, 12);
    assertEq(sar.requestDataSliceLength, 20);
    assertEq(sar.slotNumber, 2303);
    assertEq(sar.blockTime, 0x0006115e3f6d7540);
    assertEq(sar.blockHash, hex"e05035785e15056a8559815e71343ce31db2abf23f65b19c982b68aee7bf207b");
    assertEq(sar.results.length, 1);

    assertEq(sar.results[0].programId, hex"02c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa");
    assertEq(sar.results[0].seeds.length, 2);
    assertEq(sar.results[0].seeds[0], hex"477561726469616e536574");
    assertEq(sar.results[0].seeds[1], hex"00000000");

    assertEq(sar.results[0].account, hex"4fa9188b339cfd573a0778c5deaeeee94d4bcfb12b345bf8e417e5119dae773e");
    assertEq(sar.results[0].bump, 253);
    assertEq(sar.results[0].lamports, 0x116ac0);
    assertEq(sar.results[0].rentEpoch, 0);
    assertEq(sar.results[0].executable, false);
    assertEq(sar.results[0].owner, hex"02c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa");
    assertEq(sar.results[0].data, hex"57cd18b7f8a4d91a2da9ab4af05d0fbece2dcd65");
  }

  function test_decodeSolanaPdaQueryResponseRevertWrongQueryType() public {
    // Pass an ETH per chain response into the Solana decoder.
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 2,
      queryType: 1,
      request: solanaPdaPerChainQueriesInner,
      response: solanaPdaPerChainResponsesInner
    });

    vm.expectRevert(abi.encodeWithSelector(
      QueryResponseLib.WrongQueryType.selector,
      1,
      QueryType.SOLANA_PDA
    ));
    wrapper.decodeSolanaPdaQueryResponse(r);
  }

  function test_decodeSolanaPdaQueryResponseRevertUnexpectedNumberOfResults() public {
    // Only one Pda on the request but two in the response.
    bytes memory requestWithTwoPdas = hex"0000000966696e616c697a656400000000000008ff000000000000000c00000000000000140202c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa020000000b477561726469616e536574000000040000000002c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa020000000b477561726469616e5365740000000400000000";
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 5,
      request: requestWithTwoPdas,
      response: solanaPdaPerChainResponsesInner
    });

    vm.expectRevert(QueryResponseLib.UnexpectedNumberOfResults.selector);
    wrapper.decodeSolanaPdaQueryResponse(r);
  }

  function test_decodeSolanaPdaQueryResponseExtraRequestBytesRevertInvalidPayloadLength() public {
    // Extra bytes at the end of the request.
    bytes memory requestWithExtraBytes = hex"0000000966696e616c697a656400000000000008ff000000000000000c00000000000000140102c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa020000000b477561726469616e5365740000000400000000DEADBEEF";
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 5,
      request: requestWithExtraBytes,
      response: solanaPdaPerChainResponsesInner
    });

    vm.expectRevert(abi.encodeWithSelector(
      QueryResponseLib.InvalidPayloadLength.selector,
      98,
      94
    ));
    wrapper.decodeSolanaPdaQueryResponse(r);
  }

  function test_decodeSolanaPdaQueryResponseExtraResponseBytesRevertInvalidPayloadLength() public {
    // Extra bytes at the end of the response.
    bytes memory responseWithExtraBytes = hex"00000000000008ff0006115e3f6d7540e05035785e15056a8559815e71343ce31db2abf23f65b19c982b68aee7bf207b014fa9188b339cfd573a0778c5deaeeee94d4bcfb12b345bf8e417e5119dae773efd0000000000116ac000000000000000000002c806312cbe5b79ef8aa6c17e3f423d8fdfe1d46909fb1f6cdf65ee8e2e6faa0000001457cd18b7f8a4d91a2da9ab4af05d0fbece2dcd65DEADBEEF";
    PerChainQueryResponse memory r = PerChainQueryResponse({
      chainId: 1,
      queryType: 5,
      request: solanaPdaPerChainQueriesInner,
      response: responseWithExtraBytes
    });

    vm.expectRevert(abi.encodeWithSelector(
      QueryResponseLib.InvalidPayloadLength.selector,
      159,
      155
    ));
    wrapper.decodeSolanaPdaQueryResponse(r);
  }

  /***********************************
  *********** FUZZ TESTS *************
  ***********************************/

  function testFuzz_decodeAndVerifyQueryResponse_version(
    bool cd,
    uint8 _version
  ) public {
    vm.assume(_version != 1);

    bytes memory resp = concatenateQueryResponseBytesOffChain(_version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    bytes memory expectedError = abi.encodePacked(QueryResponseLib.InvalidResponseVersion.selector);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp), expectedError);
  }

  function testFuzz_decodeAndVerifyQueryResponse_senderChainId(
    bool cd,
    uint16 _senderChainId
  ) public {
    vm.assume(_senderChainId != 0);

    bytes memory resp = concatenateQueryResponseBytesOffChain(version, _senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    // This could revert for multiple reasons. But the checkLength to ensure all the bytes are consumed is the backstop.
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp));
  }

  function testFuzz_decodeAndVerifyQueryResponse_signatureHappyCase(
    bool cd,
    bytes memory _signature
  ) public {
    // This signature isn't validated in the QueryResponse library, therefore it could be an 65 byte hex string
    vm.assume(_signature.length == 65);

    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, _signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    QueryResponse memory r = _decodeAndVerifyQueryResponse(cd, resp, sign(resp));

    assertEq(r.requestId, _signature);
  }

  function testFuzz_decodeAndVerifyQueryResponse_signatureUnhappyCase(
    bool cd,
    bytes memory _signature
  ) public {
    // A signature that isn't 65 bytes long will always lead to a revert. The type of revert is unknown since it could be one of many.
    vm.assume(_signature.length != 65);

    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, _signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp));
  }

  function testFuzz_decodeAndVerifyQueryResponse_fuzzQueryRequestLen(
    bool cd,
    uint32 _queryRequestLen,
    bytes calldata _perChainQueries
  ) public {
    // We add 6 to account for version + nonce + numPerChainQueries
    vm.assume(_queryRequestLen != _perChainQueries.length + 6);

    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, _perChainQueries, numPerChainResponses, perChainResponses);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp));
  }

  function testFuzz_decodeAndVerifyQueryResponse_queryRequestVersion(
    bool cd,
    uint8 _version,
    uint8 _queryRequestVersion
  ) public {
    vm.assume(_version != _queryRequestVersion);

    bytes memory resp = concatenateQueryResponseBytesOffChain(_version, senderChainId, signature, _queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp));
  }

  function testFuzz_decodeAndVerifyQueryResponse_queryRequestNonce(
    bool cd,
    uint32 _queryRequestNonce
  ) public {
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, _queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    QueryResponse memory r = _decodeAndVerifyQueryResponse(cd, resp, sign(resp));

    assertEq(r.nonce, _queryRequestNonce);
  }

  function testFuzz_decodeAndVerifyQueryResponse_numPerChainQueriesAndResponses(
    bool cd,
    uint8 _numPerChainQueries,
    uint8 _numPerChainResponses
  ) public {
    vm.assume(_numPerChainQueries != _numPerChainResponses);

    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, _numPerChainQueries, perChainQueries, _numPerChainResponses, perChainResponses);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp));
  }

  function testFuzz_decodeAndVerifyQueryResponse_chainIds(
    bool cd,
    uint16 _requestChainId,
    uint16 _responseChainId,
    uint256 _requestQueryType
  ) public {
    vm.assume(_requestChainId != _responseChainId);
    _requestQueryType = bound(_requestQueryType, QueryType.min(), QueryType.max());

    bytes memory packedPerChainQueries = abi.encodePacked(_requestChainId, uint8(_requestQueryType), uint32(perChainQueriesInner.length), perChainQueriesInner);
    bytes memory packedPerChainResponses = abi.encodePacked(_responseChainId, uint8(_requestQueryType), uint32(perChainResponsesInner.length),  perChainResponsesInner);
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, packedPerChainQueries, numPerChainResponses, packedPerChainResponses);
    bytes memory expectedError = abi.encodePacked(QueryResponseLib.ChainIdMismatch.selector);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp), expectedError);
  }

  function testFuzz_decodeAndVerifyQueryResponse_mistmatchedRequestType(
    bool cd,
    uint256 _requestQueryType,
    uint256 _responseQueryType
  ) public {
    _requestQueryType = bound(_requestQueryType, QueryType.min(), QueryType.max());
    _responseQueryType = bound(_responseQueryType, QueryType.min(), QueryType.max());
    vm.assume(_requestQueryType != _responseQueryType);

    bytes memory packedPerChainQueries = abi.encodePacked(uint16(0x0005), uint8(_requestQueryType), uint32(perChainQueriesInner.length), perChainQueriesInner);
    bytes memory packedPerChainResponses = abi.encodePacked(uint16(0x0005), uint8(_responseQueryType), uint32(perChainResponsesInner.length),  perChainResponsesInner);
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, packedPerChainQueries, numPerChainResponses, packedPerChainResponses);
    bytes memory expectedError = abi.encodePacked(QueryResponseLib.RequestTypeMismatch.selector);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp), expectedError);
  }

  function testFuzz_decodeAndVerifyQueryResponse_unsupportedRequestType(
    bool cd,
    uint8 _requestQueryType
  ) public {
    vm.assume(!QueryType.isValid(_requestQueryType));

    bytes memory packedPerChainQueries = abi.encodePacked(uint16(0x0005), uint8(_requestQueryType), uint32(perChainQueriesInner.length), perChainQueriesInner);
    bytes memory packedPerChainResponses = abi.encodePacked(uint16(0x0005), uint8(_requestQueryType), uint32(perChainResponsesInner.length),  perChainResponsesInner);
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, packedPerChainQueries, numPerChainResponses, packedPerChainResponses);
    bytes memory expectedError = abi.encodeWithSelector(
      QueryType.UnsupportedQueryType.selector,
      _requestQueryType
    );
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp), expectedError);
  }

  function testFuzz_decodeAndVerifyQueryResponse_queryBytesLength(
    bool cd,
    uint32 _queryLength
  ) public {
    vm.assume(_queryLength != uint32(perChainQueriesInner.length));

    bytes memory packedPerChainQueries = abi.encodePacked(uint16(0x0005), uint8(0x01), _queryLength, perChainQueriesInner);
    bytes memory packedPerChainResponses = abi.encodePacked(uint16(0x0005), uint8(0x01), uint32(perChainResponsesInner.length),  perChainResponsesInner);
    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, packedPerChainQueries, numPerChainResponses, packedPerChainResponses);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, sign(resp));
  }

  function testFuzz_verifyQueryResponse_validSignature(bool cd, bytes calldata resp) public {
    // This should pass with a valid signature of any payload
    _verifyQueryResponse(cd, resp, sign(resp));
  }

  function testFuzz_verifyQueryResponse_invalidSignature(
    bool cd,
    bytes calldata resp,
    uint8 sigV,
    bytes32 sigR,
    bytes32 sigS,
    uint8 sigIndex
  ) public {
    GuardianSignature[] memory signatures = sign(resp);
    uint sigI = bound(sigIndex, 0, signatures.length-1);
    signatures[sigI] = GuardianSignature(sigR, sigS, sigV, signatures[sigI].guardianIndex);
    bytes memory expectedError = abi.encodePacked(QueryResponseLib.VerificationFailed.selector);
    _expectRevertVerifyQueryResponse(cd, resp, signatures, expectedError);
  }

  function testFuzz_verifyQueryResponse_validSignatureWrongPrefix(
    bool cd,
    bytes calldata responsePrefix
  ) public {
    vm.assume(keccak256(responsePrefix) != keccak256(QueryResponseLib.RESPONSE_PREFIX));

    bytes memory resp = concatenateQueryResponseBytesOffChain(version, senderChainId, signature, queryRequestVersion, queryRequestNonce, numPerChainQueries, perChainQueries, numPerChainResponses, perChainResponses);
    bytes32 responseDigest = keccak256(abi.encodePacked(responsePrefix, keccak256(resp)));

    GuardianSignature[] memory signatures = IWormhole(wormhole).sign(responseDigest);
    bytes memory expectedError = abi.encodePacked(QueryResponseLib.VerificationFailed.selector);
    _expectRevertVerifyQueryResponse(cd, resp, signatures, expectedError);
  }

  function testFuzz_verifyQueryResponse_noQuorum(
    bool cd,
    bytes calldata resp,
    uint8 sigCount
  ) public {
    GuardianSignature[] memory signatures = sign(resp);
    uint sigC = bound(sigCount, 0, signatures.length-1);
    GuardianSignature[] memory signaturesToUse = new GuardianSignature[](sigC);
    for (uint i = 0; i < sigC; ++i)
      signaturesToUse[i] = signatures[i];

    bytes memory expectedError = abi.encodePacked(QueryResponseLib.VerificationFailed.selector);
    _expectRevertDecodeAndVerifyQueryResponse(cd, resp, signaturesToUse, expectedError);
  }

  uint64 constant private MICROSECONDS_PER_SECOND = QueryResponseLib.MICROSECONDS_PER_SECOND;
  uint64 constant private MAX_SECONDS = type(uint64).max/MICROSECONDS_PER_SECOND;

  function testFuzz_validateBlockTime_success(
    uint64 _blockTime,
    uint64 _minBlockTime
  ) public view {
    //assure: blockTime >= minBlockTime
    _minBlockTime = uint64(bound(_minBlockTime, 0, MAX_SECONDS));
    _blockTime = uint64(bound(_blockTime, _minBlockTime, MAX_SECONDS));

    wrapper.validateBlockTime(_blockTime * MICROSECONDS_PER_SECOND, _minBlockTime);
  }

  function testFuzz_validateBlockTime_fail(
    uint64 _blockTime,
    uint256 _minBlockTime
  ) public {
    //assure: blockTime < minBlockTime
    vm.assume(_minBlockTime > 0);
    uint upperBound = _minBlockTime <= MAX_SECONDS ? _minBlockTime-1 : MAX_SECONDS;
    _blockTime = uint64(bound(_blockTime, 0, upperBound));

    vm.expectRevert(QueryResponseLib.StaleBlockTime.selector);
    wrapper.validateBlockTime(_blockTime * MICROSECONDS_PER_SECOND, _minBlockTime);
  }

  function testFuzz_validateBlockNum_success(
    uint64 _blockNum,
    uint64 _minBlockNum
  ) public view {
    //assure: blockNum >= minBlockNum
    _blockNum = uint64(bound(_blockNum, _minBlockNum, type(uint64).max));

    wrapper.validateBlockNum(_blockNum, _minBlockNum);
  }

  function testFuzz_validateBlockNum_fail(
    uint64 _blockNum,
    uint64 _minBlockNum
  ) public {
    //assure: blockNum < minBlockNum
    vm.assume(_minBlockNum > 0);
    _blockNum = uint64(bound(_blockNum, 0, _minBlockNum-1));

    vm.expectRevert(QueryResponseLib.StaleBlockNum.selector);
    wrapper.validateBlockNum(uint64(_blockNum), _minBlockNum);
  }

  function testFuzz_validateChainId_success(
    uint256 _validChainIndex,
    uint16[] memory _validChainIds
  ) public view {
    vm.assume(_validChainIds.length > 0);
    _validChainIndex %= _validChainIds.length;

    wrapper.validateChainId(_validChainIds[_validChainIndex], _validChainIds);
  }

  function testFuzz_validateChainId_fail(
    uint16 _chainId,
    uint16[] memory _validChainIds
  ) public {
    for (uint16 i = 0; i < _validChainIds.length; ++i)
      vm.assume(_chainId != _validChainIds[i]);

    vm.expectRevert(QueryResponseLib.InvalidChainId.selector);
    wrapper.validateChainId(_chainId, _validChainIds);
  }

  function testFuzz_validateEthCallRecord_success(
    bytes memory randomBytes,
    uint256 _contractAddressIndex,
    uint256 _functionSignatureIndex,
    address[] memory _validContractAddresses,
    bytes4[] memory _validFunctionSignatures
  ) public view {
    vm.assume(randomBytes.length >= 4);
    vm.assume(_validContractAddresses.length > 0);
    _contractAddressIndex %= _validContractAddresses.length;
    vm.assume(_validFunctionSignatures.length > 0);
    _functionSignatureIndex %= _validFunctionSignatures.length;

    EthCallRecord memory callData = EthCallRecord({
      contractAddress: _validContractAddresses[_contractAddressIndex],
      callData: bytes.concat(_validFunctionSignatures[_functionSignatureIndex], randomBytes),
      result: randomBytes
    });

    wrapper.validateEthCallRecord(callData, _validContractAddresses, _validFunctionSignatures);
  }

  function testFuzz_validateEthCallRecord_successZeroSignatures(
    bytes4 randomSignature,
    bytes memory randomBytes,
    uint256 _contractAddressIndex,
    address[] memory _validContractAddresses
  ) public view {
    vm.assume(_validContractAddresses.length > 0);
    _contractAddressIndex %= _validContractAddresses.length;

    EthCallRecord memory callData = EthCallRecord({
      contractAddress: _validContractAddresses[_contractAddressIndex],
      callData: bytes.concat(randomSignature, randomBytes),
      result: randomBytes
    });

    bytes4[] memory validSignatures = new bytes4[](0);

    wrapper.validateEthCallRecord(callData, _validContractAddresses, validSignatures);
  }

  function testFuzz_validateEthCallRecord_successZeroAddresses(
    address randomAddress,
    bytes memory randomBytes,
    uint256 _functionSignatureIndex,
    bytes4[] memory _validFunctionSignatures
  ) public view {
    vm.assume(randomBytes.length >= 4);
    vm.assume(_validFunctionSignatures.length > 0);
    _functionSignatureIndex %= _validFunctionSignatures.length;

    EthCallRecord memory callData = EthCallRecord({
      contractAddress: randomAddress,
      callData: bytes.concat(_validFunctionSignatures[_functionSignatureIndex], randomBytes),
      result: randomBytes
    });

    address[] memory validAddresses = new address[](0);

    wrapper.validateEthCallRecord(callData, validAddresses, _validFunctionSignatures);
  }

  function testFuzz_validateEthCallRecord_failSignature(
    bytes memory randomBytes,
    uint256 _contractAddressIndex,
    address[] memory _validContractAddresses,
    bytes4[] memory _validFunctionSignatures
  ) public {
    vm.assume(randomBytes.length >= 4);
    vm.assume(_validContractAddresses.length > 0);
    _contractAddressIndex %= _validContractAddresses.length;
    vm.assume(_validFunctionSignatures.length > 0);

    for (uint i = 0; i < _validFunctionSignatures.length; ++i)
      vm.assume(bytes4(randomBytes) != _validFunctionSignatures[i]);

    EthCallRecord memory callData = EthCallRecord({
      contractAddress: _validContractAddresses[_contractAddressIndex],
      callData: randomBytes,
      result: randomBytes
    });

    vm.expectRevert(QueryResponseLib.InvalidFunctionSignature.selector);
    wrapper.validateEthCallRecord(callData, _validContractAddresses, _validFunctionSignatures);
  }

  function testFuzz_validateEthCallRecord_failAddress(
    bytes memory randomBytes,
    address randomAddress,
    uint256 _functionSignatureIndex,
    address[] memory _validContractAddresses,
    bytes4[] memory _validFunctionSignatures
  ) public {
    vm.assume(_validFunctionSignatures.length > 0);
    _functionSignatureIndex %= _validFunctionSignatures.length;
    vm.assume(_validContractAddresses.length > 0);

    for (uint i = 0; i < _validContractAddresses.length; ++i)
      vm.assume(randomAddress != _validContractAddresses[i]);

    EthCallRecord memory callData = EthCallRecord({
      contractAddress: randomAddress,
      callData: bytes.concat(_validFunctionSignatures[_functionSignatureIndex], randomBytes),
      result: randomBytes
    });

    vm.expectRevert(QueryResponseLib.InvalidContractAddress.selector);
    wrapper.validateEthCallRecord(callData, _validContractAddresses, _validFunctionSignatures);
  }

  function testFuzz_validateMultipleEthCallRecord_success(
    uint8 numInputs,
    bytes memory randomBytes,
    uint256 _contractAddressIndex,
    uint256 _functionSignatureIndex,
    address[] memory _validContractAddresses,
    bytes4[] memory _validFunctionSignatures
  ) public view {
    vm.assume(_validContractAddresses.length > 0);
    _contractAddressIndex %= _validContractAddresses.length;
    vm.assume(_validFunctionSignatures.length > 0);
    _functionSignatureIndex %= _validFunctionSignatures.length;

    EthCallRecord[] memory callDatas = new EthCallRecord[](numInputs);

    for (uint i = 0; i < numInputs; ++i)
      callDatas[i] = EthCallRecord({
        contractAddress: _validContractAddresses[_contractAddressIndex],
        callData: bytes.concat(_validFunctionSignatures[_functionSignatureIndex], randomBytes),
        result: randomBytes
      });

    wrapper.validateEthCallRecord(callDatas, _validContractAddresses, _validFunctionSignatures);
  }
}
