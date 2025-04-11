// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "wormhole-sdk/interfaces/IDeliveryProvider.sol";
import "wormhole-sdk/testing/WormholeRelayer/Structs.sol";
import "wormhole-sdk/WormholeRelayer/Keys.sol";
import "wormhole-sdk/libraries/TypedUnits.sol";

contract DeliveryProviderStub is IDeliveryProvider {
  using WormholeRelayerStructsLib for bytes;

  struct PeerData {
    bytes32 peer;
    uint nativePrice;
    uint gasPrice;
  }

  uint256 private constant SUPPORTED_KEYS_BITMAP =
    (1 << WormholeRelayerKeysLib.KEY_TYPE_VAA) +
    (1 << WormholeRelayerKeysLib.KEY_TYPE_CCTP);

  mapping(uint16 => PeerData) private _peerData;
  
  uint256 private _localNativePrice;

  constructor(uint256 localNativePrice) {
    _localNativePrice = localNativePrice;
  }

  function addPeer(
    uint16 targetChain,
    bytes32 peer,
    uint256 nativePrice,
    uint256 gasPrice
  ) external virtual {
    _peerData[targetChain] = PeerData(peer, nativePrice, gasPrice);
  }

  function quoteDeliveryPrice(
    uint16 targetChain,
    uint256 targetNativeAmount,
    bytes memory encodedExecutionParams
  ) external view virtual returns (
    uint256 nativePriceQuote,
    bytes memory encodedExecutionInfo
  ) {
    (uint256 targetNativePrice, uint256 gasPrice) = _getPeerData(targetChain);

    uint gasLimit = encodedExecutionParams.decodeEvmExecutionParamsV1().gasLimit;
    nativePriceQuote =
      (targetNativeAmount + gasLimit * gasPrice) * targetNativePrice / _localNativePrice;

    encodedExecutionInfo = EvmExecutionInfoV1(gasLimit, gasPrice).encode();
  }

  function quoteAssetConversion(
    uint16 targetChain,
    uint256 localNativeAmount
  ) external view virtual returns (uint256 targetNativeAmount) {
    (uint256 targetNativePrice, ) = _getPeerData(targetChain);
    targetNativeAmount = localNativeAmount * _localNativePrice / targetNativePrice;
  }

  function getRewardAddress() external view virtual returns (address payable rewardAddress) {
    return payable(address(this));
  }

  function isChainSupported(uint16 targetChain) external view virtual returns (bool supported) {
    return _peerData[targetChain].peer != bytes32(0);
  }

  function isMessageKeyTypeSupported(
    uint8 keyType
  ) external view virtual returns (bool supported) { unchecked {
    return getSupportedKeys() & (1 << keyType) != 0;
  }}

  function getSupportedKeys() public view virtual returns (uint256 bitmap) { unchecked {
    return SUPPORTED_KEYS_BITMAP;
  }}

  function getTargetChainAddress(
    uint16 targetChain
  ) external view virtual returns (bytes32 deliveryProviderAddress) {
    return _peerData[targetChain].peer;
  }

  receive() external payable virtual {}

  function _getPeerData(
    uint16 targetChain
  ) internal view virtual returns (uint256 nativePrice, uint256 gasPrice) {
    PeerData memory peerData = _peerData[targetChain];
    require(peerData.peer != bytes32(0), "Invalid peer");
    nativePrice = peerData.nativePrice;
    gasPrice = peerData.gasPrice;
  }
}
