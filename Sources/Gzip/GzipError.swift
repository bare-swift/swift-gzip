// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Deflate

/// Errors thrown by ``Gzip/decode(_:)``.
public enum GzipError: Error, Equatable, Sendable {
    /// Decoder ran out of bytes mid-header / mid-trailer / mid-member.
    case truncated

    /// First two bytes were not `1F 8B` per RFC 1952 § 2.3.1.
    case badMagic

    /// `CM` field carried a value other than `8`. Only DEFLATE is defined.
    case unsupportedCompressionMethod(UInt8)

    /// `FLG` carried bits 5–7 set (reserved per RFC 1952 § 2.3.1.2).
    case reservedFlagBitsSet

    /// Trailer's CRC32 didn't match the computed CRC32 of the
    /// decompressed data.
    case crc32Mismatch

    /// Trailer's ISIZE didn't match `decompressed.count & 0xFFFFFFFF`.
    case isizeMismatch

    /// Optional FNAME or FCOMMENT field had no NUL terminator before EOF.
    case unterminatedHeaderField

    /// FHCRC was set and the header CRC16 didn't match.
    case headerCRCMismatch

    /// Wrapped DEFLATE-level error from swift-deflate.
    case malformedDeflate(DeflateError)

    /// Encoder: ``Gzip/Streaming/Encoder/finish()`` was called twice on
    /// the same encoder.
    case encoderFinished
}
