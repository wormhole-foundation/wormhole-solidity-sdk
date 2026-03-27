# Wormhole Solidity SDK Invariants & Footguns

This document enumerates caller-facing invariants (explicit and implicit) that integrators must follow to avoid security and correctness issues.

## 1) Parsing + Memory Safety Invariants

| Invariant | Explicit / Implicit | Why it exists / failure mode | Anchor |
|---|---|---|---|
| `*Unchecked` parsers do **no** bounds checks | Explicit | Out-of-bounds decode can read garbage/zeroed memory and produce bogus parsed fields | `src/libraries/BytesParsing.sol` (`Unchecked` helpers) |
| Even "checked" parsing in `BytesParsing` does **not** protect arithmetic overflow | Explicit | `offset + length` overflow can wrap and defeat intended bounds logic if caller inputs are untrusted/unbounded | `src/libraries/BytesParsing.sol` (`checkOffsetLength`) |
| Canonical safe pattern is: parse with `Unchecked` then enforce final consumed length | Explicit | Without terminal `checkLength`, trailing bytes are silently accepted | `src/libraries/BytesParsing.sol` (`checkLength` usage examples) |
| `UncheckedIndexing.writeUnchecked` assumes narrow values are pre-cleaned | Explicit | Dirty upper bits for non-word types (`uint128`, etc.) can corrupt later logic | `src/libraries/UncheckedIndexing.sol` (`writeUnchecked`) |
| `keccak256SliceUnchecked` requires caller-supplied safe `(offset,length)` | Explicit | Can hash unintended memory region if caller miscomputes bounds | `src/utils/Keccak.sol` (`keccak256SliceUnchecked`) |

## 2) VAA / Signature / Replay Invariants

| Invariant | Explicit / Implicit | Why it exists / failure mode | Anchor |
|---|---|---|---|
| Do not confuse VAA single-hash vs double-hash semantics | Explicit | EVM CoreBridge VM hash is double-hash; most other contexts use single-hash | `src/libraries/VaaLib.sol` (hash helpers) |
| Sequence replay protection only for finalized VAAs | Explicit | Using sequence bitmap for non-finalized flows gives bad replay guarantees | `src/libraries/ReplayProtection.sol` (sequence bitmap) |
| Hash replay protection in this SDK uses canonical single-hash | Explicit | Feeding CoreBridge `VM.hash` instead mismatches replay keys | `src/libraries/ReplayProtection.sol` (hash-based protection) |
| Verifying signatures is not replay protection | Implicit | `decodeAndVerifyVaa*` checks authenticity, not one-time consumption | `src/libraries/CoreBridge.sol`, `src/Executor/Integration.sol` (VAA verification helpers) |
| Guardian signatures must be strictly ascending by guardian index | Explicit | Prevents duplicate guardian signatures counting toward quorum | `src/libraries/CoreBridge.sol` (guardian loop) |

## 3) Cross-Chain Trust Invariants

| Invariant | Explicit / Implicit | Why it exists / failure mode | Anchor |
|---|---|---|---|
| Always verify emitter is a known peer | Explicit | Otherwise spoofed cross-chain messages can execute as trusted input | `src/Executor/Integration.sol` (`_checkPeer`) |
| For targeted messages, enforce destination-chain in payload | Explicit | VAA header has no destination; message may replay on other chains | `src/Executor/Integration.sol` (`_checkDestination`) |
| In relayer receiver, `_isPeer` is mandatory trust gate | Explicit | Weak peer logic breaks trust model | `src/WormholeRelayer/Receiver.sol` (`_isPeer` override) |
| `unpackAdditionalCctpMessage` assumes exact ABI tuple layout | Implicit | Malformed blobs can decode to nonsense if schema checks are skipped | `src/WormholeRelayer/AdditionalMessages.sol` (`unpackAdditionalCctpMessage`) |

## 4) Payable / Value-Flow Invariants

| Invariant | Explicit / Implicit | Why it exists / failure mode | Anchor |
|---|---|---|---|
| Executor receive path is payable; non-zero `msg.value` handling is on integrator | Explicit | Default impl rejects non-zero value; unsafe override can cause stuck-value bugs | `src/Executor/Integration.sol` (`receiveWormholeMessages`) |
| `totalCost` must include executor cost + Wormhole publish fee | Explicit | Underfunding causes failure; unchecked subtraction used | `src/Executor/Integration.sol` (`_quoteDeliveryPrice`, `totalCost`) |
| `RawDispatcher.exec768()` is payable catch-all | Explicit | Must manually enforce per-operation payability/value logic | `src/RawDispatcher.sol`, `docs/RawDispatcher.md` (payability guidance) |
| `tokenOrNativeTransfer` forwards all gas on native sends | Explicit | Enables gas griefing/reentrancy surfaces | `src/utils/Transfer.sol` (`tokenOrNativeTransfer`) |

## 5) Proxy / Upgrade Invariants

| Invariant | Explicit / Implicit | Why it exists / failure mode | Anchor |
|---|---|---|---|
| Storage in implementations must use slot-pattern discipline | Explicit | Unsafe layout handling across upgrades can corrupt state | `docs/Proxy.md` (storage patterns section) |
| Overriding `_proxyConstructor` must explicitly validate `msg.value` | Explicit | Proxy constructor is payable; missed checks can accept unintended ETH | `src/proxy/ProxyBase.sol` (`_proxyConstructor`) |
| `_upgradeTo` requires code-bearing, non-identical implementation | Explicit | Prevents idempotent upgrades / EOA implementation addresses | `src/proxy/ProxyBase.sol` (`_upgradeTo`) |
| No rollback/version sequencing safety rails | Explicit | Faulty or skipped upgrades can brick contract state | `docs/Proxy.md` (upgrade caveats) |
| `checkedUpgrade` context split (`msg.sender == address(this)`) is critical | Implicit | Misunderstanding init-vs-upgrade flow can break auth/initialization | `src/proxy/ProxyBase.sol` (`checkedUpgrade`) |

## 6) ERC20 / Address Normalization Invariants

| Invariant | Explicit / Implicit | Why it exists / failure mode | Anchor |
|---|---|---|---|
| SDK `SafeERC20` intentionally skips EXTCODESIZE check | Explicit | Calls to EOAs can appear successful at call level | `src/libraries/SafeERC20.sol` (all wrappers) |
| `fromUniversalAddress` requires top 12 bytes zero for EVM address | Explicit | Non-EVM universal addresses revert | `src/utils/UniversalAddress.sol` (`fromUniversalAddress`) |
| TokenBridge amounts are normalized to 8 decimals in payload format | Implicit | Treating normalized amount as token-native decimals causes accounting drift | `src/libraries/TokenBridgeMessages.sol`, `src/utils/DecimalNormalization.sol` (normalization helpers) |

## 7) Build / Compiler Invariants

| Invariant | Explicit / Implicit | Why it exists / failure mode | Anchor |
|---|---|---|---|
| Some components assume/use `via-ir` behavior | Explicit | Dispatch/gas and stack behavior assumptions differ under codegen modes | `README.md` (build matrix), `docs/RawDispatcher.md` |
| Non-Shanghai chains may require `evm_version = "paris"` | Explicit | `PUSH0` incompatibility can break deploy/runtime | `README.md` (chain compatibility notes) |
| Re-run tests with your exact compiler/settings | Explicit | Inline assembly + optimizer deltas can produce integration-only failures | `README.md` (testing guidance) |

# Integrator Must-Do Checklist

- Enforce peer checks and destination checks for inbound cross-chain messages.
- Pair signature verification with replay protection (sequence for finalized, hash otherwise).
- If using `Unchecked` helpers, always enforce terminal bounds/length checks.
- In proxy flows, validate `msg.value` and upgrade sequencing/migration assumptions.
- In RawDispatcher flows, manually enforce payability and calldata schema invariants.
