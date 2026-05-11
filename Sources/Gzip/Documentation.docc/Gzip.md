# ``Gzip``

RFC 1952 gzip codec — decoder (v0.1+) and encoder (v0.2+). Sendable, Foundation-free.

## Overview

`Gzip` provides both halves of RFC 1952:

- ``Gzip/decode(_:)`` — v0.1+. Parses the 10-byte header, skips optional fields (FEXTRA, FNAME, FCOMMENT, FHCRC), inflates the DEFLATE body via swift-deflate, validates the trailer's CRC32 and ISIZE. Multi-member streams (RFC 1952 § 2.2) decode to concatenated output.
- ``Gzip/encode(_:level:filename:modificationTime:)`` — v0.2+. Emits a single gzip member: fixed header, optional null-terminated ASCII FNAME, DEFLATE body, CRC32 + ISIZE trailer.

```swift
import Gzip
import Bytes

let encoded = Gzip.encode(payload, level: .default, filename: "data.txt")
let back = try Gzip.decode(encoded)  // round-trip
```

Per [RFC-0014](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0014-phase-9-anchor-compression-encoder-sweep.md), v0.2 commits to **correctness** — zopfli-style size tuning lands as v0.2.x patch releases.

## Topics

### Decode (v0.1+)

- ``Gzip/decode(_:)``

### Encode (v0.2+)

- ``Gzip/encode(_:level:filename:modificationTime:)``
- ``Gzip/Encoder``
- ``Gzip/Encoder/Level``

### Errors

- ``GzipError``
