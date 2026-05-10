// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes
import Deflate
import CRC

/// Sendable, Foundation-free [RFC 1952](https://www.rfc-editor.org/rfc/rfc1952.html)
/// gzip decoder. Wraps swift-deflate with the gzip header / trailer
/// framing and validates the CRC32 + ISIZE trailer fields.
///
/// `Gzip.decode(_:)` accepts a complete gzip member (or multiple
/// concatenated members per RFC 1952 § 2.2 — the decoded outputs are
/// concatenated).
///
/// ```swift
/// import Gzip
/// import Bytes
///
/// // .gz file contents (1F 8B 08 ... CRC32 ISIZE)
/// let gzipped: Bytes = ...
/// let plain = try Gzip.decode(gzipped)
/// ```
///
/// Per [RFC-0012](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0012-phase-7-anchor-http-body-codecs.md),
/// **v0.1 ships decoding only**. The encoder lands in v0.2 once
/// swift-deflate's DEFLATE encoder is stable.
public enum Gzip: Sendable {
    /// Decode a complete gzip stream. Multi-member streams (concatenated
    /// gzip members per RFC 1952 § 2.2) are accepted; decoded outputs are
    /// concatenated.
    public static func decode(_ bytes: Bytes) throws(GzipError) -> Bytes {
        try Decoder.decode(bytes)
    }
}
