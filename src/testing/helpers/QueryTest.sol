// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

//build Cross Chain Query (CCQ) responses for testing purposes.
library QueryTest {
  error SolanaTooManyPDAs();
  error SolanaTooManySeeds();
  error SolanaSeedTooLong();

  //According to the spec, there may be at most 16 seeds.
  // https://github.com/gagliardetto/solana-go/blob/6fe3aea02e3660d620433444df033fc3fe6e64c1/keys.go#L559
  uint public constant SOLANA_MAX_SEEDS = 16;

  //According to the spec, a seed may be at most 32 bytes.
  // https://github.com/gagliardetto/solana-go/blob/6fe3aea02e3660d620433444df033fc3fe6e64c1/keys.go#L557
  uint public constant SOLANA_MAX_SEED_LEN = 32;

  // --- Query Request ---

  function buildOffChainQueryRequestBytes(
    uint8 version,
    uint32 nonce,
    uint8 numPerChainQueries,
    bytes memory perChainQueries
  ) internal pure returns (bytes memory){
    return abi.encodePacked(
      version,
      nonce,
      numPerChainQueries,
      perChainQueries // Each created by buildPerChainRequestBytes()
    );
  }

  function buildPerChainRequestBytes(
    uint16 chainId,
    uint8 queryType,
    bytes memory queryBytes
  ) internal pure returns (bytes memory){
    return abi.encodePacked(chainId, queryType, uint32(queryBytes.length), queryBytes);
  }

  function buildEthCallRequestBytes(
    bytes memory blockId,
    uint8 numCallData,
    bytes memory callData // Created with buildEthCallRecordBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(uint32(blockId.length), blockId, numCallData, callData);
  }

  function buildEthCallByTimestampRequestBytes(
    uint64 targetTimeUs,
    bytes memory targetBlockHint,
    bytes memory followingBlockHint,
    uint8 numCallData,
    bytes memory callData // Created with buildEthCallRecordBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(
      targetTimeUs,
      uint32(targetBlockHint.length),
      targetBlockHint,
      uint32(followingBlockHint.length),
      followingBlockHint,
      numCallData,
      callData
    );
  }

  function buildEthCallWithFinalityRequestBytes(
    bytes memory blockId,
    bytes memory finality,
    uint8 numCallData,
    bytes memory callData // Created with buildEthCallRecordBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(
      uint32(blockId.length),
      blockId,
      uint32(finality.length),
      finality,
      numCallData,
      callData
    );
  }

  function buildEthCallRecordBytes(
    address contractAddress,
    bytes memory callData
  ) internal pure returns (bytes memory){
    return abi.encodePacked(contractAddress, uint32(callData.length), callData);
  }

  function buildSolanaAccountRequestBytes(
    bytes memory commitment,
    uint64 minContextSlot,
    uint64 dataSliceOffset,
    uint64 dataSliceLength,
    uint8 numAccounts,
    bytes memory accounts // Each account is 32 bytes.
  ) internal pure returns (bytes memory){
    return abi.encodePacked(
      uint32(commitment.length),
      commitment,
      minContextSlot,
      dataSliceOffset,
      dataSliceLength,
      numAccounts,
      accounts
    );
  }

  function buildSolanaPdaRequestBytes(
    bytes memory commitment,
    uint64 minContextSlot,
    uint64 dataSliceOffset,
    uint64 dataSliceLength,
    bytes[] memory pdas // Created with multiple calls to buildSolanaPdaEntry()
  ) internal pure returns (bytes memory){
    uint numPdas = pdas.length;
    if (numPdas > type(uint8).max)
      revert SolanaTooManyPDAs();

    bytes memory result = abi.encodePacked(
      uint32(commitment.length),
      commitment,
      minContextSlot,
      dataSliceOffset,
      dataSliceLength,
      uint8(numPdas)
    );

    for (uint idx; idx < numPdas;) {
      result = abi.encodePacked(result, pdas[idx]);

      unchecked { ++idx; }
    }

    return result;
  }

  function buildSolanaPdaEntry(
    bytes32 programId,
    uint8 numSeeds,
    bytes memory seeds // Created with buildSolanaPdaSeedBytes()
  ) internal pure returns (bytes memory){
    if (numSeeds > SOLANA_MAX_SEEDS)
      revert SolanaTooManySeeds();

    return abi.encodePacked(programId, numSeeds, seeds);
  }

  //packs the seeds for a PDA entry into an array of bytes.
  function buildSolanaPdaSeedBytes(
    bytes[] memory seeds
  ) internal pure returns (bytes memory, uint8){
    uint numSeeds = seeds.length;
    if (numSeeds > SOLANA_MAX_SEEDS)
      revert SolanaTooManySeeds();

    bytes memory result;

    for (uint idx; idx < numSeeds;) {
      uint seedLen = seeds[idx].length;
      if (seedLen > SOLANA_MAX_SEED_LEN)
        revert SolanaSeedTooLong();

      result = abi.encodePacked(result, abi.encodePacked(uint32(seedLen), seeds[idx]));

      unchecked { ++idx; }
    }

    return (result, uint8(numSeeds));
  }

  // --- Query Response ---

  function buildQueryResponseBytes(
    uint8 version,
    uint16 senderChainId,
    bytes memory signature,
    bytes memory queryRequest,
    uint8 numPerChainResponses,
    bytes memory perChainResponses
  ) internal pure returns (bytes memory){
    return abi.encodePacked(
      version,
      senderChainId,
      signature,
      uint32(queryRequest.length),
      queryRequest,
      numPerChainResponses,
      perChainResponses // Each created by buildPerChainResponseBytes()
    );
  }

  function buildPerChainResponseBytes(
    uint16 chainId,
    uint8 queryType,
    bytes memory responseBytes
  ) internal pure returns (bytes memory){
    return abi.encodePacked(chainId, queryType, uint32(responseBytes.length), responseBytes);
  }

  function buildEthCallResponseBytes(
    uint64 blockNumber,
    bytes32 blockHash,
    uint64 blockTimeUs,
    uint8 numResults,
    bytes memory results // Created with buildEthCallResultBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(blockNumber, blockHash, blockTimeUs, numResults, results);
  }

  function buildEthCallByTimestampResponseBytes(
    uint64 targetBlockNumber,
    bytes32 targetBlockHash,
    uint64 targetBlockTimeUs,
    uint64 followingBlockNumber,
    bytes32 followingBlockHash,
    uint64 followingBlockTimeUs,
    uint8 numResults,
    bytes memory results // Created with buildEthCallResultBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(
      targetBlockNumber,
      targetBlockHash,
      targetBlockTimeUs,
      followingBlockNumber,
      followingBlockHash,
      followingBlockTimeUs,
      numResults,
      results
    );
  }

  //Note this it is currently the same as buildEthCallResponseBytes.
  function buildEthCallWithFinalityResponseBytes(
    uint64 blockNumber,
    bytes32 blockHash,
    uint64 blockTimeUs,
    uint8 numResults,
    bytes memory results // Created with buildEthCallResultBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(blockNumber, blockHash, blockTimeUs, numResults, results);
  }

  function buildEthCallResultBytes(
    bytes memory result
  ) internal pure returns (bytes memory){
    return abi.encodePacked(uint32(result.length), result);
  }

  function buildSolanaAccountResponseBytes(
    uint64 slotNumber,
    uint64 blockTimeUs,
    bytes32 blockHash,
    uint8 numResults,
    bytes memory results // Created with buildEthCallResultBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(slotNumber, blockTimeUs, blockHash, numResults, results);
  }

  function buildSolanaPdaResponseBytes(
    uint64 slotNumber,
    uint64 blockTimeUs,
    bytes32 blockHash,
    uint8 numResults,
    bytes memory results // Created with buildEthCallResultBytes()
  ) internal pure returns (bytes memory){
    return abi.encodePacked(slotNumber, blockTimeUs, blockHash, numResults, results);
  }
}
