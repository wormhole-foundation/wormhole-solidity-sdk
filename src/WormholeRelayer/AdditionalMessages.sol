// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {WORD_SIZE} from "wormhole-sdk/constants/Common.sol";

// The `additionalMessages` parameter of `receiveWormholeMessages` contains the list of
//   VAAs, CCTP messages, and potentially other messages that were requested for delivery in
//   their speficied order.
//
// VAAs requested via VaaKey are delivered as normally encoded VAAs, just as one would expect.
//
// CCTP messages on the other hand do not include the associated attestation in their format but
//   instead expect the attestation to be provided separately.
// So the message associated with a CctpKey is a tuple of (CCTP message, attestation) and
//   `unpackAdditionalCctpMessage` can be used to extract them.
//
// To further decode VAAs or CctpMessages, check out the `VaaLib` and `CctpLib` libraries.
// To verify VAAs more efficiently, check out the `CoreBridge` library.

function unpackAdditionalCctpMessage(
  bytes calldata message
) pure returns (bytes calldata cctpMessage, bytes calldata attestation) {
  assembly ("memory-safe") {
    // message.offset points to ABI-encoded struct {bytes cctpMessage, bytes attestation}
    // First word is offset to cctpMessage bytes (always 0x40)
    // Second word is offset to attestation bytes
    let attestationRelativeOffset := calldataload(add(message.offset, WORD_SIZE))

    let cctpMessageLengthOffset := add(message.offset, 0x40)
    cctpMessage.offset := add(cctpMessageLengthOffset, WORD_SIZE)
    cctpMessage.length := calldataload(cctpMessageLengthOffset)

    let attestationLengthOffset := add(message.offset, attestationRelativeOffset)
    attestation.offset := add(attestationLengthOffset, WORD_SIZE)
    attestation.length := calldataload(attestationLengthOffset)
  }
}
