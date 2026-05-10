// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes
import Deflate
import CRC

/// RFC 1952 gzip decoder. Header + DEFLATE body + 8-byte trailer.
///
/// Single-member streams in v0.1; multi-member (RFC 1952 § 2.2) lands
/// in v0.2 alongside the encoder once swift-deflate exposes the
/// consumed-byte count.
enum Decoder {
    static func decode(_ bytes: Bytes) throws(GzipError) -> Bytes {
        let raw = bytes.storage
        if raw.count < 18 {  // 10-byte header + 8-byte trailer minimum
            throw .truncated
        }

        // RFC 1952 § 2.3.1.1 — magic + compression method.
        if raw[0] != 0x1F || raw[1] != 0x8B {
            throw .badMagic
        }
        if raw[2] != 8 {
            throw .unsupportedCompressionMethod(raw[2])
        }
        let flg = raw[3]
        if flg & 0xE0 != 0 {
            throw .reservedFlagBitsSet
        }
        // Bytes 4..7 = MTIME (LE), 8 = XFL, 9 = OS — we don't care about
        // any of these on decode.

        var cursor = 10

        // FEXTRA (FLG bit 2): XLEN (2 bytes LE) + XLEN bytes.
        if flg & 0x04 != 0 {
            guard cursor + 2 <= raw.count else { throw .truncated }
            let xlen = Int(raw[cursor]) | (Int(raw[cursor + 1]) << 8)
            cursor += 2
            guard cursor + xlen <= raw.count else { throw .truncated }
            cursor += xlen
        }

        // FNAME (FLG bit 3): zero-terminated.
        if flg & 0x08 != 0 {
            cursor = try skipZeroTerminated(raw, from: cursor)
        }

        // FCOMMENT (FLG bit 4): zero-terminated.
        if flg & 0x10 != 0 {
            cursor = try skipZeroTerminated(raw, from: cursor)
        }

        // FHCRC (FLG bit 1): 2 bytes — header CRC16 (low 16 bits of CRC32
        // of the header up to this point). We skip validation in v0.1 (the
        // outer CRC32 over uncompressed data is the load-bearing check).
        if flg & 0x02 != 0 {
            guard cursor + 2 <= raw.count else { throw .truncated }
            cursor += 2
        }

        // Trailer: last 8 bytes — CRC32 (4 LE) + ISIZE (4 LE).
        let trailerStart = raw.count - 8
        guard cursor <= trailerStart else { throw .truncated }

        let crc32Expected =
            UInt32(raw[trailerStart])
            | (UInt32(raw[trailerStart + 1]) << 8)
            | (UInt32(raw[trailerStart + 2]) << 16)
            | (UInt32(raw[trailerStart + 3]) << 24)

        let isizeExpected =
            UInt32(raw[trailerStart + 4])
            | (UInt32(raw[trailerStart + 5]) << 8)
            | (UInt32(raw[trailerStart + 6]) << 16)
            | (UInt32(raw[trailerStart + 7]) << 24)

        // Slice the DEFLATE body and inflate.
        var bodyBytes = Bytes(reservingCapacity: trailerStart - cursor)
        for i in cursor..<trailerStart {
            bodyBytes.append(raw[i])
        }
        let decompressed: Bytes
        do {
            decompressed = try Deflate.inflate(bodyBytes)
        } catch {
            throw .malformedDeflate(error)
        }

        // CRC32 of decompressed data per RFC 1952 § 2.3.1.2.
        let crc32Actual = CRC.compute(decompressed.storage, algorithm: .iso_hdlc)
        if crc32Actual != crc32Expected {
            throw .crc32Mismatch
        }

        // ISIZE = decompressed.count mod 2^32.
        let isizeActual = UInt32(truncatingIfNeeded: decompressed.count)
        if isizeActual != isizeExpected {
            throw .isizeMismatch
        }

        return decompressed
    }

    /// Advance past a zero-terminated header field. Throws if the buffer
    /// ends without a NUL byte.
    private static func skipZeroTerminated(
        _ raw: ContiguousArray<UInt8>, from start: Int
    ) throws(GzipError) -> Int {
        var i = start
        while i < raw.count {
            if raw[i] == 0 {
                return i + 1
            }
            i += 1
        }
        throw .unterminatedHeaderField
    }
}
