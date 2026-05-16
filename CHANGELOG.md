# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] — 2026-05-17

### Added
- **`Gzip.Streaming.Encoder.drain() -> Bytes`** — returns the byte-aligned portion of the accumulated stream so far, resetting the internal byte buffer. The encoder remains in the open state; subsequent `update(_:)` and `finish()` calls produce the remainder (including the CRC32 + ISIZE trailer at finish). The **first** `drain()` call emits the gzip header (10-byte fixed header + optional FNAME) followed by the drained DEFLATE bytes; subsequent drains return only DEFLATE bytes. CRC32 + ISIZE state accumulates across drains (drain does NOT touch the checksum; trailer is emitted only at `finish()`).
- 6 new tests covering drain semantics (header-emitted-on-first-drain, subsequent-drain-empty), drain+finish round-trip, multiple-drain round-trip, drain-after-finish no-op, byte-equality with non-draining stream.

### Dependencies
- swift-deflate dep bumped 0.3.0 → 0.4.0 (for `Deflate.Streaming.Encoder.drain()`).

### Use case
Multi-coding HTTP `Content-Encoding` streaming via swift-content-encoding v0.6 (Phase 28+).

### Migration (v0.3 → v0.4)
- **Additive only — non-breaking.** All v0.3 APIs unchanged.
- Existing v0.3 streams (no `drain()` calls) produce byte-identical output to v0.3.
- `GzipError` cases unchanged.

### Phase 27
- Tranche 27C of [RFC-0032](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0032-phase-27-anchor-codec-tier-v0.4-drain-sweep.md). Codec-tier v0.4 drain() API sweep.

## [0.3.0] — 2026-05-16

### Added
- **Streaming encoder** — `Gzip.Streaming.Encoder` struct with `init(level:filename:modificationTime:)` / `update(_:)` / `finish()`. Wraps `Deflate.Streaming.Encoder` (swift-deflate v0.3) for the DEFLATE body + incremental CRC32 over uncompressed bytes via `CRC.Digest<UInt32>` + accumulating ISIZE counter + 10-byte gzip header (with optional FNAME) + 8-byte trailer (CRC32 LE + ISIZE LE).
- `Gzip.Streaming` public namespace enum.
- `GzipError.encoderFinished` — thrown when `finish()` is called on an already-finished encoder.
- 16 new tests covering round-trip (empty, single chunk, two chunks, 100 tiny chunks, 70 KiB chunk), all four levels, header metadata (filename + modificationTime), and error/edge cases (double-finish, update-after-finish no-op).

### Dependencies
- swift-deflate dep bumped 0.2.0 → 0.3.0 (for `Deflate.Streaming.Encoder`).

### Stream-format notes
- Streaming output is **valid gzip** that decodes via the same `Gzip.decode(_:)` v0.1 API and reference `gzip` CLI.
- Single-member gzip output only (RFC 1952 § 2.2 multi-member encoded streams remain out of scope; decoder still supports multi-member input from v0.1).
- No window carry across chunks in v0.3 (inherited from swift-deflate v0.3). LZ77 match search is per-chunk. Inherits when swift-deflate v0.4 lands.

### Migration (v0.2 → v0.3)
- **Additive only — non-breaking.** All v0.2 APIs unchanged.
- `Gzip.encode(_:level:filename:modificationTime:)` continues to emit byte-equal output to v0.2 (regression-tested via existing v0.2 round-trip tests).
- `Gzip.Encoder` struct unchanged.
- `Gzip.decode(_:)` unchanged from v0.1.
- `GzipError` adds 1 new case (additive; existing cases unchanged).

### Phase 24
- Tranche 24A of [RFC-0029](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0029-phase-24-anchor-gzip-zlib-v0.3-streaming-encoders.md). Continues codec-tier streaming sweep.

## [0.2.0] - 2026-05-11

### Added
- `Gzip.encode(_:level:filename:modificationTime:)` — RFC 1952 single-member gzip encoder. Wraps `Deflate.encode` (v0.2) with the 10-byte fixed header, optional null-terminated FNAME (ASCII only), and the 8-byte CRC32 + ISIZE trailer.
- `Gzip.Encoder` value type — single-shot encoder (streaming ships in v0.3).
- `Gzip.Encoder.Level` typealias for `Deflate.Encoder.Level` (`.none`/`.fast`/`.default`/`.best`).
- 17 new tests across 4 suites covering API surface, internal round-trip via v0.1 decoder, FNAME handling (including non-ASCII drop + NUL drop), and header-field byte-level correctness (MTIME LE, OS, XFL hint, ISIZE LE).

### Changed
- swift-deflate dep bumped from 0.1.0 to 0.2.0 (additive — unlocks `Deflate.encode`).

### Unchanged from v0.1
- `Gzip.decode(_:)` — bit-for-bit unchanged.
- `GzipError` cases — all nine v0.1 cases preserved.

### Limitations (out of scope for v0.2)
- Multi-member encoded streams (RFC 1952 § 2.2). v0.2 produces single-member output only.
- FCOMMENT, FEXTRA, FHCRC fields. v0.2 emits only FNAME (when supplied + ASCII).
- Non-ASCII filenames silently drop the FNAME slot rather than producing OS-specific encodings.
- Streaming encoding. v0.2 takes a single full `Bytes` input.

## [0.1.0] - 2026-05-10

### Added
- `Gzip.decode(_ bytes: Bytes) throws(GzipError) -> Bytes` — single-member RFC 1952 gzip decoder. Strips header, skips optional fields (FEXTRA, FNAME, FCOMMENT, FHCRC), inflates the DEFLATE body via swift-deflate, validates CRC32 + ISIZE.
- `GzipError` typed-throws enum (9 cases) including `crc32Mismatch`, `isizeMismatch`, and `malformedDeflate(DeflateError)` wrapping the inner DEFLATE error.
- 13 tests across 4 suites covering: empty payload, simple inputs ('abc', 'hello world', repeated 'a' with back-references), FNAME-flagged stream with embedded filename, and 7 error paths (truncation, bad magic, wrong CM, reserved FLG bits, CRC32 mismatch, ISIZE mismatch, unterminated FNAME).

All test vectors generated via `gzip -c -n` (and `gzip -c -N` for FNAME) on stable inputs.

### Dependencies
- `swift-deflate` 0.1.0 — DEFLATE inflater.
- `swift-bytes` 0.1.0 — input/output buffer.
- `swift-crc` 0.1.0 — CRC-32/ISO-HDLC for trailer validation.

### Limitations (out of scope for v0.1)
- **Encoder.** Per RFC-0012's staging pattern (decompression first), the gzip encoder lands in v0.2 alongside swift-deflate's DEFLATE encoder.
- **Multi-member streams** (RFC 1952 § 2.2). v0.1 takes a single member; multi-member lands in v0.2 once swift-deflate exposes a consumed-byte count for stream framing.
- **FHCRC validation.** The 2-byte field is parsed and skipped past; the outer CRC32 over uncompressed data is the load-bearing integrity check.
- `Codable` bridging — same Foundation-free / non-Codable differentiator as the rest of the ecosystem.
