/// Recovered from ARM64 routine 0x10000d0b4 in NAC Client 2.7.
/// Obfuscation only; this provides no transport security.
enum ByteTransform {
    static func encode(_ bytes: [UInt8], key: [UInt8]) -> [UInt8] {
        precondition(!key.isEmpty)
        return bytes.enumerated().map { index, byte in
            let value = byte ^ key[index % key.count]
            return (value << 4) | (value >> 4)
        }
    }

    static func decode(_ bytes: [UInt8], key: [UInt8]) -> [UInt8] {
        precondition(!key.isEmpty)
        return bytes.enumerated().map { index, byte in
            ((byte << 4) | (byte >> 4)) ^ key[index % key.count]
        }
    }
}
