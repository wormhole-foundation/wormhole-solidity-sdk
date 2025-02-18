// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {WORD_SIZE} from "wormhole-sdk/constants/Common.sol";
import {BytesParsing} from "wormhole-sdk/libraries/BytesParsing.sol";

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
  uint offset = WORD_SIZE;
  uint length;
  (length,      offset) = BytesParsing.asUint256CdUnchecked(message, offset);
  (cctpMessage, offset) = BytesParsing.sliceCdUnchecked(message, offset, length);
  (length,      offset) = BytesParsing.asUint256CdUnchecked(message, offset);
  (attestation, offset) = BytesParsing.sliceCdUnchecked(message, offset, length);
  BytesParsing.checkLength(offset, message.length);
}
