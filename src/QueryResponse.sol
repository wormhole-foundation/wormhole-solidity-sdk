// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing} from "./libraries/BytesParsing.sol";
import {IWormhole} from "./interfaces/IWormhole.sol";

struct QueryResponse {
  uint8 version;
  uint16 senderChainId;
  uint32 nonce;
  bytes requestId; // 65 byte sig for off-chain, 32 byte vaaHash for on-chain
  PerChainQueryResponse [] responses;
}

struct PerChainQueryResponse {
  uint16 chainId;
  uint8 queryType;
  bytes request;
  bytes response;
}

struct EthCallQueryResponse {
  bytes requestBlockId;
  uint64 blockNum;
  uint64 blockTime;
  bytes32 blockHash;
  EthCallData [] result;
}

struct EthCallByTimestampQueryResponse {
  bytes requestTargetBlockIdHint;
  bytes requestFollowingBlockIdHint;
  uint64 requestTargetTimestamp;
  uint64 targetBlockNum;
  uint64 targetBlockTime;
  uint64 followingBlockNum;
  bytes32 targetBlockHash;
  bytes32 followingBlockHash;
  uint64 followingBlockTime;
  EthCallData [] result;
}

struct EthCallWithFinalityQueryResponse {
  bytes requestBlockId;
  bytes requestFinality;
  uint64 blockNum;
  uint64 blockTime;
  bytes32 blockHash;
  EthCallData [] result;
}

struct EthCallData {
  address contractAddress;
  bytes callData;
  bytes result;
}

struct SolanaAccountQueryResponse {
  bytes requestCommitment;
  uint64 requestMinContextSlot;
  uint64 requestDataSliceOffset;
  uint64 requestDataSliceLength;
  uint64 slotNumber;
  uint64 blockTime;
  bytes32 blockHash;
  SolanaAccountResult [] results;
}

struct SolanaAccountResult {
  bytes32 account;
  uint64 lamports;
  uint64 rentEpoch;
  bool executable;
  bytes32 owner;
  bytes data;
}

struct SolanaPdaQueryResponse {
  bytes requestCommitment;
  uint64 requestMinContextSlot;
  uint64 requestDataSliceOffset;
  uint64 requestDataSliceLength;
  uint64 slotNumber;
  uint64 blockTime;
  bytes32 blockHash;
  SolanaPdaResult [] results;
}

struct SolanaPdaResult {
  bytes32 programId;
  bytes[] seeds;
  bytes32 account;
  uint64 lamports;
  uint64 rentEpoch;
  bool executable;
  bytes32 owner;
  bytes data;
  uint8 bump;
}

// Custom errors
error UnsupportedQueryType(uint8 received);
error WrongQueryType(uint8 received, uint8 expected);
error InvalidResponseVersion();
error VersionMismatch();
error ZeroQueries();
error NumberOfResponsesMismatch();
error ChainIdMismatch();
error RequestTypeMismatch();
error UnexpectedNumberOfResults();
error InvalidPayloadLength(uint256 received, uint256 expected);
error InvalidContractAddress();
error InvalidFunctionSignature();
error InvalidChainId();
error StaleBlockNum();
error StaleBlockTime();
error NoQuorum();
error VerificationFailed();

library QueryType {
  //Deliberately not using an enum because failed enum casts result in a Panic and a custom
  //  conversion before the cast produces inefficient bytecode (duplicated range checking).
  uint8 internal constant ETH_CALL = 1;
  uint8 internal constant ETH_CALL_BY_TIMESTAMP = 2;
  uint8 internal constant ETH_CALL_WITH_FINALITY = 3;
  uint8 internal constant SOL_ACCOUNT = 4;
  uint8 internal constant SOL_PDA = 5;

  uint8 internal constant MAX_QT = 5;

  function isValid(uint8 queryType) internal pure returns (bool) {
    return (queryType > 0 && queryType < (MAX_QT + 1));
  }

  function checkValid(uint8 queryType) internal pure {
    if (queryType == 0 || queryType > MAX_QT)
      revert UnsupportedQueryType(queryType);
  }
}

//QueryResponse is a library that implements the parsing and verification of
//  Cross Chain Query (CCQ) responses.
//
//For a detailed discussion of these query responses, please see the white paper:
//  https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0013_ccq.md
library QueryResponseLib {
  using BytesParsing for bytes;

  bytes internal constant RESPONSE_PREFIX = bytes("query_response_0000000000000000000|");
  uint8 internal constant VERSION = 1;

  function calcResponseDigest(bytes memory response) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(RESPONSE_PREFIX, keccak256(response)));
  }

  function parseAndVerifyQueryResponse(
    address wormhole,
    bytes memory response,
    IWormhole.Signature[] memory signatures
  ) internal view returns (QueryResponse memory ret) {
    verifyQueryResponse(wormhole, response, signatures);
    return parseQueryResponse(response);
  }

  function verifyQueryResponse(
    address wormhole,
    bytes memory response,
    IWormhole.Signature[] memory signatures
  ) internal view { unchecked {
    IWormhole wormhole_ = IWormhole(wormhole);
    IWormhole.GuardianSet memory guardianSet =
      wormhole_.getGuardianSet(wormhole_.getCurrentGuardianSetIndex());
    uint quorum = guardianSet.keys.length * 2 / 3 + 1;
    if (signatures.length < quorum)
      revert NoQuorum();

    (bool signaturesValid, ) =
      wormhole_.verifySignatures(calcResponseDigest(response), signatures, guardianSet);
    if(!signaturesValid)
      revert VerificationFailed();
  }}
  
  function parseQueryResponse(
    bytes memory response
  ) internal pure returns (QueryResponse memory ret) { unchecked {
    uint offset;

    (ret.version, offset) = response.asUint8Unchecked(offset);
    if (ret.version != VERSION)
      revert InvalidResponseVersion();

    (ret.senderChainId, offset) = response.asUint16Unchecked(offset);

    //For off chain requests (chainID zero), the requestId is the 65 byte signature.
    //For on chain requests, it is the 32 byte VAA hash.
    (ret.requestId, offset) = response.sliceUnchecked(offset, ret.senderChainId == 0 ? 65 : 32);

    uint32 queryReqLen;
    (queryReqLen, offset) = response.asUint32Unchecked(offset);
    uint reqOff = offset;

    {
      uint8 version;
      (version, reqOff) = response.asUint8Unchecked(reqOff);
      if (version != ret.version)
        revert VersionMismatch();
    }

    (ret.nonce, reqOff) = response.asUint32Unchecked(reqOff);

    uint8 numPerChainQueries;
    (numPerChainQueries, reqOff) = response.asUint8Unchecked(reqOff);

    //A valid query request has at least one per chain query
    if (numPerChainQueries == 0)
      revert ZeroQueries();

    //The response starts after the request.
    uint respOff = offset + queryReqLen;
    uint startOfResponse = respOff;

    uint8 respNumPerChainQueries;
    (respNumPerChainQueries, respOff) = response.asUint8Unchecked(respOff);
    if (respNumPerChainQueries != numPerChainQueries)
      revert NumberOfResponsesMismatch();

    ret.responses = new PerChainQueryResponse[](numPerChainQueries);

    //Walk through the requests and responses in lock step.
    for (uint i; i < numPerChainQueries; ++i) {
      (ret.responses[i].chainId, reqOff) = response.asUint16Unchecked(reqOff);
      uint16 respChainId;
      (respChainId, respOff) = response.asUint16Unchecked(respOff);
      if (respChainId != ret.responses[i].chainId)
        revert ChainIdMismatch();

      (ret.responses[i].queryType, reqOff) = response.asUint8Unchecked(reqOff);
      QueryType.checkValid(ret.responses[i].queryType);
      uint8 respQueryType;
      (respQueryType, respOff) = response.asUint8Unchecked(respOff);
      if (respQueryType != ret.responses[i].queryType)
        revert RequestTypeMismatch();

      (ret.responses[i].request, reqOff) = response.sliceUint32PrefixedUnchecked(reqOff);

      (ret.responses[i].response, respOff) = response.sliceUint32PrefixedUnchecked(respOff);
    }

    //End of request body should align with start of response body
    if (startOfResponse != reqOff)
      revert InvalidPayloadLength(startOfResponse, reqOff);

    checkLength(response, respOff);
    return ret;
  }}

  function parseEthCallQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (EthCallQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.ETH_CALL)
      revert WrongQueryType(pcr.queryType, QueryType.ETH_CALL);

    uint reqOff;
    uint respOff;

    uint8 numBatchCallData;
    (ret.requestBlockId, reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
    (numBatchCallData,   reqOff) = pcr.request.asUint8Unchecked(reqOff);

    uint8 respNumResults;
    (ret.blockNum,   respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32Unchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64Unchecked(respOff);
    (respNumResults, respOff) = pcr.response.asUint8Unchecked(respOff);

    if (respNumResults != numBatchCallData)
      revert UnexpectedNumberOfResults();

    ret.result = new EthCallData[](numBatchCallData);

    //Walk through the call data and results in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      (ret.result[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.result[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.result[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
    return ret;
  }}

  function parseEthCallByTimestampQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (EthCallByTimestampQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.ETH_CALL_BY_TIMESTAMP)
      revert WrongQueryType(pcr.queryType, QueryType.ETH_CALL_BY_TIMESTAMP);

    uint reqOff;
    uint respOff;

    uint8 numBatchCallData;
    (ret.requestTargetTimestamp,      reqOff) = pcr.request.asUint64Unchecked(reqOff);
    (ret.requestTargetBlockIdHint,    reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
    (ret.requestFollowingBlockIdHint, reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
    (numBatchCallData,                reqOff) = pcr.request.asUint8Unchecked(reqOff);

    uint8 respNumResults;
    (ret.targetBlockNum,     respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.targetBlockHash,    respOff) = pcr.response.asBytes32Unchecked(respOff);
    (ret.targetBlockTime,    respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.followingBlockNum,  respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.followingBlockHash, respOff) = pcr.response.asBytes32Unchecked(respOff);
    (ret.followingBlockTime, respOff) = pcr.response.asUint64Unchecked(respOff);
    (respNumResults,         respOff) = pcr.response.asUint8Unchecked(respOff);

    if (respNumResults != numBatchCallData)
      revert UnexpectedNumberOfResults();

    ret.result = new EthCallData[](numBatchCallData);

    // Walk through the call data and results in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      (ret.result[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.result[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.result[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }}

  function parseEthCallWithFinalityQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (EthCallWithFinalityQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.ETH_CALL_WITH_FINALITY)
      revert WrongQueryType(pcr.queryType, QueryType.ETH_CALL_WITH_FINALITY);

    uint reqOff;
    uint respOff;

    uint8 numBatchCallData;
    (ret.requestBlockId,  reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
    (ret.requestFinality, reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
    (numBatchCallData,    reqOff) = pcr.request.asUint8Unchecked(reqOff);

    uint8 respNumResults;
    (ret.blockNum,   respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32Unchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64Unchecked(respOff);
    (respNumResults, respOff) = pcr.response.asUint8Unchecked(respOff);

    if (respNumResults != numBatchCallData)
      revert UnexpectedNumberOfResults();

    ret.result = new EthCallData[](numBatchCallData);

    //Walk through the call data and results in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      (ret.result[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.result[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.result[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }}

  function parseSolanaAccountQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (SolanaAccountQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.SOL_ACCOUNT)
      revert WrongQueryType(pcr.queryType, QueryType.SOL_ACCOUNT);

    uint reqOff;
    uint respOff;

    uint8 numAccounts;
    (ret.requestCommitment,      reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
    (ret.requestMinContextSlot,  reqOff) = pcr.request.asUint64Unchecked(reqOff);
    (ret.requestDataSliceOffset, reqOff) = pcr.request.asUint64Unchecked(reqOff);
    (ret.requestDataSliceLength, reqOff) = pcr.request.asUint64Unchecked(reqOff);
    (numAccounts,                reqOff) = pcr.request.asUint8Unchecked(reqOff);

    uint8 respNumResults;
    (ret.slotNumber, respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32Unchecked(respOff);
    (respNumResults, respOff) = pcr.response.asUint8Unchecked(respOff);

    if (respNumResults != numAccounts)
      revert UnexpectedNumberOfResults();

    ret.results = new SolanaAccountResult[](numAccounts);

    //Walk through the call data and results in lock step.
    for (uint i; i < numAccounts; ++i) {
      (ret.results[i].account, reqOff) = pcr.request.asBytes32Unchecked(reqOff);

      (ret.results[i].lamports,   respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].rentEpoch,  respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].executable, respOff) = pcr.response.asBoolUnchecked(respOff);
      (ret.results[i].owner,      respOff) = pcr.response.asBytes32Unchecked(respOff);
      (ret.results[i].data,       respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }}

  function parseSolanaPdaQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (SolanaPdaQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.SOL_PDA)
      revert WrongQueryType(pcr.queryType, QueryType.SOL_PDA);

    uint reqOff;
    uint respOff;

    (ret.requestCommitment,      reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
    (ret.requestMinContextSlot,  reqOff) = pcr.request.asUint64Unchecked(reqOff);
    (ret.requestDataSliceOffset, reqOff) = pcr.request.asUint64Unchecked(reqOff);
    (ret.requestDataSliceLength, reqOff) = pcr.request.asUint64Unchecked(reqOff);

    uint8 numPdas;
    (numPdas, reqOff) = pcr.request.asUint8Unchecked(reqOff);

    (ret.slotNumber, respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64Unchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32Unchecked(respOff);

    uint8 respNumResults;
    (respNumResults, respOff) = pcr.response.asUint8Unchecked(respOff);
    if (respNumResults != numPdas)
      revert UnexpectedNumberOfResults();

    ret.results = new SolanaPdaResult[](numPdas);

    //Walk through the call data and results in lock step.
    for (uint i; i < numPdas; ++i) {
      (ret.results[i].programId, reqOff) = pcr.request.asBytes32Unchecked(reqOff);

      uint8 reqNumSeeds;
      (reqNumSeeds, reqOff) = pcr.request.asUint8Unchecked(reqOff);
      ret.results[i].seeds = new bytes[](reqNumSeeds);
      for (uint s; s < reqNumSeeds; ++s)
        (ret.results[i].seeds[s], reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.results[i].account,    respOff) = pcr.response.asBytes32Unchecked(respOff);
      (ret.results[i].bump,       respOff) = pcr.response.asUint8Unchecked(respOff);
      (ret.results[i].lamports,   respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].rentEpoch,  respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].executable, respOff) = pcr.response.asBoolUnchecked(respOff);
      (ret.results[i].owner,      respOff) = pcr.response.asBytes32Unchecked(respOff);
      (ret.results[i].data,       respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }}

  function validateBlockTime(
    uint64 blockTimeInMicroSeconds,
    uint256 minBlockTimeInSeconds
  ) internal pure {
    uint256 blockTimeInSeconds = blockTimeInMicroSeconds / 1_000_000; // Rounds down

    if (blockTimeInSeconds < minBlockTimeInSeconds)
      revert StaleBlockTime();
  }

  function validateBlockNum(uint64 blockNum, uint256 minBlockNum) internal pure {
    if (blockNum < minBlockNum)
      revert StaleBlockNum();
  }

  function validateChainId(
    uint16 chainId,
    uint16[] memory validChainIds
  ) internal pure { unchecked {
    uint numChainIds = validChainIds.length;
    for (uint i; i < numChainIds; ++i)
      if (chainId == validChainIds[i])
        return;

    revert InvalidChainId();
  }}

  function validateEthCallData(
    EthCallData[] memory ecds,
    address[] memory validContractAddresses,
    bytes4[] memory validFunctionSignatures
  ) internal pure { unchecked {
    uint callDatasLength = ecds.length;
    for (uint i; i < callDatasLength; ++i)
      validateEthCallData(ecds[i], validContractAddresses, validFunctionSignatures);
  }}

  //validates that EthCallData comes from a function signature and contract address we expect
  //An empty array means we accept all addresses/function signatures
  //  Example 1: To accept signatures 0xaaaaaaaa and 0xbbbbbbbb from `address(abcd)`
  //    you'd pass in [0xaaaaaaaa, 0xbbbbbbbb], [address(abcd)]
  //  Example 2: To accept any function signatures from `address(abcd)` or `address(efab)`
  //    you'd pass in [], [address(abcd), address(efab)]
  //  Example 3: To accept function signature 0xaaaaaaaa from any address
  //    you'd pass in [0xaaaaaaaa], []
  //
  // WARNING Example 4: If you want to accept signature 0xaaaaaaaa from `address(abcd)`
  //    and signature 0xbbbbbbbb from `address(efab)` the following input would be incorrect:
  //    [0xaaaaaaaa, 0xbbbbbbbb], [address(abcd), address(efab)]
  //    This would accept both 0xaaaaaaaa and 0xbbbbbbbb from `address(abcd)` AND `address(efab)`.
  //    Instead you should make 2 calls to this method using the pattern in Example 1.
  //    [0xaaaaaaaa], [address(abcd)] OR [0xbbbbbbbb], [address(efab)]
  function validateEthCallData(
    EthCallData memory ecd,
    address[] memory validContractAddresses, //empty array means accept all
    bytes4[] memory validFunctionSignatures  //empty array means accept all
  ) internal pure { unchecked {
    if (validContractAddresses.length > 0)
      validateContractAddress(ecd.contractAddress, validContractAddresses);
    
    if (validFunctionSignatures.length > 0) {
      (bytes4 funcSig,) = ecd.callData.asBytes4(0);
      validateFunctionSignature(funcSig, validFunctionSignatures);
    }
  }}

  function validateContractAddress(
    address contractAddress,
    address[] memory validContractAddresses
  ) private pure { unchecked {
    uint len = validContractAddresses.length;
    for (uint i; i < len; ++i)
      if (contractAddress == validContractAddresses[i])
        return;

    revert InvalidContractAddress();
  }}

  function validateFunctionSignature(
    bytes4 functionSignature,
    bytes4[] memory validFunctionSignatures
  ) private pure { unchecked {
    uint len = validFunctionSignatures.length;
    for (uint i; i < len; ++i)
      if (functionSignature == validFunctionSignatures[i])
        return;

    revert InvalidFunctionSignature();
  }}

  //we use this over BytesParsing.checkLength to return our custom errors in all error cases
  function checkLength(bytes memory encoded, uint256 expected) private pure {
    if (encoded.length != expected)
      revert InvalidPayloadLength(encoded.length, expected);
  }
}

