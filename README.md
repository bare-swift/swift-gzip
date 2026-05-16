# swift-gzip

RFC 1952 gzip codec — decoder (v0.1) + one-shot encoder (v0.2) + streaming encoder (v0.3). Sendable, Foundation-free; wraps swift-deflate.

Part of the [bare-swift](https://github.com/bare-swift) ecosystem.

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/bare-swift/swift-gzip.git", from: "0.3.0")
```

Then depend on the `Gzip` product:

```swift
.product(name: "Gzip", package: "swift-gzip")
```

## Usage

### Decode (v0.1+)

```swift
import Gzip
import Bytes

// .gz file contents or HTTP body with Content-Encoding: gzip
let gzipped: Bytes = ...
let plain = try Gzip.decode(gzipped)
```

### Encode (v0.2+)

```swift
import Gzip
import Bytes

let payload: Bytes = ...
let gzipped = Gzip.encode(payload, level: .default, filename: "data.txt")
// Round-trip property: Gzip.decode(gzipped) == payload
```

### Streaming encode (v0.3+)

```swift
import Gzip
import Bytes

var encoder = Gzip.Streaming.Encoder(level: .default, filename: "data.txt")
encoder.update(chunk1)
encoder.update(chunk2)
let gzipped = try encoder.finish()
let plain = try Gzip.decode(gzipped)
// plain == chunk1 + chunk2
```

`Gzip.Streaming.Encoder` wraps `Deflate.Streaming.Encoder` (swift-deflate
v0.3) for the body + an incremental CRC32 over uncompressed bytes + an
ISIZE byte counter + gzip header/trailer framing. Each `update(_:)` feeds
the chunk to the inner DEFLATE encoder, updates the CRC, and increments
ISIZE. Empty chunks are no-ops. `finish()` emits the full gzip stream
(header + DEFLATE body + 8-byte CRC32 + ISIZE trailer). After `finish()`
the encoder is consumed — further `update(_:)` calls are silent no-ops;
another `finish()` throws `encoderFinished`.

Single-member gzip output only (RFC 1952 § 2.2 multi-member encoded
streams remain out of scope; the decoder still supports multi-member
input from v0.1).

Levels pass straight through to swift-deflate:

- `.none` — stored blocks; no compression.
- `.fast` — fixed Huffman; lowest CPU.
- `.default` — dynamic Huffman; balanced (recommended default).
- `.best` — dynamic Huffman + lazy matching; smallest output.

## Scope

`swift-gzip` v0.2 ships **both halves** of RFC 1952:

- Decoder: header parse + DEFLATE body (via swift-deflate) + CRC32/ISIZE trailer validation. Multi-member streams (RFC 1952 § 2.2) are accepted on decode.
- Encoder: 10-byte fixed header, optional null-terminated ASCII FNAME, DEFLATE body (via swift-deflate v0.2), CRC32 + ISIZE trailer. Single-member only on encode.

Public API:

- `Gzip.decode(_:) throws(GzipError) -> Bytes`
- `Gzip.encode(_:level:filename:modificationTime:) -> Bytes`
- `Gzip.Encoder` value type with `.encode(_:)` method.
- `Gzip.Encoder.Level` (typealias for `Deflate.Encoder.Level`).
- `GzipError` typed-throws enum (9 cases).

## Dependencies

- `swift-deflate` 0.2.0 — DEFLATE codec (inflate + deflate).
- `swift-bytes` 0.1.0 — input/output buffer.
- `swift-crc` 0.1.0 — CRC-32/ISO-HDLC.

## Out of scope for v0.2

- **Multi-member encoded streams** (RFC 1952 § 2.2). v0.2 produces single-member output only.
- **FCOMMENT, FEXTRA, FHCRC fields on encode.** v0.2 emits only FNAME (when supplied + ASCII).
- **Non-ASCII filenames** — the FNAME field is restricted to ASCII per RFC 1952 § 2.3.1.4's note that the field is OS-specific.
- **Streaming encoding.**
- `Codable` bridging — same Foundation-free / non-Codable differentiator as the rest of the ecosystem.

## Documentation

Full DocC documentation: <https://bare-swift.github.io/swift-gzip/>

## Source

No upstream Rust crate; this is a native bare-swift package implementing RFC 1952 directly.

## License

Apache 2.0 with LLVM exception. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
