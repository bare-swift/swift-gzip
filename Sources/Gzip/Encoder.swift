// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes
import Deflate
import CRC

/// Internal driver for gzip encoding. Public entry is
/// ``Gzip/encode(_:level:filename:modificationTime:)``.
enum GzipEncoder {
    static func encode(
        _ input: Bytes,
        level: Deflate.Encoder.Level,
        filename: String?,
        modificationTime: UInt32
    ) -> Bytes {
        var out = ContiguousArray<UInt8>()
        out.reserveCapacity(input.storage.count + 32)

        // RFC 1952 § 2.3.1 — 10-byte fixed header.
        out.append(0x1F)
        out.append(0x8B)
        out.append(0x08)  // CM = 8 (DEFLATE)
        let asciiFilename = filename.flatMap { asAsciiCString($0) }
        let flg: UInt8 = (asciiFilename != nil) ? 0x08 : 0x00
        out.append(flg)
        out.append(UInt8(truncatingIfNeeded: modificationTime & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (modificationTime >> 8) & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (modificationTime >> 16) & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (modificationTime >> 24) & 0xFF))
        let xfl: UInt8
        switch level {
        case .best:    xfl = 2
        case .fast:    xfl = 4
        default:       xfl = 0
        }
        out.append(xfl)
        out.append(0xFF)  // OS = unknown

        if let bytes = asciiFilename {
            out.append(contentsOf: bytes)
            out.append(0x00)
        }

        // DEFLATE body.
        let compressed = Deflate.encode(input, level: level)
        out.append(contentsOf: compressed.storage)

        // Trailer: CRC32/ISO-HDLC over uncompressed input (LE), then ISIZE (LE).
        let crc = CRC.compute(input.storage, algorithm: .iso_hdlc)
        out.append(UInt8(truncatingIfNeeded: crc & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (crc >> 8) & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (crc >> 16) & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (crc >> 24) & 0xFF))
        let isize = UInt32(truncatingIfNeeded: input.storage.count)
        out.append(UInt8(truncatingIfNeeded: isize & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (isize >> 8) & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (isize >> 16) & 0xFF))
        out.append(UInt8(truncatingIfNeeded: (isize >> 24) & 0xFF))

        return Bytes(out)
    }

    /// Return the ASCII bytes of `s` iff every codepoint fits in 0x01..0x7F.
    /// Returns nil if any byte would not round-trip through the FNAME slot.
    private static func asAsciiCString(_ s: String) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(s.utf8.count)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v == 0 || v > 0x7F { return nil }
            out.append(UInt8(v))
        }
        return out
    }
}
