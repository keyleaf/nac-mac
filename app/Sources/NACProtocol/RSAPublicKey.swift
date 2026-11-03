import Foundation
import Security

enum RSAPublicKey {
    enum Failure: Error { case invalidPEM, invalidDER, unsupportedAlgorithm, importFailed }
    private struct DER {
        var data: Data
        var cursor = 0
        mutating func read(_ tag: UInt8) throws -> Data {
            guard cursor + 2 <= data.count, data[cursor] == tag else { throw Failure.invalidDER }
            cursor += 1
            var length = Int(data[cursor]); cursor += 1
            if length >= 128 {
                let count = length & 127
                guard (1...3).contains(count), cursor + count <= data.count,
                      data[cursor] != 0 else { throw Failure.invalidDER }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(data[cursor]); cursor += 1 }
                guard length >= 128 else { throw Failure.invalidDER }
            }
            guard length <= data.count - cursor else { throw Failure.invalidDER }
            let value = data.subdata(in: cursor..<(cursor + length))
            cursor += length
            return value
        }
        var finished: Bool { cursor == data.count }
    }
    static func parsePEM(_ pem: String) throws -> SecKey {
        guard pem.utf8.count <= 16_384 else { throw Failure.invalidPEM }
        let lines = pem.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first, let last = lines.last,
              (first == "-----BEGIN PUBLIC KEY-----" && last == "-----END PUBLIC KEY-----") ||
              (first == "-----BEGIN RSA PUBLIC KEY-----" && last == "-----END RSA PUBLIC KEY-----"),
              let bytes = Data(base64Encoded: lines.dropFirst().dropLast().joined()) else { throw Failure.invalidPEM }
        var pkcs1 = bytes
        if first == "-----BEGIN PUBLIC KEY-----" {
            var outer = DER(data: bytes)
            var body = DER(data: try outer.read(0x30))
            guard outer.finished else { throw Failure.invalidDER }
            var algorithm = DER(data: try body.read(0x30))
            let oid = try algorithm.read(6)
            guard oid == Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1,1]) else { throw Failure.unsupportedAlgorithm }
            if !algorithm.finished {
                guard try algorithm.read(5).isEmpty else { throw Failure.invalidDER }
            }
            guard algorithm.finished else { throw Failure.invalidDER }
            let bitString = try body.read(3)
            guard body.finished, bitString.first == 0 else { throw Failure.invalidDER }
            pkcs1 = Data(bitString.dropFirst())
        }
        var outer = DER(data: pkcs1)
        var sequence = DER(data: try outer.read(0x30))
        let modulus = try sequence.read(2)
        let exponent = try sequence.read(2)
        guard outer.finished, sequence.finished, !modulus.isEmpty, !exponent.isEmpty,
              modulus.first! < 128, exponent.first! < 128 else { throw Failure.invalidDER }
        var error: Unmanaged<CFError>?
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                   kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            if let error { throw error.takeRetainedValue() }
            throw Failure.importFailed
        }
        return key
    }
}
