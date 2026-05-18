# ``Gzip``

RFC 1952 gzip codec — decoder (v0.1) + one-shot encoder (v0.2) + streaming encoder (v0.3) + streaming decoder (v0.5, inherits true memory-streaming from swift-deflate v0.6 at v0.6+). Sendable, Foundation-free.

## Overview

`Gzip` provides both halves of RFC 1952:

- ``Gzip/decode(_:)`` — v0.1+. Parses the 10-byte header, skips optional fields (FEXTRA, FNAME, FCOMMENT, FHCRC), inflates the DEFLATE body via swift-deflate, validates the trailer's CRC32 and ISIZE. Multi-member streams (RFC 1952 § 2.2) decode to concatenated output.
- ``Gzip/encode(_:level:filename:modificationTime:)`` — v0.2+. Emits a single gzip member (one-shot): fixed header, optional null-terminated ASCII FNAME, DEFLATE body, CRC32 + ISIZE trailer.
- ``Gzip/Streaming/Encoder`` — v0.3+. Streaming compression: feed chunks via `update(_:)`, finalize with `finish()`.

```swift
import Gzip
import Bytes

let encoded = Gzip.encode(payload, level: .default, filename: "data.txt")
let back = try Gzip.decode(encoded)  // round-trip
```

**Streaming compress** (since v0.3):

```swift
var encoder = Gzip.Streaming.Encoder(level: .default, filename: "data.txt")
encoder.update(chunk1)
encoder.update(chunk2)
let gzipped = try encoder.finish()
```

Wraps `Deflate.Streaming.Encoder` for the DEFLATE body + an incremental
CRC32 over uncompressed bytes + ISIZE counter + gzip framing. Each
`update(_:)` feeds the chunk to the inner DEFLATE encoder, updates the
CRC, and increments ISIZE. `finish()` emits the full gzip stream.
Single-member output only.

Per [RFC-0014](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0014-phase-9-anchor-compression-encoder-sweep.md), v0.2 commits to **correctness** — zopfli-style size tuning lands as v0.2.x patch releases.

## Topics

### Decode (v0.1+)

- ``Gzip/decode(_:)``

### Encode (v0.2+)

- ``Gzip/encode(_:level:filename:modificationTime:)``
- ``Gzip/Encoder``
- ``Gzip/Encoder/Level``

### Streaming encode (v0.3+)

- ``Gzip/Streaming``
- ``Gzip/Streaming/Encoder``

### Errors

- ``GzipError``
