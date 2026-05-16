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
