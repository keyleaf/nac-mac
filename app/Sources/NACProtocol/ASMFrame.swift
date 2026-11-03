import Foundation
import zlib

/// Static ASM5 framing. Network ownership and transaction response semantics are separate.
enum ASMFrame {
    static let maximumLength = 4 * 1024 * 1024
    private static let key = Array("infogo".utf8)
    enum Failure: Error { case invalidTrade, invalidLength, unsupportedFlags, compression, decompression, trailingCompressedData }
    struct Message {
        let header: FrameHeader
        let trade: String
        let content: Data
    }

    static func encode(trade: String, content: Data, field8: UInt32, serial: UInt32) throws -> Data {
        let name = Array(trade.utf8)
        guard !name.isEmpty, name.count <= 32, name.allSatisfy({ (32...126).contains($0) }) else { throw Failure.invalidTrade }
        guard !content.isEmpty, content.count <= maximumLength - 60 else { throw Failure.invalidLength }
        var length = compressBound(uLong(content.count))
        var compressed = [UInt8](repeating: 0, count: Int(length))
        let result = content.withUnsafeBytes { input in
            compress2(&compressed, &length, input.bindMemory(to: UInt8.self).baseAddress!, uLong(content.count), 9)
        }
        guard result == Z_OK else { throw Failure.compression }
        compressed.removeSubrange(Int(length)..<compressed.count)
        guard compressed.count + 60 <= maximumLength else { throw Failure.invalidLength }
        var bytes = [UInt8](repeating: 0, count: 60)
        func put(_ offset: Int, _ value: UInt32) {
            for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
        }
        put(0, UInt32(60 + compressed.count)); put(4, 0x354d5341)
        put(8, field8); put(12, 1); put(16, 1); put(52, serial); put(56, UInt32(content.count))
        bytes.replaceSubrange(20..<52, with: ByteTransform.encode(name + Array(repeating: 0, count: 32 - name.count), key: key))
        bytes.append(contentsOf: ByteTransform.encode(compressed, key: key))
        return Data(bytes)
    }

    static func decode(_ data: Data) throws -> Message {
        let bytes = Array(data)
        let header = try FrameHeader.parse(bytes, maximumLength: UInt32(maximumLength))
        guard bytes.count == Int(header.totalLength), bytes.count > 60 else { throw Failure.invalidLength }
        guard header.field12 <= 1, header.field16 <= 1 else { throw Failure.unsupportedFlags }
        let name = ByteTransform.decode(header.encodedTradeName, key: key).prefix { $0 != 0 }
        guard !name.isEmpty, name.allSatisfy({ (32...126).contains($0) }) else { throw Failure.invalidTrade }
        let wirePayload = Array(bytes.dropFirst(60))
        let compressed = header.field16 == 1 ? ByteTransform.decode(wirePayload, key: key) : wirePayload
        if header.field12 == 0 {
            return Message(header: header, trade: String(decoding: name, as: UTF8.self), content: Data(compressed))
        }
        guard header.originalLength > 0 else { throw Failure.invalidLength }
        var output = [UInt8](repeating: 0, count: Int(header.originalLength))
        var outputLength = uLongf(output.count)
        var sourceLength = uLong(compressed.count)
        let result = compressed.withUnsafeBufferPointer { source in
            uncompress2(&output, &outputLength, source.baseAddress!, &sourceLength)
        }
        guard result == Z_OK, outputLength == header.originalLength else { throw Failure.decompression }
        guard sourceLength == compressed.count else { throw Failure.trailingCompressedData }
        return Message(header: header, trade: String(decoding: name, as: UTF8.self), content: Data(output))
    }

    struct Stream {
        private var buffer = Data()
        mutating func feed(_ bytes: Data) throws -> [Message] {
            guard bytes.count <= ASMFrame.maximumLength,
                  buffer.count + bytes.count <= ASMFrame.maximumLength * 2 else { throw Failure.invalidLength }
            buffer.append(bytes)
            var messages: [Message] = []
            while buffer.count >= FrameHeader.size {
                let header = try FrameHeader.parse(Array(buffer.prefix(60)), maximumLength: UInt32(ASMFrame.maximumLength))
                guard buffer.count >= header.totalLength else { break }
                let count = Int(header.totalLength)
                messages.append(try ASMFrame.decode(Data(buffer.prefix(count))))
                buffer = Data(buffer.dropFirst(count))
            }
            return messages
        }
    }
}
