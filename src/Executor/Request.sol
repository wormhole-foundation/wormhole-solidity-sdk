// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

//see: https://github.com/wormholelabs-xyz/example-messaging-executor/blob/ec5daea3c03f8860a62c23e28db5c6dc8771a9ce/evm/src/libraries/ExecutorMessages.sol
//and also: https://github.com/wormhole-foundation/wormhole-sdk-ts/blob/0379af2b0562c832bf4d2ff3d866ffca2ac92aae/core/definitions/src/protocols/executor/api.ts#L46

library RequestLib {
  bytes4 internal constant REQ_VAA_V1  = "ERV1";
  bytes4 internal constant REQ_NTT_V1  = "ERN1";
  bytes4 internal constant REQ_CCTP_V1 = "ERC1";
  bytes4 internal constant REQ_CCTP_V2 = "ERC2";

  function encodeVaaMultiSigRequest(
    uint16  emitterChain,
    bytes32 emitterAddress,
    uint64  sequence
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(REQ_VAA_V1, emitterChain, emitterAddress, sequence);
  }

  //messageId specifies the manager message id for the NTT transfer
  //for VAAs that's just the sequence number
  function encodeNttRequest(
    uint16  srcChain,
    bytes32 srcManager,
    bytes32 messageId
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(REQ_NTT_V1, srcChain, srcManager, messageId);
  }

  function encodeCctpV1Request(
    uint32 srcDomain,
    uint64 nonce
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(REQ_CCTP_V1, srcDomain, nonce);
  }

  //this request currently assumes the Executor will auto detect the event off chain.
  //that may change in the future, in which case this interface would change.
  function encodeCctpV2Request() internal pure returns (bytes memory) {
    return abi.encodePacked(REQ_CCTP_V2, uint8(1));
  }
}
