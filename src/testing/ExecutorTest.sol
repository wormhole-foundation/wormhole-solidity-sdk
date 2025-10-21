// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";

import "wormhole-sdk/testing/Constants.sol";
import "wormhole-sdk/testing/WormholeForkTest.sol";
import "wormhole-sdk/testing/LogUtils.sol";
import "wormhole-sdk/testing/WormholeOverride.sol";
import "wormhole-sdk/testing/CctpOverride.sol";

import "wormhole-sdk/interfaces/ICoreBridge.sol";
import "wormhole-sdk/interfaces/IExecutor.sol";
import "wormhole-sdk/interfaces/cctp/IMessageTransmitter.sol";

import "wormhole-sdk/Executor/Request.sol";
import "wormhole-sdk/Executor/RelayInstruction.sol";

import "wormhole-sdk/libraries/BytesParsing.sol";
import "wormhole-sdk/libraries/VaaLib.sol";
import "wormhole-sdk/libraries/CctpMessages.sol";

//see https://github.com/wormholelabs-xyz/example-messaging-executor?tab=readme-ov-file#off-chain-quote
//we don't actually need quotes for the purpose of testing, but mimic them here to stay in line
//  with real world applications
library QuoteLib {
  bytes4 internal constant QUOTE_PREFIX_V1 = "EQ01";

  function encodeQuote(
    bytes4 prefix,
    address quoter,
    address payee,
    uint16 srcChain,
    uint16 dstChain,
    uint64 expiryTime,
    bytes memory data
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(
      prefix,
      quoter,
      toUniversalAddress(payee),
      srcChain,
      dstChain,
      expiryTime,
      data
    );
  }

  function encodeV1Quote(
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
    bytes memory data = abi.encodePacked(baseFee, dstGasPrice, srcPrice, dstPrice);
    return encodeQuote(QUOTE_PREFIX_V1, quoter, payee, srcChain, dstChain, expiryTime, data);
  }

  function signAndPackQuote(
    bytes memory quote,
    uint256 quoterSecret
  ) internal pure returns (bytes memory) {
    bytes32 hash = keccak256(quote);
    (uint8 v, bytes32 r, bytes32 s) = Vm(VM_ADDRESS).sign(quoterSecret, hash);
    return abi.encodePacked(quote, r, s, v);
  }
}

struct GasDropOff {
  uint256 dropOff;
  bytes32 recipient;
}

struct ExecutionRequest {
  bytes4       requestType;
  bytes        requestData;
  uint16       dstChain;
  bytes32      dstAddr;
  //the IN MEMORY STRUCT REPRESENTATION, i.e. PublishedMessage or CctpTokenBurnMessage
  bytes        associatedMsgPtr;
  uint256      gasLimit;
  uint256      msgVal;
  GasDropOff[] gasDropOffs;
}

enum ExecutionStep {
  ContractCall,
  GasDropOff
}
error ExecutionError(ExecutionStep step, bytes errorData);

struct ExecutionResult {
  bool     success;
  bytes    data; //either the returned data or an ExecutionError "struct"
  Vm.Log[] logs;
  uint16   srcChain;
  uint16   dstChain;
  bytes32  dstAddr;
  bytes4   requestType;
  bytes    requestData;
  bytes    attestedMsg;
}

abstract contract ExecutorTest is WormholeForkTest {
  using AdvancedWormholeOverride   for ICoreBridge;
  using CctpOverride               for IMessageTransmitter;
  using BytesParsing               for bytes;
  using VaaLib                     for bytes;
  using CctpMessageLib             for bytes;
  using LogUtils                   for Vm.Log[];
  using {toUniversalAddress}       for address;
  using {fromUniversalAddress}     for bytes32;
  using {BytesParsing.checkLength} for uint;

  address internal immutable payee;
  address internal immutable quoter;
  uint256 internal immutable quoterSecret;

  ExecutionResult[] internal executionResults;

  constructor() {
    (quoter, quoterSecret) = makeAddrAndKey("quoter");
    payee = makeAddr("payee");
  }

  function craftSignedQuote(uint16 dstChain) internal view virtual returns (bytes memory) {
    //some hardcoded (but for the purpose of testing) meaningless values to generate a
    //  realistic-ish quote (correct size, non-zero values)
    uint64 expiryTime = uint64(block.timestamp + 1 hours);
    return QuoteLib.signAndPackQuote(
      QuoteLib.encodeV1Quote(quoter, payee, chainId(), dstChain, expiryTime, 1e9, 1e9, 1e9, 1e9),
      quoterSecret
    );
  }

  function getLastExecutionResult() internal view virtual returns (ExecutionResult memory) {
    return executionResults[executionResults.length - 1];
  }

  function executeRelay() internal virtual {
    executeRelay(vm.getRecordedLogs());
  }

  function executeRelay(Vm.Log[] memory logs) internal virtual {
    (ExecutionRequest[] memory requests) = logsToExecutionRequests(logs);

    for (uint i = 0; i < requests.length; ++i)
      executeRelay(requests[i]);
  }

  function executeRelay(ExecutionRequest memory request) internal virtual preserveFork {
    ExecutionResult memory executionResult;
    executionResult.srcChain    = chainId();
    executionResult.dstChain    = request.dstChain;
    executionResult.dstAddr     = request.dstAddr;
    executionResult.requestType = request.requestType;
    executionResult.requestData = request.requestData;

    selectFork(request.dstChain);

    address callee;
    bytes memory funcCall;
    if (request.requestType == RequestLib.REQ_VAA_V1) {
      bytes memory vaa = coreBridge().sign(_asPublishedMessage(request.associatedMsgPtr)).encode();

      callee = request.dstAddr.fromUniversalAddress();
      funcCall = abi.encodeCall(IVaaV1Receiver.executeVAAv1, (vaa));
      executionResult.attestedMsg = vaa;

    }
    else { //must be REQ_CCTP_V1
      CctpTokenBurnMessage memory cctpBurnMsg = _asCctpTokenBurnMessage(request.associatedMsgPtr);
      bytes memory cctpAttestation = cctpMessageTransmitter().sign(cctpBurnMsg);
      bytes memory cctpEncodedMsg = cctpBurnMsg.encode();

      callee = address(cctpMessageTransmitter());
      funcCall = abi.encodeCall(
        IMessageTransmitter.receiveMessage,
        (cctpEncodedMsg, cctpAttestation)
      );
      executionResult.attestedMsg = abi.encode(cctpEncodedMsg, cctpAttestation);
    }

    if (callee.code.length == 0)
      revert("Callee has no code");

    vm.recordLogs();

    (executionResult.success, executionResult.data) = address(this).call(
      abi.encodeCall(
        this.callAndMaybeDropOff,
        ( callee,
          funcCall,
          request.gasLimit != 0 ? request.gasLimit : type(uint128).max,
          request.msgVal,
          request.gasDropOffs
        )
      )
    );

    executionResult.logs = vm.getRecordedLogs();

    executionResults.push(executionResult);
  }

  function getExecutionRequest() internal virtual returns (ExecutionRequest memory) {
    ExecutionRequest[] memory requests = logsToExecutionRequests(vm.getRecordedLogs());
    require(requests.length == 1, "Expected exactly one request for execution");
    return requests[0];
  }

  function logsToExecutionRequests(
    Vm.Log[] memory logs
  ) internal view virtual returns (ExecutionRequest[] memory requests) {
    Vm.Log[] memory executorLogs = logs.filter(address(executor()), RequestForExecution.selector);
    PublishedMessage[] memory pms = coreBridge().fetchPublishedMessages(logs);
    CctpTokenBurnMessage[] memory burnMsgs = cctpMessageTransmitter().fetchBurnMessages(logs);

    requests = new ExecutionRequest[](executorLogs.length);
    for (uint i = 0; i < requests.length; ++i) {
      ( , //uint256 amtPaid
        uint16  dstChain,
        bytes32 dstAddr,
        , //address refundAddr
        , //bytes memory signedQuote
        bytes memory requestBytes,
        bytes memory relayInstructions
      ) = abi.decode(
        executorLogs[i].data,
        (uint256, uint16, bytes32, address, bytes, bytes, bytes)
      );

      (bytes4 requestType, uint offset) = requestBytes.asBytes4MemUnchecked(0);
      uint requestDataOffset = offset;
      bytes memory associatedMsgPtr;
      if (requestType == RequestLib.REQ_VAA_V1) {
        uint16 emitterChain; bytes32 emitterAddress; uint64 sequence;
        (emitterChain,   offset) = requestBytes.asUint16MemUnchecked(offset);
        (emitterAddress, offset) = requestBytes.asBytes32MemUnchecked(offset);
        (sequence,       offset) = requestBytes.asUint64MemUnchecked(offset);
        associatedMsgPtr =
          _asPtr(_findPublishedMessage(emitterChain, emitterAddress, sequence, pms));
      }
      else if (requestType == RequestLib.REQ_CCTP_V1) {
        uint32 domain; uint64 nonce;
        (domain, offset) = requestBytes.asUint32MemUnchecked(offset);
        (nonce,  offset) = requestBytes.asUint64MemUnchecked(offset);
        associatedMsgPtr =
          _asPtr(_findCctpMessage(domain, nonce, burnMsgs));
      }
      else
        revert("only VAA_V1 and CCTP_V1 requests are supported by ExecutorTest");

      requestBytes.length.checkLength(offset);
      bytes memory requestData;
      uint requestDataSize = offset - requestDataOffset;
      (requestData, offset) = requestBytes.sliceMemUnchecked(requestDataOffset, requestDataSize);

      (uint gasLimit, uint msgVal, GasDropOff[] memory gasDropOffs) =
        _decodeRelayInstructions(relayInstructions);

      requests[i] = ExecutionRequest(
        requestType,
        requestData,
        dstChain,
        dstAddr,
        associatedMsgPtr,
        gasLimit,
        msgVal,
        gasDropOffs
      );
    }
  }

  // ---- Implementation ----

  function callAndMaybeDropOff(
    address               contractAddr,
    bytes        calldata contractCall,
    uint                  gasLimit,
    uint                  msgVal,
    GasDropOff[] calldata gasDropOffs
  ) external virtual returns (bytes memory data) {
    bool success;
    (success, data) = contractAddr.call{gas: gasLimit, value: msgVal}(contractCall);
    if (!success)
      revert ExecutionError(ExecutionStep.ContractCall, data);

    for (uint i = 0; i < gasDropOffs.length; ++i) {
      address payable recipient = payable(gasDropOffs[i].recipient.fromUniversalAddress());
      bytes memory dropOffData;
      (success, dropOffData) = recipient.call{value: gasDropOffs[i].dropOff}("");
      if (!success)
        revert ExecutionError(
          ExecutionStep.GasDropOff,
          abi.encode(recipient, gasDropOffs[i].dropOff)
        );
    }
  }

  function _asPtr(PublishedMessage memory pm) private pure returns (bytes memory ret) {
    assembly ("memory-safe") { ret := pm }
  }

  function _asPtr(CctpTokenBurnMessage memory cctpMsg) private pure returns (bytes memory ret) {
    assembly ("memory-safe") { ret := cctpMsg }
  }

  function _asPublishedMessage(
    bytes memory ptr
  ) private pure returns (PublishedMessage memory pm) {
    assembly ("memory-safe") { pm := ptr }
  }

  function _asCctpTokenBurnMessage(
    bytes memory ptr
  ) private pure returns (CctpTokenBurnMessage memory cctpMsg) {
    assembly ("memory-safe") { cctpMsg := ptr }
  }

  function _findPublishedMessage(
    uint16  emitterChainId,
    bytes32 emitterAddress,
    uint64  sequence,
    PublishedMessage[] memory pms
  ) private pure returns (PublishedMessage memory) {
    for (uint k = 0; k < pms.length; ++k) {
      PublishedMessage memory pm = pms[k];
      if ((emitterChainId == pm.envelope.emitterChainId) &&
          (emitterAddress == pm.envelope.emitterAddress) &&
          (sequence       == pm.envelope.sequence      ))
        return pm;
    }

    revert("Failed to find published Wormhole message");
  }

  function _findCctpMessage(
    uint32 domain,
    uint64 nonce,
    CctpTokenBurnMessage[] memory cctpMessages
  ) private pure returns (CctpTokenBurnMessage memory) {
    for (uint k = 0; k < cctpMessages.length; ++k) {
      CctpTokenBurnMessage memory cctpMessage = cctpMessages[k];
      if ((domain == cctpMessage.header.sourceDomain) &&
          (nonce  == cctpMessage.header.nonce       ))
        return cctpMessage;
    }

    revert("Failed to find CCTP Message");
  }

  function _decodeRelayInstructions(
    bytes memory encoded
  ) private pure returns (
    uint totalGasLimit,
    uint totalMsgVal, //only from gas instructions, does not include gas drop offs
    GasDropOff[] memory gasDropOffs
  ) { unchecked {
    uint dropoffRequests = 0;
    uint offset = 0;
    while (offset < encoded.length) {
      uint8 instructionType;
      (instructionType, offset) = encoded.asUint8MemUnchecked(offset);
      if (instructionType == RelayInstructionLib.RECV_INST_TYPE_GAS) {
        uint gasLimit; uint msgVal;
        (gasLimit, offset) = encoded.asUint128MemUnchecked(offset);
        (msgVal,   offset) = encoded.asUint128MemUnchecked(offset);
        totalGasLimit += gasLimit;
        totalMsgVal   += msgVal;
      }
      else if (instructionType == RelayInstructionLib.RECV_INST_TYPE_DROP_OFF) {
        offset += 48; // 16 dropOff amount + 32 universal recipient
        ++dropoffRequests;
      }
      else
        revert("Invalid instruction type");
    }
    encoded.length.checkLength(offset);

    if (dropoffRequests > 0) {
      gasDropOffs = new GasDropOff[](dropoffRequests);
      offset = 0;
      uint requestIndex = 0;
      uint uniqueRecipientCount = 0;
      while (true) {
        uint8 instructionType;
        (instructionType, offset) = encoded.asUint8MemUnchecked(offset);
        if (instructionType == RelayInstructionLib.RECV_INST_TYPE_GAS)
          offset += 32; // 16 gas limit + 16 msg val
        else {
          //must be RECV_INST_TYPE_DROP_OFF
          uint dropOff; bytes32 recipient;
          (dropOff,   offset) = encoded.asUint128MemUnchecked(offset);
          (recipient, offset) = encoded.asBytes32MemUnchecked(offset);
          uint i = 0;
          for (; i < uniqueRecipientCount; ++i)
            if (gasDropOffs[i].recipient == recipient) {
              gasDropOffs[i].dropOff += dropOff;
              break;
            }
          if (i == uniqueRecipientCount) {
            gasDropOffs[i] = GasDropOff(dropOff, recipient);
            ++uniqueRecipientCount;
          }

          ++requestIndex;
          if (requestIndex == dropoffRequests)
            break;
        }
      }
      assembly ("memory-safe") {
        mstore(gasDropOffs, uniqueRecipientCount)
      }
    }
  }}
}
