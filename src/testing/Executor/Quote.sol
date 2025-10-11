// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

library QuoteLib {
  bytes4 internal constant QUOTE_PREFIX_V1 = "EQ01";

  //these are the fields that every quote must have because they are parsed by the Executor contract
  //see: https://github.com/wormholelabs-xyz/example-messaging-executor/blob/626f7e6e7a6a60c93070fa9c8373c1845fdcfe6e/evm/src/Executor.sol#L30-L54
  function encodeQuoteHeader(
    address quoter,
    address payee, //encoded as UniversalAddress but for EVM always an EVM address
    uint16 srcChain,
    uint16 dstChain,
    uint64 expiryTime
  ) internal pure returns (bytes memory) {
    bytes32 payee_ = bytes32(uint256(uint160(payee)));
    return abi.encodePacked(QUOTE_PREFIX_V1, quoter, payee_, srcChain, dstChain, expiryTime);
  }

  function encodeQuote(
    address quoter,
    address payee,
    uint16 srcChain,
    uint16 dstChain,
    uint64 expiryTime,
    bytes memory data
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(QUOTE_PREFIX_V1, quoter, payee, srcChain, dstChain, expiryTime, data);
  }

  //see https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/main/core/definitions/src/protocols/executor/signedQuote.ts
  function encodeQuote(
    address quoter,
    address payee,
    uint16 srcChain,
    uint16 dstChain,
    uint64 expiryTime,
    uint64 baseFee,
    uint64 dstGasPrice,
    uint64 srcPrice,
    uint64 dstPrice
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      encodeQuoteHeader(quoter, payee, srcChain, dstChain, expiryTime),
      baseFee,
      dstGasPrice,
      srcPrice,
      dstPrice
    );
  }
}
