// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

//see https://github.com/wormholelabs-xyz/example-messaging-executor/blob/ec5daea3c03f8860a62c23e28db5c6dc8771a9ce/evm/src/interfaces/IExecutor.sol

event RequestForExecution(
  address indexed quoterAddress,
  uint256 amtPaid,
  uint16  dstChain,
  bytes32 dstAddr,
  address refundAddr,
  bytes   signedQuote,
  bytes   requestBytes,
  bytes   relayInstructions
);

interface IExecutor {
  function requestExecution(
    uint16  dstChain,
    bytes32 dstAddr,
    address refundAddr,
    bytes calldata signedQuote,
    bytes calldata requestBytes,
    bytes calldata relayInstructions
  ) external payable;
}

//from https://github.com/wormholelabs-xyz/example-messaging-executor/blob/ec5daea3c03f8860a62c23e28db5c6dc8771a9ce/evm/src/interfaces/IVaaV1Receiver.sol
//required interface for receiving MultiSig (=V1) VAAs from the executor
interface IVaaV1Receiver {
  function executeVAAv1(bytes memory multiSigVaa) external payable;
}
