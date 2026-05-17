// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import Testing
import Bytes
@testable import Gzip

@Suite("Streaming encoder")
struct StreamingTests {
    // MARK: - Helpers

    private static func bytesFromString(_ s: String) -> Bytes {
        var b = Bytes()
        b.append(contentsOf: Array(s.utf8))
        return b
    }

    private static func bytesFromArray(_ a: [UInt8]) -> Bytes {
        var b = Bytes()
        b.append(contentsOf: a)
        return b
    }

    // MARK: - Round-trip

    @Test("empty stream round-trips to empty Bytes")
    func emptyStream() throws {
        var encoder = Gzip.Streaming.Encoder()
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(plain.storage.count == 0)
    }

    @Test("single chunk round-trips")
    func singleChunkRoundTrip() throws {
        let payload = Self.bytesFromString("hello")
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("two chunks round-trip to concatenation")
    func twoChunkRoundTrip() throws {
        let chunk1 = Self.bytesFromString("hel")
        let chunk2 = Self.bytesFromString("lo")
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(chunk1)
        encoder.update(chunk2)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array("hello".utf8))
    }

    @Test("many tiny 1-byte chunks round-trip")
    func manyTinyChunks() throws {
        let payload: [UInt8] = (0..<100).map { UInt8($0 & 0xFF) }
        var encoder = Gzip.Streaming.Encoder()
        for byte in payload {
            encoder.update(Self.bytesFromArray([byte]))
        }
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == payload)
    }

    @Test("large 70 KiB chunk round-trips")
    func largeChunk() throws {
        let size = 70 * 1024
        let payload = [UInt8](repeating: 0x41, count: size)
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(Self.bytesFromArray(payload))
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(plain.storage.count == size)
        #expect(Array(plain.storage) == payload)
    }

    @Test("mixed-size chunks round-trip")
    func mixedSizeChunks() throws {
        let pangram = Self.bytesFromString("The quick brown fox jumps over the lazy dog. ")
        let small = Self.bytesFromString("XY")
        let medium = Self.bytesFromArray([UInt8](repeating: 0x42, count: 256))
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(pangram)
        encoder.update(small)
        encoder.update(medium)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        let expected = Array(pangram.storage) + Array(small.storage) + Array(medium.storage)
        #expect(Array(plain.storage) == expected)
    }

    @Test("empty chunk in middle is a no-op")
    func emptyChunkInMiddle() throws {
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(Self.bytesFromString("a"))
        encoder.update(Bytes())
        encoder.update(Self.bytesFromString("b"))
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array("ab".utf8))
    }

    // MARK: - Level coverage

    @Test(".none level round-trip")
    func levelNone() throws {
        let payload = Self.bytesFromString("hello world")
        var encoder = Gzip.Streaming.Encoder(level: .none)
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test(".fast level round-trip")
    func levelFast() throws {
        let payload = Self.bytesFromString("The quick brown fox jumps over the lazy dog.")
        var encoder = Gzip.Streaming.Encoder(level: .fast)
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test(".default level round-trip")
    func levelDefault() throws {
        let payload = Self.bytesFromString("The quick brown fox jumps over the lazy dog.")
        var encoder = Gzip.Streaming.Encoder(level: .default)
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test(".best level round-trip")
    func levelBest() throws {
        let payload = Self.bytesFromArray([UInt8](repeating: 0x5A, count: 1024))
        var encoder = Gzip.Streaming.Encoder(level: .best)
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    // MARK: - Header metadata

    @Test("filename round-trips via FNAME flag")
    func filenameInHeader() throws {
        var encoder = Gzip.Streaming.Encoder(filename: "test.txt")
        encoder.update(Self.bytesFromString("payload"))
        let compressed = try encoder.finish()
        // FLG byte is at offset 3; FNAME bit is 0x08.
        #expect(compressed.storage[3] & 0x08 == 0x08)
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array("payload".utf8))
    }

    @Test("modificationTime round-trips in MTIME field")
    func mtimeInHeader() throws {
        let mtime: UInt32 = 0x12345678
        var encoder = Gzip.Streaming.Encoder(modificationTime: mtime)
        encoder.update(Self.bytesFromString("x"))
        let compressed = try encoder.finish()
        // MTIME is bytes 4..7 LE.
        let actual: UInt32 =
            UInt32(compressed.storage[4]) |
            (UInt32(compressed.storage[5]) << 8) |
            (UInt32(compressed.storage[6]) << 16) |
            (UInt32(compressed.storage[7]) << 24)
        #expect(actual == mtime)
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array("x".utf8))
    }

    // MARK: - Error / edge cases

    @Test("double-finish throws encoderFinished")
    func doubleFinishThrows() throws {
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(Self.bytesFromString("data"))
        _ = try encoder.finish()
        do {
            _ = try encoder.finish()
            Issue.record("expected throw")
        } catch GzipError.encoderFinished {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - Drain (v0.4)

    @Test("drain() on fresh encoder emits gzip header (10 bytes minimum)")
    func drainFreshEmitsHeader() throws {
        var encoder = Gzip.Streaming.Encoder()
        let drained = encoder.drain()
        // First drain emits the 10-byte gzip header even with no body yet.
        #expect(drained.storage.count >= 10)
        #expect(drained.storage[0] == 0x1F)
        #expect(drained.storage[1] == 0x8B)
    }

    @Test("second drain() with no update between is empty (header already emitted)")
    func secondDrainEmpty() throws {
        var encoder = Gzip.Streaming.Encoder()
        _ = encoder.drain()  // emits header
        let second = encoder.drain()
        #expect(second.storage.count == 0)
    }

    @Test("drain() after update emits header + deflate bytes; finish completes trailer")
    func drainConcatRoundTrip() throws {
        let payload = Self.bytesFromString("hello world hello world")
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(payload)
        let drained = encoder.drain()
        let final = try encoder.finish()

        // Drain should have emitted the gzip header (10 bytes).
        #expect(drained.storage.count >= 10)
        #expect(drained.storage[0] == 0x1F)
        #expect(drained.storage[1] == 0x8B)

        var combined = Bytes()
        combined.append(contentsOf: drained.storage)
        combined.append(contentsOf: final.storage)
        let plain = try Gzip.decode(combined)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("multiple drains: only first emits header; trailer emitted at finish")
    func multipleDrains() throws {
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(Self.bytesFromString("first"))
        var collected = Bytes()
        let d1 = encoder.drain()
        collected.append(contentsOf: d1.storage)
        // First drain emits header.
        #expect(d1.storage.count >= 10)
        #expect(d1.storage[0] == 0x1F)

        encoder.update(Self.bytesFromString("second"))
        let d2 = encoder.drain()
        collected.append(contentsOf: d2.storage)
        // Second drain does NOT re-emit header — these bytes are not the gzip magic prefix.
        // (We can't check d2[0] for "not 0x1F" because deflate output can incidentally start
        // with 0x1F. Instead, check overall round-trip succeeds.)

        encoder.update(Self.bytesFromString("third"))
        collected.append(contentsOf: encoder.drain().storage)
        collected.append(contentsOf: (try encoder.finish()).storage)

        let plain = try Gzip.decode(collected)
        #expect(Array(plain.storage) == Array("firstsecondthird".utf8))
    }

    @Test("drain after finish is silent no-op")
    func drainAfterFinish() throws {
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(Self.bytesFromString("data"))
        _ = try encoder.finish()
        let drained = encoder.drain()
        #expect(drained.storage.count == 0)
    }

    @Test("non-draining stream byte-equals concatenated-drains stream")
    func drainConcatByteEquality() throws {
        let chunk1 = Self.bytesFromString("aaaaaaaaaa")
        let chunk2 = Self.bytesFromString("bbbbbbbbbb")

        var reference = Gzip.Streaming.Encoder()
        reference.update(chunk1)
        reference.update(chunk2)
        let referenceOutput = try reference.finish()

        var draining = Gzip.Streaming.Encoder()
        draining.update(chunk1)
        let d1 = draining.drain()
        draining.update(chunk2)
        let d2 = draining.drain()
        let d3 = try draining.finish()

        var combined = Bytes()
        combined.append(contentsOf: d1.storage)
        combined.append(contentsOf: d2.storage)
        combined.append(contentsOf: d3.storage)

        #expect(Array(combined.storage) == Array(referenceOutput.storage))
    }

    // MARK: - v0.3 edge cases

    // MARK: - Streaming Decoder (v0.5)

    @Test("Decoder: single chunk round-trip via v0.2 encoder")
    func decoderSingleChunkRoundTrip() throws(GzipError) {
        let payload = Self.bytesFromString("hello world hello world")
        let gzipped = Gzip.encode(payload)
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(gzipped)
        let plain = try decoder.finish()
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("Decoder: multi-chunk input round-trip")
    func decoderMultiChunkRoundTrip() throws(GzipError) {
        let payload = Self.bytesFromString("The quick brown fox jumps over the lazy dog.")
        let gzipped = Gzip.encode(payload)
        let third = gzipped.storage.count / 3
        let c1 = ContiguousArray(gzipped.storage[0..<third])
        let c2 = ContiguousArray(gzipped.storage[third..<(2 * third)])
        let c3 = ContiguousArray(gzipped.storage[(2 * third)..<gzipped.storage.count])
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(Bytes(Array(c1)))
        decoder.update(Bytes(Array(c2)))
        decoder.update(Bytes(Array(c3)))
        let plain = try decoder.finish()
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("Decoder: tiny 1-byte chunks round-trip")
    func decoderTinyChunks() throws(GzipError) {
        let payload = Self.bytesFromString("hello")
        let gzipped = Gzip.encode(payload)
        var decoder = Gzip.Streaming.Decoder()
        for byte in gzipped.storage {
            decoder.update(Self.bytesFromArray([byte]))
        }
        let plain = try decoder.finish()
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("Decoder: gzip with FNAME flag round-trips")
    func decoderWithFNAME() throws(GzipError) {
        let payload = Self.bytesFromString("data with filename")
        let gzipped = Gzip.encode(payload, filename: "test.txt")
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(gzipped)
        let plain = try decoder.finish()
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("Decoder: 70 KiB payload round-trip")
    func decoderLargePayload() throws(GzipError) {
        let payload = Self.bytesFromArray([UInt8](repeating: 0x42, count: 70 * 1024))
        let gzipped = Gzip.encode(payload)
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(gzipped)
        let plain = try decoder.finish()
        #expect(plain.storage.count == 70 * 1024)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("Decoder: truncated input throws")
    func decoderTruncatedThrows() {
        let payload = Self.bytesFromString("hello")
        let gzipped = Gzip.encode(payload)
        let truncated = ContiguousArray(gzipped.storage.dropLast(5))
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(Bytes(Array(truncated)))
        do {
            _ = try decoder.finish()
            Issue.record("expected throw")
        } catch GzipError.truncated, GzipError.crc32Mismatch, GzipError.isizeMismatch, GzipError.malformedDeflate {
            // any of these is acceptable for truncated input
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Decoder: bad magic throws badMagic")
    func decoderBadMagicThrows() {
        var bad = Self.bytesFromArray([0x00, 0x00, 0x08, 0x00, 0, 0, 0, 0, 0, 0xFF])
        // append placeholder body + trailer
        for _ in 0..<10 { bad.append(0) }
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(bad)
        do {
            _ = try decoder.finish()
            Issue.record("expected throw")
        } catch GzipError.badMagic {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Decoder: double-finish throws decoderFinished")
    func decoderDoubleFinishThrows() throws(GzipError) {
        let gzipped = Gzip.encode(Self.bytesFromString("data"))
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(gzipped)
        _ = try decoder.finish()
        do {
            _ = try decoder.finish()
            Issue.record("expected throw")
        } catch GzipError.decoderFinished {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Decoder: update after finish is silent no-op (then double-finish throws)")
    func decoderUpdateAfterFinishNoOp() throws(GzipError) {
        let payload = Self.bytesFromString("first")
        let gzipped = Gzip.encode(payload)
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(gzipped)
        let plain1 = try decoder.finish()
        decoder.update(Gzip.encode(Self.bytesFromString("second")))
        do {
            _ = try decoder.finish()
            Issue.record("expected throw")
        } catch GzipError.decoderFinished {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(Array(plain1.storage) == Array(payload.storage))
    }

    @Test("Decoder: empty update is no-op (whole flow still works)")
    func decoderEmptyUpdateNoOp() throws(GzipError) {
        let payload = Self.bytesFromString("hello")
        let gzipped = Gzip.encode(payload)
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(Bytes())  // no-op
        decoder.update(gzipped)
        decoder.update(Bytes())  // no-op
        let plain = try decoder.finish()
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("Decoder: single-byte payload round-trip")
    func decoderSingleBytePayload() throws(GzipError) {
        let payload = Self.bytesFromArray([0x7F])
        let gzipped = Gzip.encode(payload)
        var decoder = Gzip.Streaming.Decoder()
        decoder.update(gzipped)
        let plain = try decoder.finish()
        #expect(Array(plain.storage) == [0x7F])
    }

    // MARK: - Streaming Encoder (existing v0.3-v0.4 edge cases)

    @Test("update after finish is silent no-op (then double-finish throws)")
    func updateAfterFinishNoOp() throws {
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(Self.bytesFromString("first"))
        let compressed = try encoder.finish()
        encoder.update(Self.bytesFromString("second"))
        do {
            _ = try encoder.finish()
            Issue.record("expected throw")
        } catch GzipError.encoderFinished {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == Array("first".utf8))
    }

    @Test("single-byte stream round-trips")
    func singleByteStream() throws {
        let payload = Self.bytesFromArray([0x7F])
        var encoder = Gzip.Streaming.Encoder()
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Gzip.decode(compressed)
        #expect(Array(plain.storage) == [0x7F])
    }
}
