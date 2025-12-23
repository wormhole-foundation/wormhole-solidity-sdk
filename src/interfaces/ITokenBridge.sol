// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

//slimmed down interface of TokenBridge (only integrator relevant functions)

interface ITokenBridge {
  event TransferRedeemed(
    uint16 indexed emitterChainId,
    bytes32 indexed emitterAddress,
    uint64 indexed sequence
  );

  // -- transfer functions --

  function wrapAndTransferETH(
    uint16 recipientChain,
    bytes32 recipient,
    uint256 arbiterFee, //no built-in relayer -> unused, always set to 0
    uint32 nonce
  ) external payable returns (uint64 sequence);

  function transferTokens(
    address token,
    uint256 amount,
    uint16 recipientChain,
    bytes32 recipient,
    uint256 arbiterFee, //no built-in relayer -> unused, always set to 0
    uint32 nonce
  ) external payable returns (uint64 sequence);

  function wrapAndTransferETHWithPayload(
    uint16 recipientChain,
    bytes32 recipient,
    uint32 nonce,
    bytes calldata payload
  ) external payable returns (uint64 sequence);

  function transferTokensWithPayload(
    address token,
    uint256 amount,
    uint16 recipientChain,
    bytes32 recipient,
    uint32 nonce,
    bytes calldata payload
  ) external payable returns (uint64 sequence);

  // -- completeTransfer functions --

  function completeTransfer(bytes calldata encodedVaa) external;
  function completeTransferAndUnwrapETH(bytes calldata encodedVaa) external;

  //transfers tokens to the recipient (must be msg.sender) and returns the payload of the transfer
  //use libraries/TokenBridgeMessages.sol to decode e.g. emitter chain and fromAddress if required
  function completeTransferWithPayload(bytes calldata encodedVaa) external returns (bytes memory);
  function completeTransferAndUnwrapETHWithPayload(
    bytes calldata encodedVaa
  ) external returns (bytes memory);

  // -- token attestation functions --

  function attestToken(address token, uint32 nonce) external payable returns (uint64 sequence);
  function createWrapped(bytes calldata encodedVaa) external returns (address token);
  function updateWrapped(bytes calldata encodedVaa) external returns (address token);

  // -- view functions --

  //convenience function that wraps the core bridge's chainId()
  function chainId() external view returns (uint16);
  //returns address of the core bridge
  function wormhole() external view returns (address);
  //returns universal address of peer contracts on other chains
  function bridgeContracts(uint16 chainId) external view returns (bytes32);
  //underlying implementation of the beacon
  function tokenImplementation() external view returns (address);
  //returns address of the canonical wrapped native token
  function WETH() external view returns (address);

  function isTransferCompleted(bytes32 hash) external view returns (bool);
  function isWrappedAsset(address token) external view returns (bool);
  function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) external view returns (address);
}
