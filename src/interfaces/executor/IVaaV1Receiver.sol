// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

//from https://github.com/wormholelabs-xyz/example-messaging-executor/blob/ec5daea3c03f8860a62c23e28db5c6dc8771a9ce/evm/src/interfaces/IVaaV1Receiver.sol
//any contract that wishes to receive V1 VAAs from the executor needs to implement `IVaaV1Receiver`.
interface IVaaV1Receiver {
    function executeVAAv1(bytes memory msg) external payable;
}
