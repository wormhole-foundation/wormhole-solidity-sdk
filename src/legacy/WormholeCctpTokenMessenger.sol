// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IERC20} from "IERC20/IERC20.sol";

import {
  ICoreBridge,
  CoreBridgeVM}              from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {IMessageTransmitter} from "wormhole-sdk/interfaces/cctp/IMessageTransmitter.sol";
import {ITokenMessenger}     from "wormhole-sdk/interfaces/cctp/ITokenMessenger.sol";
import {ITokenMinter}        from "wormhole-sdk/interfaces/cctp/ITokenMinter.sol";

import {toUniversalAddress,
        eagerAnd,
        eagerOr}                     from "wormhole-sdk/Utils.sol";
import {WormholeCctpMessageLib}      from "wormhole-sdk/legacy/WormholeCctpMessages.sol";
import {CONSISTENCY_LEVEL_FINALIZED} from "wormhole-sdk/constants/ConsistencyLevel.sol";

/**
 * @notice A way to associate a CCTP token burn message with a Wormhole message.
 * @dev To construct the contract, the addresses to the Wormhole Core Bridge and CCTP Token
 *   Messenger must be provided. Using the CCTP Token Messenger, the Message Transmitter and Token
 *   Minter are derived.
 *
 * NOTE: For more information on CCTP message formats, please refer to the following:
 * https://developers.circle.com/stablecoins/docs/message-format.
 */
abstract contract WormholeCctpTokenMessenger {
  using { toUniversalAddress } for address;

  /// @dev Parsing and verifying VAA reverted at the Wormhole Core Bridge contract level.
  error InvalidVaa();

  /**
   * @dev The CCTP message's source domain, destination domain and nonce must match the VAA's.
   * NOTE: This nonce is the one acting as the CCTP message sequence (and not the arbitrary one
   * specified when publishing Wormhole messages).
   */
  error CctpVaaMismatch(uint32, uint32, uint64);

  /// @dev The emitter of the VAA must match the expected emitter.
  error UnexpectedEmitter(bytes32, bytes32);

  /// @dev Wormhole Core Bridge contract address.
  ICoreBridge immutable _coreBridge;

  /// @dev Wormhole Chain ID. NOTE: This is NOT the EVM chain ID.
  uint16 immutable _chainId;

  /// @dev CCTP Message Transmitter contract interface.
  IMessageTransmitter immutable _messageTransmitter;

  /// @dev CCTP Token Messenger contract interface.
  ITokenMessenger immutable _tokenMessenger;

  /// @dev CCTP Token Minter contract interface.
  ITokenMinter immutable _tokenMinter;

  /// @dev CCTP domain for this network (configured by the CCTP Message Transmitter).
  uint32 immutable _localCctpDomain;

  constructor(address coreBridge, address cctpTokenMessenger) {
    _coreBridge = ICoreBridge(coreBridge);
    _chainId  = _coreBridge.chainId();

    _tokenMessenger     = ITokenMessenger(cctpTokenMessenger);
    _messageTransmitter = _tokenMessenger.localMessageTransmitter();
    _tokenMinter        = _tokenMessenger.localMinter();
    _localCctpDomain    = _messageTransmitter.localDomain();
  }

  /**
   * @dev A convenience method to set the token spending allowance for the CCTP Token Messenger,
   *  who will ultimately be burning the tokens.
   */
  function setTokenMessengerApproval(address token, uint256 amount) internal {
    IERC20(token).approve(address(_tokenMessenger), amount);
  }

  /**
   * @dev Method to burn tokens via CCTP Token Messenger and publish a Wormhole message associated
   * with the CCTP Token Burn message. The Wormhole message encodes a `Deposit` (ID == 1), which
   * has the same source domain, destination domain and nonce as the CCTP Token Burn message.
   *
   * NOTE: This method does not protect against re-entrancy here because it relies on the CCTP
   * Token Messenger to protect against any possible re-entrancy. We are leaning on the fact that
   * the Token Messenger keeps track of its local tokens, which are the only tokens it allows to
   * burn (and in turn, mint on another network).
   *
   * NOTE: The wormhole message fee is not required to be paid by the transaction sender (so an
   *  integrator can use ETH funds in his contract to pay for this fee if he wants to).
   */
  function burnAndPublish(
    bytes32 destinationCaller,
    uint32 destinationCctpDomain,
    address token,
    uint256 amount,
    bytes32 mintRecipient,
    uint32 wormholeNonce,
    bytes memory payload,
    uint256 wormholeFee
  ) internal returns (uint64 wormholeSequence, uint64 cctpNonce) {
    // Invoke Token Messenger to burn tokens and emit a CCTP token burn message.
    cctpNonce = _tokenMessenger.depositForBurnWithCaller(
      amount, destinationCctpDomain, mintRecipient, token, destinationCaller
    );

    // Publish deposit message via Wormhole Core Bridge.
    wormholeSequence = _coreBridge.publishMessage{value: wormholeFee}(
      wormholeNonce,
      WormholeCctpMessageLib.encodeDeposit(
        token.toUniversalAddress(),
        amount,
        _localCctpDomain, // sourceCctpDomain
        destinationCctpDomain,
        cctpNonce,
        msg.sender.toUniversalAddress(), // burnSource
        mintRecipient,
        payload
      ),
      CONSISTENCY_LEVEL_FINALIZED
    );
  }

  /**
   * @dev Method to verify and reconcile CCTP and Wormhole messages in order to mint tokens for
   * the encoded mint recipient. This method will revert with custom errors.
   * NOTE: This method does not require the caller to be the mint recipient. If your contract
   * requires that the mint recipient is the caller, you should add a check after calling this
   * method to see if msg.sender.toUniversalAddress() == mintRecipient.
   */
  function verifyVaaAndMint(
    bytes calldata encodedCctpMessage,
    bytes calldata cctpAttestation,
    bytes calldata encodedVaa
  ) internal returns (
    CoreBridgeVM memory vaa,
    bytes32 token,
    uint256 amount,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) {
    // First parse and verify VAA.
    vaa = _parseAndVerifyVaa(encodedVaa);

    // Decode the deposit message so we can match the Wormhole message with the CCTP message.
    uint32 sourceCctpDomain;
    uint32 destinationCctpDomain;
    uint64 cctpNonce;
    (
      token,
      amount,
      sourceCctpDomain,
      destinationCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      payload
    ) = WormholeCctpMessageLib.decodeDepositMem(vaa.payload);

    // Finally reconcile messages and mint tokens to the mint recipient.
    token = _matchMessagesAndMint(
      encodedCctpMessage,
      cctpAttestation,
      sourceCctpDomain,
      destinationCctpDomain,
      cctpNonce,
      token
    );
  }

  /**
   * @dev PLEASE USE `verifyVaaAndMint` INSTEAD. Method to verify and reconcile CCTP and Wormhole
   * messages in order to mint tokens for the encoded mint recipient. This method will revert with
   * Solidity's built-in Error(string).
   * NOTE: This method does not require the caller to be the mint recipient. If your contract
   * requires that the mint recipient is the caller, you should add a check after calling this
   * method to see if msg.sender.toUniversalAddress() == mintRecipient.
   */
  function verifyVaaAndMintLegacy(
    bytes calldata encodedCctpMessage,
    bytes calldata cctpAttestation,
    bytes calldata encodedVaa
  ) internal returns (
    CoreBridgeVM memory vaa,
    bytes32 token,
    uint256 amount,
    uint32 sourceCctpDomain,
    uint32 destinationCctpDomain,
    uint64 cctpNonce,
    bytes32 burnSource,
    bytes32 mintRecipient,
    bytes memory payload
  ) {
    // First parse and verify VAA.
    vaa = _parseAndVerifyVaa(encodedVaa);

    // Decode the deposit message so we can match the Wormhole message with the CCTP message.
    (
      token,
      amount,
      sourceCctpDomain,
      destinationCctpDomain,
      cctpNonce,
      burnSource,
      mintRecipient,
      payload
    ) = WormholeCctpMessageLib.decodeDepositMem(vaa.payload);

    // Finally reconcile messages and mint tokens to the mint recipient.
    token = _matchMessagesAndMint(
      encodedCctpMessage,
      cctpAttestation,
      sourceCctpDomain,
      destinationCctpDomain,
      cctpNonce,
      token
    );
  }

  /**
   * @dev For a given remote domain and token, fetch the corresponding local token, for which the
   * CCTP Token Minter has minting authority.
   */
  function fetchLocalToken(
    uint32 remoteDomain,
    bytes32 remoteToken
  ) internal view returns (bytes32 localToken) {
    localToken = _tokenMinter.remoteTokensToLocalTokens(
      keccak256(abi.encodePacked(remoteDomain, remoteToken))
    ).toUniversalAddress();
  }

  /**
   * @dev We encourage an integrator to use this method to make sure the VAA is emitted from one
   * that his contract trusts. Usually foreign emitters are stored in a mapping keyed off by
   * Wormhole Chain ID (uint16).
   *
   * NOTE: Reverts with `UnexpectedEmitter(bytes32, bytes32)`.
   */
  function requireEmitter(CoreBridgeVM memory vaa, bytes32 expectedEmitter) internal pure {
    if (eagerAnd(expectedEmitter != 0, vaa.emitterAddress != expectedEmitter))
      revert UnexpectedEmitter(vaa.emitterAddress, expectedEmitter);
  }

  // ----- private methods -----

  function _parseAndVerifyVaa(
    bytes calldata encodedVaa
  ) private view returns (CoreBridgeVM memory vaa) {
    bool valid;
    (vaa, valid, ) = _coreBridge.parseAndVerifyVM(encodedVaa);

    if (!valid)
      revert InvalidVaa();
  }

  function _matchMessagesAndMint(
    bytes calldata encodedCctpMessage,
    bytes calldata cctpAttestation,
    uint32 vaaSourceCctpDomain,
    uint32 vaaDestinationCctpDomain,
    uint64 vaaCctpNonce,
    bytes32 burnToken
  ) private returns (bytes32 mintToken) {
    // Confirm that the caller passed the correct message pair.
    {
      uint32 sourceDomain;
      uint32 destinationDomain;
      uint64 nonce;

      assembly ("memory-safe") {
        // NOTE: First four bytes is the CCTP message version.
        let ptr := calldataload(encodedCctpMessage.offset)

        // NOTE: There is no need to mask here because the types defined outside of this
        // block will already perform big-endian masking.

        // Source domain is bytes 4..8, so shift 24 bytes to the right.
        sourceDomain := shr(192, ptr)
        // Destination domain is bytes 8..12, so shift 20 bytes to the right.
        destinationDomain := shr(160, ptr)
        // Nonce is bytes 12..20, so shift 12 bytes to the right.
        nonce := shr(96, ptr)
      }

      //avoid short-circuiting (more gas and bytecode efficient)
      if (eagerOr(
        eagerOr(vaaSourceCctpDomain != sourceDomain, vaaDestinationCctpDomain != destinationDomain),
        vaaCctpNonce != nonce
      ))
        revert CctpVaaMismatch(sourceDomain, destinationDomain, nonce);
    }

    // Call the circle bridge to mint tokens to the recipient.
    _messageTransmitter.receiveMessage(encodedCctpMessage, cctpAttestation);

    // We should trust that this getter will not return the zero address because the TokenMinter
    // will have already minted the valid token for the mint recipient.
    mintToken = fetchLocalToken(vaaSourceCctpDomain, burnToken);
  }
}
