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

extension Gzip {
    /// RFC 1952 gzip compression entry point. Produces a single gzip
    /// member with the supplied (optional) filename and modification time.
    ///
    /// Per [RFC-0014](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0014-phase-9-anchor-compression-encoder-sweep.md),
    /// v0.2 commits to *correctness* — zopfli-style size tuning is out of
    /// scope and will land as v0.2.x patch releases.
    public static func encode(
        _ input: Bytes,
        level: Encoder.Level = .default,
        filename: String? = nil,
        modificationTime: UInt32 = 0
    ) -> Bytes {
        Encoder(level: level, filename: filename, modificationTime: modificationTime)
            .encode(input)
    }

    /// RFC 1952 gzip encoder. Single-shot in v0.2; streaming ships in v0.3.
    public struct Encoder: Sendable {
        /// Compression level — passed straight through to swift-deflate.
        public typealias Level = Deflate.Encoder.Level

        public let level: Level
        /// Optional original filename embedded in the gzip header (FNAME).
        /// Restricted to ASCII per RFC 1952 § 2.3.1.4 (the field is
        /// OS-specific — we don't try to be clever about other encodings).
        public let filename: String?
        /// MTIME field. 0 means "no time stamp available" per spec.
        public let modificationTime: UInt32

        public init(
            level: Level = .default,
            filename: String? = nil,
            modificationTime: UInt32 = 0
        ) {
            self.level = level
            self.filename = filename
            self.modificationTime = modificationTime
        }

        public func encode(_ input: Bytes) -> Bytes {
            GzipEncoder.encode(
                input,
                level: level,
                filename: filename,
                modificationTime: modificationTime
            )
        }
    }
}
