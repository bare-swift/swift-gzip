# ``Gzip``

RFC 1952 gzip decoder — Sendable, Foundation-free; wraps swift-deflate.

## Overview

`Gzip.decode(_:)` strips the RFC 1952 gzip header / trailer, calls
`Deflate.inflate(_:)` on the body, and validates the trailer's CRC32 +
ISIZE fields against the decompressed data.

```swift
import Gzip
import Bytes

// .gz file contents (1F 8B 08 ... CRC32 ISIZE)
let gzipped: Bytes = ...
let plain = try Gzip.decode(gzipped)
```

Optional gzip header fields (FEXTRA, FNAME, FCOMMENT, FHCRC) are
skipped past on read. The 16-bit FHCRC is parsed but not validated in
v0.1 — the outer CRC32 over uncompressed data is the load-bearing
integrity check.

Per [RFC-0012](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0012-phase-7-anchor-http-body-codecs.md),
**v0.1 ships single-member decoding only**. Multi-member streams
(RFC 1952 § 2.2 — concatenated gzip members) and the encoder land in
v0.2.

## Topics

### Essentials

- ``GzipError``
