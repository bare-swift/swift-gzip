// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes
import Deflate
import CRC

extension Gzip.Streaming {
    /// Streaming gzip encoder (RFC 1952). Feed chunks via ``update(_:)``
    /// and terminate with ``finish()``. The encoder wraps a
    /// `Deflate.Streaming.Encoder` for the body + an incremental CRC32
    /// + ISIZE counter over uncompressed bytes + gzip header / trailer
    /// framing.
    ///
    /// Usage:
    /// ```swift
    /// var encoder = Gzip.Streaming.Encoder(level: .default)
    /// encoder.update(chunk1)
    /// encoder.update(chunk2)
    /// let gzipped = try encoder.finish()
    /// let plain = try Gzip.decode(gzipped)
    /// // plain == chunk1 + chunk2
    /// ```
    ///
    /// `Encoder` is a value type. Copying mid-stream produces two
    /// divergent encoders. Treat as single-owner.
    ///
    /// After ``finish()`` the encoder is in the finished state.
    /// ``update(_:)`` after finish is a silent no-op; double-finish throws
    /// ``GzipError/encoderFinished``.
    ///
    /// Single-member gzip output only (RFC 1952 § 2.2 multi-member encoded
    /// streams are out of scope for v0.3).
    public struct Encoder: Sendable {
        public typealias Level = Deflate.Encoder.Level

        private enum State: Sendable {
            case open
            case finished
        }

        public let level: Level
        public let filename: String?
        public let modificationTime: UInt32

        private var headerBytes: ContiguousArray<UInt8>
        private var headerEmitted: Bool  // v0.4: track whether drain() has emitted the header
        private var deflateEncoder: Deflate.Streaming.Encoder
        private var crc: CRC.Digest<UInt32>
        private var isize: UInt64
        private var state: State

        public init(
            level: Level = .default,
            filename: String? = nil,
            modificationTime: UInt32 = 0
        ) {
            self.level = level
            self.filename = filename
            self.modificationTime = modificationTime
            self.headerBytes = Self.buildHeader(
                level: level,
                filename: filename,
                modificationTime: modificationTime
            )
            self.headerEmitted = false
            self.deflateEncoder = Deflate.Streaming.Encoder(level: level)
            self.crc = CRC.Digest(algorithm: .iso_hdlc)
            self.isize = 0
            self.state = .open
        }

        /// Feed a chunk. Updates the inner DEFLATE encoder, the running
        /// CRC32 over uncompressed bytes, and the ISIZE counter. Empty
        /// chunk = no-op. Silent no-op when called after ``finish()``.
        public mutating func update(_ chunk: Bytes) {
            guard case .open = state else { return }
            if chunk.isEmpty { return }
            deflateEncoder.update(chunk)
            crc.update(chunk.storage)
            isize &+= UInt64(chunk.storage.count)
        }

        /// Return the byte-aligned portion of the accumulated stream so far,
        /// resetting the internal byte buffer. The encoder remains in the
        /// open state — subsequent ``update(_:)`` and ``finish()`` calls
        /// produce the remainder of the stream (including the CRC32 +
        /// ISIZE trailer at finish).
        ///
        /// The first `drain()` call emits the gzip header (10-byte fixed
        /// header + optional FNAME) followed by the drained DEFLATE bytes.
        /// Subsequent drains return only DEFLATE bytes (header already
        /// emitted).
        ///
        /// CRC32 + ISIZE state accumulates across drain calls — drain does
        /// NOT touch the checksum. The trailer is emitted only at `finish()`.
        ///
        /// Concatenating all `drain()` returns with the final `finish()`
        /// return produces the **same bytes** as a single `finish()` call
        /// would have produced (byte-for-byte equality).
        ///
        /// Silent no-op (returns empty `Bytes`) when called after `finish()`.
        ///
        /// Added in v0.4 for multi-coding HTTP streaming composition.
        public mutating func drain() -> Bytes {
            guard case .open = state else { return Bytes() }
            var out = ContiguousArray<UInt8>()
            if !headerEmitted {
                out.append(contentsOf: headerBytes)
                headerEmitted = true
            }
            let deflateBytes = deflateEncoder.drain()
            out.append(contentsOf: deflateBytes.storage)
            return Bytes(out)
        }

        /// Finalize the gzip stream: emit header (if not already emitted via
        /// drain) + remaining DEFLATE body + CRC32 + ISIZE trailer. Throws
        /// ``GzipError/encoderFinished`` on double-call.
        public mutating func finish() throws(GzipError) -> Bytes {
            guard case .open = state else { throw .encoderFinished }
            state = .finished

            let deflateBytes: Bytes
            do {
                deflateBytes = try deflateEncoder.finish()
            } catch {
                throw .malformedDeflate(error)
            }

            var out = ContiguousArray<UInt8>()
            out.reserveCapacity(headerBytes.count + deflateBytes.storage.count + 8)
            if !headerEmitted {
                out.append(contentsOf: headerBytes)
                headerEmitted = true
            }
            out.append(contentsOf: deflateBytes.storage)

            // CRC32 LE.
            let crcValue = crc.finalize()
            out.append(UInt8(truncatingIfNeeded: crcValue & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (crcValue >> 8) & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (crcValue >> 16) & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (crcValue >> 24) & 0xFF))

            // ISIZE LE (RFC 1952 § 2.3.1 — input.count mod 2^32).
            let isize32 = UInt32(truncatingIfNeeded: isize)
            out.append(UInt8(truncatingIfNeeded: isize32 & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (isize32 >> 8) & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (isize32 >> 16) & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (isize32 >> 24) & 0xFF))

            return Bytes(out)
        }

        // MARK: - Header

        private static func buildHeader(
            level: Level,
            filename: String?,
            modificationTime: UInt32
        ) -> ContiguousArray<UInt8> {
            var out = ContiguousArray<UInt8>()
            let asciiFilename = filename.flatMap { Self.asAsciiCString($0) }
            out.reserveCapacity(10 + (asciiFilename?.count ?? 0) + 1)

            // RFC 1952 § 2.3.1 — 10-byte fixed header.
            out.append(0x1F)
            out.append(0x8B)
            out.append(0x08)  // CM = 8 (DEFLATE)
            let flg: UInt8 = (asciiFilename != nil) ? 0x08 : 0x00
            out.append(flg)
            out.append(UInt8(truncatingIfNeeded: modificationTime & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (modificationTime >> 8) & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (modificationTime >> 16) & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (modificationTime >> 24) & 0xFF))
            let xfl: UInt8 = {
                switch level {
                case .best: return 2
                case .fast: return 4
                default:    return 0
                }
            }()
            out.append(xfl)
            out.append(0xFF)  // OS = unknown

            if let bytes = asciiFilename {
                out.append(contentsOf: bytes)
                out.append(0x00)
            }
            return out
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
}

extension Gzip.Streaming {
    /// Streaming gzip decoder. Feed compressed chunks via ``update(_:)``
    /// and finalize with ``finish()``. The decoder mirrors
    /// ``Gzip/Streaming/Encoder``'s shape for API symmetry.
    ///
    /// **v0.5 implementation note (honest scope under limitation):** the
    /// decoder buffers all compressed input bytes internally and runs
    /// ``Gzip/decode(_:)`` one-shot at `finish()`. The decoded output is
    /// not yielded incrementally during `update(_:)`. True memory-
    /// streaming gzip decode requires a state-machine refactor of the
    /// underlying ``Deflate/Streaming/Decoder`` (v0.5 buffering wrap) →
    /// `Deflate.Streaming.Decoder` v0.6+ would enable it; gzip v0.6 would
    /// inherit. v0.5 ships the streaming-symmetric API surface today.
    ///
    /// Multi-member gzip streams (RFC 1952 § 2.2) decode to concatenated
    /// output (inherited from ``Gzip/decode(_:)``).
    ///
    /// `Decoder` is a value type. Copying mid-stream produces two
    /// divergent decoders. Treat as single-owner.
    ///
    /// After ``finish()`` the decoder is in the finished state.
    /// ``update(_:)`` after finish is a silent no-op; double-finish throws
    /// ``GzipError/decoderFinished``.
    ///
    /// Added in v0.5 per RFC-0036.
    public struct Decoder: Sendable {
        private enum State: Sendable {
            case open
            case finished
        }

        private var buffer: ContiguousArray<UInt8>
        private var state: State

        public init() {
            self.buffer = ContiguousArray<UInt8>()
            self.state = .open
        }

        /// Feed a chunk of compressed input. Empty chunk = no-op.
        /// Silent no-op when called after ``finish()``.
        public mutating func update(_ chunk: Bytes) {
            guard case .open = state else { return }
            if chunk.isEmpty { return }
            buffer.append(contentsOf: chunk.storage)
        }

        /// Finalize the stream: parse gzip header, decompress DEFLATE body,
        /// verify CRC32 + ISIZE trailer. Return decompressed output.
        /// Throws ``GzipError/decoderFinished`` on double-call; throws
        /// other `GzipError` cases (badMagic, crc32Mismatch, isizeMismatch,
        /// truncated, malformedDeflate, etc.) if the buffered input is not
        /// a valid gzip stream.
        public mutating func finish() throws(GzipError) -> Bytes {
            guard case .open = state else { throw .decoderFinished }
            state = .finished
            return try Gzip.decode(Bytes(buffer))
        }
    }
}
