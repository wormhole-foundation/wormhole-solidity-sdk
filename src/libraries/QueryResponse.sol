// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {IWormhole} from "wormhole-sdk/interfaces/IWormhole.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";
import {eagerAnd, eagerOr} from "wormhole-sdk/Utils.sol";

error UnsupportedQueryType(uint8 received);

library QueryType {
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

//QueryResponse is a library that implements the parsing and verification of
//  Cross Chain Query (CCQ) responses.
//
//For a detailed discussion of these query responses, please see the white paper:
//  https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0013_ccq.md
library QueryResponseLib {
  using BytesParsing for bytes;

  bytes internal constant RESPONSE_PREFIX = bytes("query_response_0000000000000000000|");
  uint8 internal constant VERSION = 1;
  uint64 internal constant MICROSECONDS_PER_SECOND = 1_000_000;

  function calcPrefixedResponseHash(bytes memory response) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(RESPONSE_PREFIX, keccak256(response)));
  }

  //TODO add calldata impl? (duplicated code but better gas efficiency)
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
  ) internal view {
    verifyQueryResponse(wormhole, calcPrefixedResponseHash(response), signatures);
  }

  function verifyQueryResponse(
    address wormhole,
    bytes32 prefixedResponseHash,
    IWormhole.Signature[] memory signatures
  ) internal view { unchecked {
    IWormhole wormhole_ = IWormhole(wormhole);
    uint32 guardianSetIndex = wormhole_.getCurrentGuardianSetIndex();
    IWormhole.GuardianSet memory guardianSet = wormhole_.getGuardianSet(guardianSetIndex);

    while (true) {
      uint quorum = guardianSet.keys.length * 2 / 3 + 1;
      if (signatures.length >= quorum) {
        (bool signaturesValid, ) =
          wormhole_.verifySignatures(prefixedResponseHash, signatures, guardianSet);
        if (signaturesValid)
          return;
      }

      //check if the previous guardian set is still valid and if yes, try with that
      if (guardianSetIndex > 0) {
        guardianSet = wormhole_.getGuardianSet(--guardianSetIndex);
        if (guardianSet.expirationTime < block.timestamp)
          revert VerificationFailed();
      }
      else
        revert VerificationFailed();
    }
  }}

  function parseQueryResponse(
    bytes memory response
  ) internal pure returns (QueryResponse memory ret) { unchecked {
    uint offset;

    (ret.version, offset) = response.asUint8Unchecked(offset);
    if (ret.version != VERSION)
      revert InvalidResponseVersion();

    (ret.senderChainId, offset) = response.asUint16Unchecked(offset);

    //for off-chain requests (chainID zero), the requestId is the 65 byte signature
    //for on-chain requests, it is the 32 byte VAA hash
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

    //a valid query request must have at least one per-chain-query
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

    //walk through the requests and responses in lock step.
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

    //end of request body should align with start of response body
    if (startOfResponse != reqOff)
      revert InvalidPayloadLength(startOfResponse, reqOff);

    _checkLength(response, respOff);
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

    ret.results = new EthCallRecord[](numBatchCallData);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      (ret.results[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.results[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.results[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    _checkLength(pcr.request, reqOff);
    _checkLength(pcr.response, respOff);
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

    ret.results = new EthCallRecord[](numBatchCallData);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      (ret.results[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.results[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.results[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    _checkLength(pcr.request, reqOff);
    _checkLength(pcr.response, respOff);
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

    ret.results = new EthCallRecord[](numBatchCallData);

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numBatchCallData; ++i) {
      (ret.results[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.results[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.results[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    _checkLength(pcr.request, reqOff);
    _checkLength(pcr.response, respOff);
  }}

  function parseSolanaAccountQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (SolanaAccountQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.SOLANA_ACCOUNT)
      revert WrongQueryType(pcr.queryType, QueryType.SOLANA_ACCOUNT);

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

    //walk through the call inputs and outputs in lock step.
    for (uint i; i < numAccounts; ++i) {
      (ret.results[i].account, reqOff) = pcr.request.asBytes32Unchecked(reqOff);

      (ret.results[i].lamports,   respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].rentEpoch,  respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].executable, respOff) = pcr.response.asBoolUnchecked(respOff);
      (ret.results[i].owner,      respOff) = pcr.response.asBytes32Unchecked(respOff);
      (ret.results[i].data,       respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);
    }

    _checkLength(pcr.request, reqOff);
    _checkLength(pcr.response, respOff);
  }}

  function parseSolanaPdaQueryResponse(
    PerChainQueryResponse memory pcr
  ) internal pure returns (SolanaPdaQueryResponse memory ret) { unchecked {
    if (pcr.queryType != QueryType.SOLANA_PDA)
      revert WrongQueryType(pcr.queryType, QueryType.SOLANA_PDA);

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

    //walk through the call inputs and outputs in lock step.
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

    _checkLength(pcr.request, reqOff);
    _checkLength(pcr.response, respOff);
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

      (bytes4 funcSig, ) = ecd.callData.asBytes4Unchecked(0);
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
  function _checkLength(bytes memory encoded, uint256 expected) private pure {
    if (encoded.length != expected)
      revert InvalidPayloadLength(encoded.length, expected);
  }
}
