// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

import {BytesParsing} from "./BytesParsing.sol";
import {CoreBridgeLib} from "./CoreBridge.sol";
import {GuardianSignature} from "./VaaLib.sol";
import {eagerAnd, eagerOr, keccak256Cd} from "../Utils.sol";

library QueryType {
  error UnsupportedQueryType(uint8 received);

  //Solidity enums don't permit custom values (i.e. can't start from 1)
  //Also invalid enum conversions result in panics and manual range checking requires assembly
  //  to avoid superfluous double checking.
  //So we're sticking with uint8 constants instead.
  uint8 internal constant ETH_CALL = 1;
  uint8 internal constant ETH_CALL_BY_TIMESTAMP = 2;
  uint8 internal constant ETH_CALL_WITH_FINALITY = 3;
  uint8 internal constant SOLANA_ACCOUNT = 4;
  uint8 internal constant SOLANA_PDA = 5;

  //emulate type(enum).min/max for external consumers (mainly tests)
  function min() internal pure returns (uint8) { return ETH_CALL; }
  function max() internal pure returns (uint8) { return SOLANA_PDA; }

  function checkValid(uint8 queryType) internal pure {
    //slightly more gas efficient than calling `isValid`
    if (eagerOr(queryType == 0, queryType > SOLANA_PDA))
      revert UnsupportedQueryType(queryType);
  }

  function isValid(uint8 queryType) internal pure returns (bool) {
    //see docs/Optimization.md why `< CONST + 1` rather than `<= CONST`
    //see docs/Optimization.md for rationale behind `eagerAnd`
    return eagerAnd(queryType > 0, queryType < SOLANA_PDA + 1);
  }
}

struct QueryResponse {
  uint8 version;
  uint16 senderChainId;
  uint32 nonce;
  bytes requestId; // 65 byte sig for off-chain, 32 byte vaaHash for on-chain
  PerChainQueryResponse[] responses;
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
  EthCallRecord[] results;
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
  EthCallRecord[] results;
}

struct EthCallWithFinalityQueryResponse {
  bytes requestBlockId;
  bytes requestFinality;
  uint64 blockNum;
  uint64 blockTime;
  bytes32 blockHash;
  EthCallRecord[] results;
}

struct EthCallRecord {
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
  SolanaAccountResult[] results;
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
  SolanaPdaResult[] results;
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

//QueryResponse is a library that implements the decoding and verification of
//  Cross Chain Query (CCQ) responses.
//
//For a detailed discussion of these query responses, please see the white paper:
//  https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0013_ccq.md
//
//We only implement Cd and Mem decoding variants for the QueryResponse struct itself because all
//  further decoding will have to operate on the memory bytes anyway since there's no way in plain
//  Solidity to have structs with mixed data location, i.e. a struct in memory that references bytes
//  in calldata.
//  This will at least help cut down the gas cost of decoding/slicing the outer most layer.
library QueryResponseLib {
  using BytesParsing for bytes;

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
  error VerificationFailed();

  bytes internal constant RESPONSE_PREFIX = bytes("query_response_0000000000000000000|");
  uint8 internal constant VERSION = 1;
  uint64 internal constant MICROSECONDS_PER_SECOND = 1_000_000;

  function calcPrefixedResponseHashCd(bytes calldata response) internal pure returns (bytes32) {
    return calcPrefixedResponseHash(keccak256Cd(response));
  }

  function calcPrefixedResponseHashMem(bytes memory response) internal pure returns (bytes32) {
    return calcPrefixedResponseHash(keccak256(response));
  }

  function calcPrefixedResponseHash(bytes32 responseHash) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(RESPONSE_PREFIX, responseHash));
  }

  // -------- decodeAndVerifyQueryResponse --------

  // ---- guardian set index variants
  // will look up the guardian set internally and also try to verify against the latest
  //   guardian set, if the specified guardian set is expired.

  function decodeAndVerifyQueryResponseCd(
    address wormhole,
    bytes calldata response,
    GuardianSignature[] calldata guardianSignatures,
    uint32 guardianSetIndex
  ) internal view returns (QueryResponse memory ret) {
    verifyQueryResponseCd(wormhole, response, guardianSignatures, guardianSetIndex);
    return decodeQueryResponseCd(response);
  }

  function decodeAndVerifyQueryResponseMem(
    address wormhole,
    bytes memory response,
    GuardianSignature[] memory guardianSignatures,
    uint32 guardianSetIndex
  ) internal view returns (QueryResponse memory ret) {
    verifyQueryResponseMem(wormhole, response, guardianSignatures, guardianSetIndex);
    return decodeQueryResponseMem(response);
  }

  function verifyQueryResponseCd(
    address wormhole,
    bytes calldata response,
    GuardianSignature[] calldata guardianSignatures,
    uint32 guardianSetIndex
  ) internal view {
    if (!CoreBridgeLib.isVerifiedByQuorumCd(
      wormhole,
      calcPrefixedResponseHashCd(response),
      guardianSignatures,
      guardianSetIndex
    ))
      revert VerificationFailed();
  }

  function verifyQueryResponseMem(
    address wormhole,
    bytes memory response,
    GuardianSignature[] memory guardianSignatures,
    uint32 guardianSetIndex
  ) internal view {
    if (!CoreBridgeLib.isVerifiedByQuorumMem(
      wormhole,
      calcPrefixedResponseHashMem(response),
      guardianSignatures,
      guardianSetIndex
    ))
      revert VerificationFailed();
  }

  // ---- guardian address variants
  // will only try to verify against the specified guardian addresses only

  function decodeAndVerifyQueryResponseCd(
    bytes calldata response,
    GuardianSignature[] calldata guardianSignatures,
    address[] memory guardians
  ) internal pure returns (QueryResponse memory ret) {
    verifyQueryResponseCd(response, guardianSignatures, guardians);
    return decodeQueryResponseCd(response);
  }

  function decodeAndVerifyQueryResponseMem(
    bytes memory response,
    GuardianSignature[] memory guardianSignatures,
    address[] memory guardians
  ) internal pure returns (QueryResponse memory ret) {
    verifyQueryResponseMem(response, guardianSignatures, guardians);
    return decodeQueryResponseMem(response);
  }

  function verifyQueryResponseCd(
    bytes calldata response,
    GuardianSignature[] calldata guardianSignatures,
    address[] memory guardians
  ) internal pure {
    if (!CoreBridgeLib.isVerifiedByQuorumCd(
      calcPrefixedResponseHashCd(response),
      guardianSignatures,
      guardians
    ))
      revert VerificationFailed();
  }

  function verifyQueryResponseMem(
    bytes memory response,
    GuardianSignature[] memory guardianSignatures,
    address[] memory guardians
  ) internal pure {
    if (!CoreBridgeLib.isVerifiedByQuorumMem(
      calcPrefixedResponseHashMem(response),
      guardianSignatures,
      guardians
    ))
      revert VerificationFailed();
  }

  // -------- decode functions --------

  function decodeQueryResponseCd(
    bytes calldata response
  ) internal pure returns (QueryResponse memory ret) { unchecked {
    uint offset;

    (ret.version, offset) = response.asUint8CdUnchecked(offset);
    if (ret.version != VERSION)
      revert InvalidResponseVersion();

    (ret.senderChainId, offset) = response.asUint16CdUnchecked(offset);

    //for off-chain requests (chainID zero), the requestId is the 65 byte signature
    //for on-chain requests, it is the 32 byte VAA hash
    (ret.requestId, offset) = response.sliceCdUnchecked(offset, ret.senderChainId == 0 ? 65 : 32);

    uint32 queryReqLen;
    (queryReqLen, offset) = response.asUint32CdUnchecked(offset);
    uint reqOff = offset;

    {
      uint8 version;
      (version, reqOff) = response.asUint8CdUnchecked(reqOff);
      if (version != ret.version)
        revert VersionMismatch();
    }

    (ret.nonce, reqOff) = response.asUint32CdUnchecked(reqOff);

    uint8 numPerChainQueries;
    (numPerChainQueries, reqOff) = response.asUint8CdUnchecked(reqOff);

    //a valid query request must have at least one per-chain-query
    if (numPerChainQueries == 0)
      revert ZeroQueries();

    //The response starts after the request.
    uint respOff = offset + queryReqLen;
    uint startOfResponse = respOff;

    uint8 respNumPerChainQueries;
    (respNumPerChainQueries, respOff) = response.asUint8CdUnchecked(respOff);
    if (respNumPerChainQueries != numPerChainQueries)
      revert NumberOfResponsesMismatch();

    ret.responses = new PerChainQueryResponse[](numPerChainQueries);

    //walk through the requests and responses in lock step.
    for (uint i; i < numPerChainQueries; ++i) {
      (ret.responses[i].chainId, reqOff) = response.asUint16CdUnchecked(reqOff);
      uint16 respChainId;
      (respChainId, respOff) = response.asUint16CdUnchecked(respOff);
      if (respChainId != ret.responses[i].chainId)
        revert ChainIdMismatch();

      (ret.responses[i].queryType, reqOff) = response.asUint8CdUnchecked(reqOff);
      QueryType.checkValid(ret.responses[i].queryType);
      uint8 respQueryType;
      (respQueryType, respOff) = response.asUint8CdUnchecked(respOff);
      if (respQueryType != ret.responses[i].queryType)
        revert RequestTypeMismatch();

      (ret.responses[i].request, reqOff) = response.sliceUint32PrefixedCdUnchecked(reqOff);

      (ret.responses[i].response, respOff) = response.sliceUint32PrefixedCdUnchecked(respOff);
    }

    //end of request body should align with start of response body
    if (startOfResponse != reqOff)
      revert InvalidPayloadLength(startOfResponse, reqOff);

    _checkLength(response.length, respOff);
    return ret;
  }}

  function decodeQueryResponseMem(
    bytes memory response
  ) internal pure returns (QueryResponse memory ret) { unchecked {
    uint offset;

    (ret.version, offset) = response.asUint8MemUnchecked(offset);
    if (ret.version != VERSION)
      revert InvalidResponseVersion();

    (ret.senderChainId, offset) = response.asUint16MemUnchecked(offset);

    //for off-chain requests (chainID zero), the requestId is the 65 byte signature
    //for on-chain requests, it is the 32 byte VAA hash
    (ret.requestId, offset) = response.sliceMemUnchecked(offset, ret.senderChainId == 0 ? 65 : 32);

    uint32 queryReqLen;
    (queryReqLen, offset) = response.asUint32MemUnchecked(offset);
    uint reqOff = offset;

    {
      uint8 version;
      (version, reqOff) = response.asUint8MemUnchecked(reqOff);
      if (version != ret.version)
        revert VersionMismatch();
    }

    (ret.nonce, reqOff) = response.asUint32MemUnchecked(reqOff);

    uint8 numPerChainQueries;
    (numPerChainQueries, reqOff) = response.asUint8MemUnchecked(reqOff);

    //a valid query request must have at least one per-chain-query
    if (numPerChainQueries == 0)
      revert ZeroQueries();

    //The response starts after the request.
    uint respOff = offset + queryReqLen;
    uint startOfResponse = respOff;

    uint8 respNumPerChainQueries;
    (respNumPerChainQueries, respOff) = response.asUint8MemUnchecked(respOff);
    if (respNumPerChainQueries != numPerChainQueries)
      revert NumberOfResponsesMismatch();

    ret.responses = new PerChainQueryResponse[](numPerChainQueries);

    //walk through the requests and responses in lock step.
    for (uint i; i < numPerChainQueries; ++i) {
      (ret.responses[i].chainId, reqOff) = response.asUint16MemUnchecked(reqOff);
      uint16 respChainId;
      (respChainId, respOff) = response.asUint16MemUnchecked(respOff);
      if (respChainId != ret.responses[i].chainId)
        revert ChainIdMismatch();

      (ret.responses[i].queryType, reqOff) = response.asUint8MemUnchecked(reqOff);
      QueryType.checkValid(ret.responses[i].queryType);
      uint8 respQueryType;
      (respQueryType, respOff) = response.asUint8MemUnchecked(respOff);
      if (respQueryType != ret.responses[i].queryType)
        revert RequestTypeMismatch();

      (ret.responses[i].request, reqOff) = response.sliceUint32PrefixedMemUnchecked(reqOff);

      (ret.responses[i].response, respOff) = response.sliceUint32PrefixedMemUnchecked(respOff);
    }

    //end of request body should align with start of response body
    if (startOfResponse != reqOff)
      revert InvalidPayloadLength(startOfResponse, reqOff);

    _checkLength(response.length, respOff);
    return ret;
  }}

  function decodeEthCallQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (EthCallQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.ETH_CALL)
      revert WrongQueryType(pcr.queryType, QueryType.ETH_CALL);

    uint reqOff;
    uint respOff;

    uint8 numBatchCallData;
    (ret.requestBlockId, reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);
    (numBatchCallData,   reqOff) = pcr.request.asUint8MemUnchecked(reqOff);

    uint8 respNumResults;
    (ret.blockNum,   respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32MemUnchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (respNumResults, respOff) = pcr.response.asUint8MemUnchecked(respOff);

    if (respNumResults != numBatchCallData)
      revert UnexpectedNumberOfResults();

    ret.results = new EthCallRecord[](numBatchCallData);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      EthCallRecord memory ecr = ret.results[i];
      (ecr.contractAddress, reqOff) = pcr.request.asAddressMemUnchecked(reqOff);
      (ecr.callData,        reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);

      (ecr.result, respOff) = pcr.response.sliceUint32PrefixedMemUnchecked(respOff);
    }

    _checkLength(pcr.request.length, reqOff);
    _checkLength(pcr.response.length, respOff);
    return ret;
  }}

  function decodeEthCallByTimestampQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (EthCallByTimestampQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.ETH_CALL_BY_TIMESTAMP)
      revert WrongQueryType(pcr.queryType, QueryType.ETH_CALL_BY_TIMESTAMP);

    uint reqOff;
    uint respOff;

    uint8 numBatchCallData;
    (ret.requestTargetTimestamp,      reqOff) = pcr.request.asUint64MemUnchecked(reqOff);
    (ret.requestTargetBlockIdHint,    reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);
    (ret.requestFollowingBlockIdHint, reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);
    (numBatchCallData,                reqOff) = pcr.request.asUint8MemUnchecked(reqOff);

    uint8 respNumResults;
    (ret.targetBlockNum,     respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.targetBlockHash,    respOff) = pcr.response.asBytes32MemUnchecked(respOff);
    (ret.targetBlockTime,    respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.followingBlockNum,  respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.followingBlockHash, respOff) = pcr.response.asBytes32MemUnchecked(respOff);
    (ret.followingBlockTime, respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (respNumResults,         respOff) = pcr.response.asUint8MemUnchecked(respOff);

    if (respNumResults != numBatchCallData)
      revert UnexpectedNumberOfResults();

    ret.results = new EthCallRecord[](numBatchCallData);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      EthCallRecord memory ecr = ret.results[i];
      (ecr.contractAddress, reqOff) = pcr.request.asAddressMemUnchecked(reqOff);
      (ecr.callData,        reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);

      (ecr.result, respOff) = pcr.response.sliceUint32PrefixedMemUnchecked(respOff);
    }

    _checkLength(pcr.request.length, reqOff);
    _checkLength(pcr.response.length, respOff);
  }}

  function decodeEthCallWithFinalityQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (EthCallWithFinalityQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.ETH_CALL_WITH_FINALITY)
      revert WrongQueryType(pcr.queryType, QueryType.ETH_CALL_WITH_FINALITY);

    uint reqOff;
    uint respOff;

    uint8 numBatchCallData;
    (ret.requestBlockId,  reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);
    (ret.requestFinality, reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);
    (numBatchCallData,    reqOff) = pcr.request.asUint8MemUnchecked(reqOff);

    uint8 respNumResults;
    (ret.blockNum,   respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32MemUnchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (respNumResults, respOff) = pcr.response.asUint8MemUnchecked(respOff);

    if (respNumResults != numBatchCallData)
      revert UnexpectedNumberOfResults();

    ret.results = new EthCallRecord[](numBatchCallData);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      EthCallRecord memory ecr = ret.results[i];
      (ecr.contractAddress, reqOff) = pcr.request.asAddressMemUnchecked(reqOff);
      (ecr.callData,        reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);

      (ecr.result, respOff) = pcr.response.sliceUint32PrefixedMemUnchecked(respOff);
    }

    _checkLength(pcr.request.length, reqOff);
    _checkLength(pcr.response.length, respOff);
  }}

  function decodeSolanaAccountQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (SolanaAccountQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.SOLANA_ACCOUNT)
      revert WrongQueryType(pcr.queryType, QueryType.SOLANA_ACCOUNT);

    uint reqOff;
    uint respOff;

    uint8 numAccounts;
    (ret.requestCommitment,      reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);
    (ret.requestMinContextSlot,  reqOff) = pcr.request.asUint64MemUnchecked(reqOff);
    (ret.requestDataSliceOffset, reqOff) = pcr.request.asUint64MemUnchecked(reqOff);
    (ret.requestDataSliceLength, reqOff) = pcr.request.asUint64MemUnchecked(reqOff);
    (numAccounts,                reqOff) = pcr.request.asUint8MemUnchecked(reqOff);

    uint8 respNumResults;
    (ret.slotNumber, respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32MemUnchecked(respOff);
    (respNumResults, respOff) = pcr.response.asUint8MemUnchecked(respOff);

    if (respNumResults != numAccounts)
      revert UnexpectedNumberOfResults();

    ret.results = new SolanaAccountResult[](numAccounts);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numAccounts; ++i) {
      (ret.results[i].account, reqOff) = pcr.request.asBytes32MemUnchecked(reqOff);

      (ret.results[i].lamports,   respOff) = pcr.response.asUint64MemUnchecked(respOff);
      (ret.results[i].rentEpoch,  respOff) = pcr.response.asUint64MemUnchecked(respOff);
      (ret.results[i].executable, respOff) = pcr.response.asBoolMemUnchecked(respOff);
      (ret.results[i].owner,      respOff) = pcr.response.asBytes32MemUnchecked(respOff);
      (ret.results[i].data,       respOff) = pcr.response.sliceUint32PrefixedMemUnchecked(respOff);
    }

    _checkLength(pcr.request.length, reqOff);
    _checkLength(pcr.response.length, respOff);
  }}

  function decodeSolanaPdaQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (SolanaPdaQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.SOLANA_PDA)
      revert WrongQueryType(pcr.queryType, QueryType.SOLANA_PDA);

    uint reqOff;
    uint respOff;

    (ret.requestCommitment,      reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);
    (ret.requestMinContextSlot,  reqOff) = pcr.request.asUint64MemUnchecked(reqOff);
    (ret.requestDataSliceOffset, reqOff) = pcr.request.asUint64MemUnchecked(reqOff);
    (ret.requestDataSliceLength, reqOff) = pcr.request.asUint64MemUnchecked(reqOff);

    uint8 numPdas;
    (numPdas, reqOff) = pcr.request.asUint8MemUnchecked(reqOff);

    (ret.slotNumber, respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.blockTime,  respOff) = pcr.response.asUint64MemUnchecked(respOff);
    (ret.blockHash,  respOff) = pcr.response.asBytes32MemUnchecked(respOff);

    uint8 respNumResults;
    (respNumResults, respOff) = pcr.response.asUint8MemUnchecked(respOff);
    if (respNumResults != numPdas)
      revert UnexpectedNumberOfResults();

    ret.results = new SolanaPdaResult[](numPdas);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numPdas; ++i) {
      (ret.results[i].programId, reqOff) = pcr.request.asBytes32MemUnchecked(reqOff);

      uint8 reqNumSeeds;
      (reqNumSeeds, reqOff) = pcr.request.asUint8MemUnchecked(reqOff);
      ret.results[i].seeds = new bytes[](reqNumSeeds);
      for (uint s; s < reqNumSeeds; ++s)
        (ret.results[i].seeds[s], reqOff) = pcr.request.sliceUint32PrefixedMemUnchecked(reqOff);

      (ret.results[i].account,    respOff) = pcr.response.asBytes32MemUnchecked(respOff);
      (ret.results[i].bump,       respOff) = pcr.response.asUint8MemUnchecked(respOff);
      (ret.results[i].lamports,   respOff) = pcr.response.asUint64MemUnchecked(respOff);
      (ret.results[i].rentEpoch,  respOff) = pcr.response.asUint64MemUnchecked(respOff);
      (ret.results[i].executable, respOff) = pcr.response.asBoolMemUnchecked(respOff);
      (ret.results[i].owner,      respOff) = pcr.response.asBytes32MemUnchecked(respOff);
      (ret.results[i].data,       respOff) = pcr.response.sliceUint32PrefixedMemUnchecked(respOff);
    }

    _checkLength(pcr.request.length, reqOff);
    _checkLength(pcr.response.length, respOff);
  }}

  function validateBlockTime(
    uint64 blockTimeInMicroSeconds,
    uint256 minBlockTimeInSeconds
  ) internal pure {
    uint256 blockTimeInSeconds = blockTimeInMicroSeconds / MICROSECONDS_PER_SECOND; // Rounds down

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
    uint len = validChainIds.length;
    for (uint i; i < len; ++i)
      if (chainId == validChainIds[i])
        return;

    revert InvalidChainId();
  }}

  function validateEthCallRecord(
    EthCallRecord[] memory ecrs,
    address[] memory validContractAddresses,
    bytes4[] memory validFunctionSignatures
  ) internal pure { unchecked {
    uint len = ecrs.length;
    for (uint i; i < len; ++i)
      validateEthCallRecord(ecrs[i], validContractAddresses, validFunctionSignatures);
  }}

  //validates that EthCallRecord a valid function signature and contract address
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
  function validateEthCallRecord(
    EthCallRecord memory ecd,
    address[] memory validContractAddresses, //empty array means accept all
    bytes4[] memory validFunctionSignatures  //empty array means accept all
  ) internal pure {
    if (validContractAddresses.length > 0)
      _validateContractAddress(ecd.contractAddress, validContractAddresses);

    if (validFunctionSignatures.length > 0) {
      if (ecd.callData.length < 4)
        revert InvalidFunctionSignature();

      (bytes4 funcSig, ) = ecd.callData.asBytes4MemUnchecked(0);
      _validateFunctionSignature(funcSig, validFunctionSignatures);
    }
  }

  function _validateContractAddress(
    address contractAddress,
    address[] memory validContractAddresses
  ) private pure { unchecked {
    uint len = validContractAddresses.length;
    for (uint i; i < len; ++i)
      if (contractAddress == validContractAddresses[i])
        return;

    revert InvalidContractAddress();
  }}

  function _validateFunctionSignature(
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
  function _checkLength(uint256 length, uint256 expected) private pure {
    if (length != expected)
      revert InvalidPayloadLength(length, expected);
  }
}
