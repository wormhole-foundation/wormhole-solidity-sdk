// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.4;

import "wormhole-sdk/libraries/SafeERC20.sol";
import "wormhole-sdk/WormholeRelayer.sol";
import "wormhole-sdk/testing/WormholeRelayerTest.sol";

contract WormholeRelayerTestIntegration is WormholeRelayerReceiver {
  using { toUniversalAddress } for address;
  using WormholeRelayerKeysLib for VaaKey;
  using WormholeRelayerKeysLib for CctpKey;

  struct Peer {
    address peer;
    uint32 cctpDomain;
  }

  address private immutable _wormholeRelayer;
  address private immutable _token;
  address private immutable _tokenBridge;
  address private immutable _usdc;
  address private immutable _cctpTokenMessenger;
  address private immutable _coreBridge;

  uint16 private immutable _chainId;

  address private owner;

  mapping(uint16 => Peer) private _peers;

  constructor(
    address wormholeRelayer,
    address token,
    address tokenBridge,
    address usdc,
    address cctpTokenMessenger
  ) WormholeRelayerReceiver(wormholeRelayer) {
    _wormholeRelayer    = wormholeRelayer;
    _token              = token;
    _tokenBridge        = tokenBridge;
    _usdc               = usdc;
    _cctpTokenMessenger = cctpTokenMessenger;
    _coreBridge         = ITokenBridge(_tokenBridge).wormhole();

    _chainId = ICoreBridge(_coreBridge).chainId();
    owner = msg.sender;

    //more gas efficient to approve only once
    IERC20(_usdc).approve(_cctpTokenMessenger, type(uint256).max);
    //no need to use SafeERC20 forceApprove here, allowance must be zero upon construction
    IERC20(_token).approve(_tokenBridge, type(uint256).max);
  }

  function registerPeer(uint16 chainId, address peerAddress, uint32 cctpDomain) external {
    require(msg.sender == owner, "Unauthorized");
    _peers[chainId] = Peer(peerAddress, cctpDomain);
  }

  function bulkTransfer(
    uint16 targetChain,
    address recipient,
    uint256 tokenAmount,
    uint256 usdcAmount
  ) external payable {
    Peer memory peerData = _peers[targetChain];
    bytes32 peer = peerData.peer.toUniversalAddress();
    require(peer != bytes32(0), "No peer on target chain");

    uint additionalMessagesCount = (tokenAmount > 0 ? 1 : 0) + (usdcAmount > 0 ? 1 : 0);
    MessageKey[] memory messageKeys = new MessageKey[](additionalMessagesCount);
    uint messageKeysIndex = 0;
    if (tokenAmount > 0) {
      SafeERC20.safeTransferFrom(IERC20(_token), msg.sender, address(this), tokenAmount);

      //use a transfer with payload to enforce that only our peer can redeem the transfer
      uint64 sequence =
        ITokenBridge(_tokenBridge).transferTokensWithPayload{
          value: ICoreBridge(_coreBridge).messageFee()
        }(
          _token,
          tokenAmount,
          targetChain,
          peer,
          0,
          bytes("")
        );

      messageKeys[messageKeysIndex++] = MessageKey(
        WormholeRelayerKeysLib.KEY_TYPE_VAA,
        VaaKey(_chainId, _tokenBridge.toUniversalAddress(), sequence).encode()
      );
    }
    if (usdcAmount > 0) {
      SafeERC20.safeTransferFrom(IERC20(_usdc), msg.sender, address(this), usdcAmount);

      //use a transfer with payload to enforce that only our peer can redeem the transfer
      uint64 sequence =
        ITokenMessenger(_cctpTokenMessenger).depositForBurnWithCaller(
          usdcAmount,
          peerData.cctpDomain,
          recipient.toUniversalAddress(),
          _usdc,
          peer
        );

      messageKeys[messageKeysIndex++] = MessageKey(
        WormholeRelayerKeysLib.KEY_TYPE_CCTP,
        CctpKey(peerData.cctpDomain, sequence).encode()
      );
    }

    //TODO implement
  }

  function _isPeer(uint16 chainId, bytes32 peerAddress) internal view override returns (bool) {
    return _peers[chainId].peer.toUniversalAddress() == peerAddress;
  }

  function _handleDelivery(
    bytes   calldata payload,
    bytes[] calldata additionalMessages,
    uint16,
    bytes32,
    bytes32
  ) internal override {
    // TODO: Implement
  }
}
