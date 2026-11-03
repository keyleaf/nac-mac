import Foundation

/// Outbound ASM5 layout observed in NAC Client 2.7.
/// Receive-direction compatibility and field meanings remain unverified.
struct FrameHeader: Equatable {
    static let size = 60
    enum Failure: Error { case truncated, invalidMagic, invalidLength, oversized }
    let totalLength: UInt32
    let field8: UInt32
    let field12: UInt32
    let field16: UInt32
    let encodedTradeName: [UInt8]
    let field52: UInt32
    let originalLength: UInt32

    static func parse(_ bytes: [UInt8], maximumLength: UInt32 = 4 * 1024 * 1024) throws -> Self {
        guard bytes.count >= size else { throw Failure.truncated }
        func word(_ offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
        }
        guard word(4) == 0x354d5341 else { throw Failure.invalidMagic }
        let total = word(0)
        guard total >= UInt32(size) else { throw Failure.invalidLength }
        guard total <= maximumLength, word(56) <= maximumLength else { throw Failure.oversized }
        return Self(totalLength: total, field8: word(8), field12: word(12),
                    field16: word(16), encodedTradeName: Array(bytes[20..<52]),
                    field52: word(52), originalLength: word(56))
    }
}
