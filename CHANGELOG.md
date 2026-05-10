# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
