# swift-gzip

RFC 1952 gzip decoder — Sendable, Foundation-free; wraps swift-deflate.

Part of the [bare-swift](https://github.com/bare-swift) ecosystem.

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/bare-swift/swift-gzip.git", from: "0.1.0")
```

Then depend on the `Gzip` product:

```swift
.product(name: "Gzip", package: "swift-gzip")
```

## Usage

```swift
import Gzip
import Bytes

// .gz file contents or HTTP body with Content-Encoding: gzip
let gzipped: Bytes = ...
let plain = try Gzip.decode(gzipped)
```

## Scope

`swift-gzip` v0.1 implements RFC 1952 single-member gzip decoding:

- 10-byte fixed header (magic `1F 8B`, CM=8, FLG, MTIME, XFL, OS).
- Optional fields skipped per FLG bits: FEXTRA, FNAME, FCOMMENT, FHCRC.
- DEFLATE body decompressed via swift-deflate.
- 8-byte trailer validated: CRC32 (computed via swift-crc CRC-32/ISO-HDLC) + ISIZE (size mod 2^32).

Public API:

- `Gzip.decode(_ bytes: Bytes) throws(GzipError) -> Bytes` — single-shot.
- `GzipError` typed-throws enum (9 cases including `truncated`, `badMagic`, `unsupportedCompressionMethod`, `crc32Mismatch`, `isizeMismatch`, `malformedDeflate(DeflateError)` wrapping the inner error).

## Dependencies

- `swift-deflate` 0.1.0 — the DEFLATE inflater.
- `swift-bytes` 0.1.0 — input/output buffer.
- `swift-crc` 0.1.0 — CRC-32/ISO-HDLC.

## Out of scope for v0.1

- **Encoder.** Per RFC-0012's staging pattern (decompression first), the gzip encoder lands in v0.2 alongside swift-deflate's DEFLATE encoder.
- **Multi-member streams** (RFC 1952 § 2.2). Concatenated gzip members are accepted by `gzip` and `gunzip` but rare in HTTP. v0.1 takes a single member; multi-member lands in v0.2 once swift-deflate exposes a consumed-byte count for stream framing.
- **FHCRC (header CRC16) validation.** The 2-byte field is parsed and skipped past; the outer CRC32 over uncompressed data is the load-bearing integrity check.
- `Codable` bridging — same Foundation-free / non-Codable differentiator as the rest of the ecosystem.

## Documentation

Full DocC documentation: <https://bare-swift.github.io/swift-gzip/>

## Source

No upstream Rust crate; this is a native bare-swift package implementing RFC 1952 directly.

## License

Apache 2.0 with LLVM exception. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
