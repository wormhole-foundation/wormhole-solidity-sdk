// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing} from "./libraries/BytesParsing.sol";
import "./interfaces/IWormhole.sol";

// @dev ParsedQueryResponse is returned by QueryResponse.parseAndVerifyQueryResponse().
struct ParsedQueryResponse {
  uint8 version;
  uint16 senderChainId;
  uint32 nonce;
  bytes requestId; // 65 byte sig for off-chain, 32 byte vaaHash for on-chain
  ParsedPerChainQueryResponse [] responses;
}

// @dev ParsedPerChainQueryResponse describes a single per-chain response.
struct ParsedPerChainQueryResponse {
  uint16 chainId;
  uint8 queryType;
  bytes request;
  bytes response;
}

// @dev EthCallQueryResponse describes the response to an ETH call per-chain query.
struct EthCallQueryResponse {
  bytes requestBlockId;
  uint64 blockNum;
  uint64 blockTime;
  bytes32 blockHash;
  EthCallData [] result;
}

// @dev EthCallByTimestampQueryResponse describes the response to an ETH call by timestamp per-chain query.
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

// @dev EthCallWithFinalityQueryResponse describes the response to an ETH call with finality per-chain query.
struct EthCallWithFinalityQueryResponse {
  bytes requestBlockId;
  bytes requestFinality;
  uint64 blockNum;
  uint64 blockTime;
  bytes32 blockHash;
  EthCallData [] result;
}

// @dev EthCallData describes a single ETH call query / response pair.
struct EthCallData {
  address contractAddress;
  bytes callData;
  bytes result;
}

// @dev SolanaAccountQueryResponse describes the response to a Solana Account query per-chain query.
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

// @dev SolanaAccountResult describes a single Solana Account query result.
struct SolanaAccountResult {
  bytes32 account;
  uint64 lamports;
  uint64 rentEpoch;
  bool executable;
  bytes32 owner;
  bytes data;
}

// @dev SolanaPdaQueryResponse describes the response to a Solana PDA (Program Derived Address) query per-chain query.
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

// @dev SolanaPdaResult describes a single Solana PDA (Program Derived Address) query result.
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
error EmptyWormholeAddress();
error InvalidResponseVersion();
error VersionMismatch();
error ZeroQueries();
error NumberOfResponsesMismatch();
error ChainIdMismatch();
error RequestTypeMismatch();
error UnsupportedQueryType(uint8 received);
error WrongQueryType(uint8 received, uint8 expected);
error UnexpectedNumberOfResults();
error InvalidPayloadLength(uint256 received, uint256 expected);
error InvalidContractAddress();
error InvalidFunctionSignature();
error InvalidChainId();
error StaleBlockNum();
error StaleBlockTime();

// @dev QueryResponse is a library that implements the parsing and verification of Cross Chain Query (CCQ) responses.
// For a detailed discussion of these query responses, please see the white paper:
// https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0013_ccq.md
abstract contract QueryResponse {
  using BytesParsing for bytes;

  IWormhole public immutable wormhole;

  bytes public constant RESPONSE_PREFIX = bytes("query_response_0000000000000000000|");
  uint8 public constant VERSION = 1;

  // TODO: Consider changing these to an enum.
  uint8 public constant QT_ETH_CALL = 1;
  uint8 public constant QT_ETH_CALL_BY_TIMESTAMP = 2;
  uint8 public constant QT_ETH_CALL_WITH_FINALITY = 3;
  uint8 public constant QT_SOL_ACCOUNT = 4;
  uint8 public constant QT_SOL_PDA = 5;
  uint8 public constant QT_MAX = 6; // Keep this last

  constructor(address _wormhole) {
    if (_wormhole == address(0))
      revert EmptyWormholeAddress();

    wormhole = IWormhole(_wormhole);
  }

  /// @dev getResponseHash computes the hash of the specified query response.
  function getResponseHash(bytes memory response) public pure returns (bytes32) {
    return keccak256(response);
  }

  /// @dev getResponseDigest computes the digest of the specified query response.
  function getResponseDigest(bytes memory response) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(RESPONSE_PREFIX, getResponseHash(response)));
  }

  /// @dev parseAndVerifyQueryResponse verifies the query response and returns the parsed response.
  function parseAndVerifyQueryResponse(
    bytes memory response,
    IWormhole.Signature[] memory signatures
  ) public view returns (ParsedQueryResponse memory ret) {
    verifyQueryResponseSignatures(response, signatures);

    uint offset;

    (ret.version, offset) = response.asUint8Unchecked(offset);
    if (ret.version != VERSION)
      revert InvalidResponseVersion();

    (ret.senderChainId, offset) = response.asUint16Unchecked(offset);

    // For off chain requests (chainID zero), the requestId is the 65 byte signature.
    // For on chain requests, it is the 32 byte VAA hash.
    (ret.requestId, offset) = response.sliceUnchecked(offset, ret.senderChainId == 0 ? 65 : 32);

    uint32 queryReqLen;
    (queryReqLen, offset) = response.asUint32Unchecked(offset);
    uint reqOff = offset;

    // Scope to avoid stack-too-deep error
    {
      uint8 version;
      (version, reqOff) = response.asUint8Unchecked(reqOff);
      if (version != ret.version)
        revert VersionMismatch();
    }

    (ret.nonce, reqOff) = response.asUint32Unchecked(reqOff);

    uint8 numPerChainQueries;
    (numPerChainQueries, reqOff) = response.asUint8Unchecked(reqOff);

    // A valid query request has at least one per chain query
    if (numPerChainQueries == 0)
      revert ZeroQueries();

    // The response starts after the request.
    uint respOff = offset + queryReqLen;
    uint startOfResponse = respOff;

    uint8 respNumPerChainQueries;
    (respNumPerChainQueries, respOff) = response.asUint8Unchecked(respOff);
    if (respNumPerChainQueries != numPerChainQueries)
      revert NumberOfResponsesMismatch();

    ret.responses = new ParsedPerChainQueryResponse[](numPerChainQueries);

    // Walk through the requests and responses in lock step.
    for (uint i; i < numPerChainQueries;) {
      (ret.responses[i].chainId, reqOff) = response.asUint16Unchecked(reqOff);
      uint16 respChainId;
      (respChainId, respOff) = response.asUint16Unchecked(respOff);
      if (respChainId != ret.responses[i].chainId)
        revert ChainIdMismatch();

      (ret.responses[i].queryType, reqOff) = response.asUint8Unchecked(reqOff);
      uint8 respQueryType;
      (respQueryType, respOff) = response.asUint8Unchecked(respOff);
      if (respQueryType != ret.responses[i].queryType)
        revert RequestTypeMismatch();

      if (ret.responses[i].queryType < QT_ETH_CALL || ret.responses[i].queryType >= QT_MAX)
        revert UnsupportedQueryType(ret.responses[i].queryType);

      (ret.responses[i].request, reqOff) = response.sliceUint32PrefixedUnchecked(reqOff);

      (ret.responses[i].response, respOff) = response.sliceUint32PrefixedUnchecked(respOff);

      unchecked { ++i; }
    }

    // End of request body should align with start of response body
    if (startOfResponse != reqOff)
      revert InvalidPayloadLength(startOfResponse, reqOff);

    checkLength(response, respOff);
    return ret;
  }

  /// @dev parseEthCallQueryResponse parses a ParsedPerChainQueryResponse for an ETH call per-chain query.
  function parseEthCallQueryResponse(
    ParsedPerChainQueryResponse memory pcr
  ) public pure returns (EthCallQueryResponse memory ret) {
    if (pcr.queryType != QT_ETH_CALL)
      revert WrongQueryType(pcr.queryType, QT_ETH_CALL);

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

    // Walk through the call data and results in lock step.
    for (uint i; i < numBatchCallData;) {
      (ret.result[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.result[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.result[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);

      unchecked { ++i; }
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
    return ret;
  }

  /// @dev parseEthCallByTimestampQueryResponse parses a ParsedPerChainQueryResponse for an ETH call per-chain query.
  function parseEthCallByTimestampQueryResponse(
    ParsedPerChainQueryResponse memory pcr
  ) public pure returns (EthCallByTimestampQueryResponse memory ret) {
    if (pcr.queryType != QT_ETH_CALL_BY_TIMESTAMP)
      revert WrongQueryType(pcr.queryType, QT_ETH_CALL_BY_TIMESTAMP);

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
    for (uint i; i < numBatchCallData;) {
      (ret.result[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.result[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.result[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);

      unchecked { ++i; }
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }

  /// @dev parseEthCallWithFinalityQueryResponse parses a ParsedPerChainQueryResponse for an ETH call per-chain query.
  function parseEthCallWithFinalityQueryResponse(
    ParsedPerChainQueryResponse memory pcr
  ) public pure returns (EthCallWithFinalityQueryResponse memory ret) {
    if (pcr.queryType != QT_ETH_CALL_WITH_FINALITY)
      revert WrongQueryType(pcr.queryType, QT_ETH_CALL_WITH_FINALITY);

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

    // Walk through the call data and results in lock step.
    for (uint i; i < numBatchCallData;) {
      (ret.result[i].contractAddress, reqOff) = pcr.request.asAddressUnchecked(reqOff);
      (ret.result[i].callData,        reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);

      (ret.result[i].result, respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);

      unchecked { ++i; }
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }

  /// @dev parseSolanaAccountQueryResponse parses a ParsedPerChainQueryResponse for a Solana Account per-chain query.
  function parseSolanaAccountQueryResponse(
    ParsedPerChainQueryResponse memory pcr
  ) public pure returns (SolanaAccountQueryResponse memory ret) {
    if (pcr.queryType != QT_SOL_ACCOUNT)
      revert WrongQueryType(pcr.queryType, QT_SOL_ACCOUNT);

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

    // Walk through the call data and results in lock step.
    for (uint i; i < numAccounts;) {
      (ret.results[i].account, reqOff) = pcr.request.asBytes32Unchecked(reqOff);

      (ret.results[i].lamports,   respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].rentEpoch,  respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].executable, respOff) = pcr.response.asBoolUnchecked(respOff);
      (ret.results[i].owner,      respOff) = pcr.response.asBytes32Unchecked(respOff);
      (ret.results[i].data,       respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);

      unchecked { ++i; }
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }

  /// @dev parseSolanaPdaQueryResponse parses a ParsedPerChainQueryResponse for a Solana Pda per-chain query.
  function parseSolanaPdaQueryResponse(
    ParsedPerChainQueryResponse memory pcr
  ) public pure returns (SolanaPdaQueryResponse memory ret) {
    if (pcr.queryType != QT_SOL_PDA)
      revert WrongQueryType(pcr.queryType, QT_SOL_PDA);

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

    // Walk through the call data and results in lock step.
    for (uint i; i < numPdas;) {
      (ret.results[i].programId, reqOff) = pcr.request.asBytes32Unchecked(reqOff);

      uint8 reqNumSeeds;
      (reqNumSeeds, reqOff) = pcr.request.asUint8Unchecked(reqOff);
      ret.results[i].seeds = new bytes[](reqNumSeeds);
      for (uint s; s < reqNumSeeds;) {
        (ret.results[i].seeds[s], reqOff) = pcr.request.sliceUint32PrefixedUnchecked(reqOff);
        unchecked { ++s; }
      }

      (ret.results[i].account,    respOff) = pcr.response.asBytes32Unchecked(respOff);
      (ret.results[i].bump,       respOff) = pcr.response.asUint8Unchecked(respOff);
      (ret.results[i].lamports,   respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].rentEpoch,  respOff) = pcr.response.asUint64Unchecked(respOff);
      (ret.results[i].executable, respOff) = pcr.response.asBoolUnchecked(respOff);
      (ret.results[i].owner,      respOff) = pcr.response.asBytes32Unchecked(respOff);
      (ret.results[i].data,       respOff) = pcr.response.sliceUint32PrefixedUnchecked(respOff);

      unchecked { ++i; }
    }

    checkLength(pcr.request, reqOff);
    checkLength(pcr.response, respOff);
  }

  /// @dev validateBlockTime validates that the parsed block time isn't stale
  /// @param blockTime Wormhole block time in MICROseconds
  /// @param minBlockTime Minium block time in seconds
  function validateBlockTime(uint64 blockTime, uint256 minBlockTime) public pure {
    uint256 blockTimeInSeconds = blockTime / 1_000_000; // Rounds down

    if (blockTimeInSeconds < minBlockTime)
      revert StaleBlockTime();
  }

  /// @dev validateBlockNum validates that the parsed blockNum isn't stale
  function validateBlockNum(uint64 blockNum, uint256 minBlockNum) public pure {
    if (blockNum < minBlockNum)
      revert StaleBlockNum();
  }

  /// @dev validateChainId validates that the parsed chainId is one of an array of chainIds we expect
  function validateChainId(uint16 chainId, uint16[] memory validChainIds) public pure {
    uint256 numChainIds = validChainIds.length;
    for (uint i; i < numChainIds;) {
      if (chainId == validChainIds[i])
        return;

      unchecked { ++i; }
    }

    revert InvalidChainId();
  }

  /// @dev validateMutlipleEthCallData validates that each EthCallData in an array comes from a function signature and contract address we expect
  function validateMultipleEthCallData(
    EthCallData[] memory ecds,
    address[] memory _expectedContractAddresses,
    bytes4[] memory _expectedFunctionSignatures
  ) public pure {
    uint256 callDatasLength = ecds.length;

    for (uint i; i < callDatasLength;) {
      validateEthCallData(ecds[i], _expectedContractAddresses, _expectedFunctionSignatures);

      unchecked { ++i; }
    }
  }

  /// @dev validateEthCallData validates that EthCallData comes from a function signature and contract address we expect
  /// @dev An empty array means we accept all addresses/function signatures
  /// @dev Example 1: To accept signatures 0xaaaaaaaa and 0xbbbbbbbb from `address(abcd)` you'd pass in [0xaaaaaaaa, 0xbbbbbbbb], [address(abcd)]
  /// @dev Example 2: To accept any function signatures from `address(abcd)` or `address(efab)` you'd pass in [], [address(abcd), address(efab)]
  /// @dev Example 3: To accept function signature 0xaaaaaaaa from any address you'd pass in [0xaaaaaaaa], []
  /// @dev WARNING Example 4: If you want to accept signature 0xaaaaaaaa from `address(abcd)` and signature 0xbbbbbbbb from `address(efab)` the following input would be incorrect:
  /// @dev [0xaaaaaaaa, 0xbbbbbbbb], [address(abcd), address(efab)]
  /// @dev This would accept both 0xaaaaaaaa and 0xbbbbbbbb from `address(abcd)` AND `address(efab)`. Instead you should make 2 calls to this method
  /// @dev using the pattern in Example 1. [0xaaaaaaaa], [address(abcd)] OR [0xbbbbbbbb], [address(efab)]
  function validateEthCallData(
    EthCallData memory ecd,
    address[] memory _expectedContractAddresses,
    bytes4[] memory _expectedFunctionSignatures
  ) public pure {
    bool validContractAddress = _expectedContractAddresses.length == 0;
    bool validFunctionSignature = _expectedFunctionSignatures.length == 0;

    uint256 contractAddressesLength = _expectedContractAddresses.length;

    // Check that the contract address called in the request is expected
    for (uint i; i < contractAddressesLength;) {
      if (ecd.contractAddress == _expectedContractAddresses[i]) {
        validContractAddress = true;
        break;
      }

      unchecked { ++i; }
    }

    // Early exit to save gas
    if (!validContractAddress)
      revert InvalidContractAddress();

    uint256 functionSignaturesLength = _expectedFunctionSignatures.length;

    // Check that the function signature called is expected
    for (uint i; i < functionSignaturesLength;) {
      (bytes4 funcSig,) = ecd.callData.asBytes4Unchecked(0);
      if (funcSig == _expectedFunctionSignatures[i]) {
        validFunctionSignature = true;
        break;
      }

      unchecked { ++i; }
    }

    if (!validFunctionSignature)
      revert InvalidFunctionSignature();
  }

  /**
   * @dev verifyQueryResponseSignatures verifies the signatures on a query response. It calls into the Wormhole contract.
   * IWormhole.Signature expects the last byte to be bumped by 27
   * see https://github.com/wormhole-foundation/wormhole/blob/637b1ee657de7de05f783cbb2078dd7d8bfda4d0/ethereum/contracts/Messages.sol#L174
   */
  function verifyQueryResponseSignatures(
    bytes memory response,
    IWormhole.Signature[] memory signatures
  ) public view {
    // It might be worth adding a verifyCurrentQuorum call on the core bridge so that there is only 1 cross call instead of 4.
    uint32 gsi = wormhole.getCurrentGuardianSetIndex();
    IWormhole.GuardianSet memory guardianSet = wormhole.getGuardianSet(gsi);

    bytes32 responseHash = getResponseDigest(response);

     /**
    * @dev Checks whether the guardianSet has zero keys
    * WARNING: This keys check is critical to ensure the guardianSet has keys present AND to ensure
    * that guardianSet key size doesn't fall to zero and negatively impact quorum assessment.  If guardianSet
    * key length is 0 and vm.signatures length is 0, this could compromise the integrity of both vm and
    * signature verification.
    */
    if(guardianSet.keys.length == 0)
      revert("invalid guardian set");

     /**
    * @dev We're using a fixed point number transformation with 1 decimal to deal with rounding.
    *   WARNING: This quorum check is critical to assessing whether we have enough Guardian signatures to validate a VM
    *   if making any changes to this, obtain additional peer review. If guardianSet key length is 0 and
    *   vm.signatures length is 0, this could compromise the integrity of both vm and signature verification.
    */
    if (signatures.length < wormhole.quorum(guardianSet.keys.length))
      revert("no quorum");

    /// @dev Verify the proposed vm.signatures against the guardianSet
    (bool signaturesValid, string memory invalidReason) =
      wormhole.verifySignatures(responseHash, signatures, guardianSet);
    if(!signaturesValid)
      revert(invalidReason);

    /// If we are here, we've validated the VM is a valid multi-sig that matches the current guardianSet.
  }

  /// @dev we use this over BytesParsing.checkLength to return our custom errors in all error cases
  function checkLength(bytes memory encoded, uint256 expected) private pure {
    if (encoded.length != expected)
      revert InvalidPayloadLength(encoded.length, expected);
  }
}

