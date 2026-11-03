@main
struct FrameHeaderCheck {
    static func main() throws {
        var bytes = [UInt8](repeating: 0, count: 60)
        func set(_ value: UInt32, at offset: Int) {
            for i in 0..<4 { bytes[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        set(64, at: 0); set(0x354d5341, at: 4)
        set(0x12345678, at: 52); set(128, at: 56)
        let header = try FrameHeader.parse(bytes)
        precondition(header.totalLength == 64 && header.field52 == 0x12345678 && header.originalLength == 128)
        for length in 0..<60 {
            do { _ = try FrameHeader.parse(Array(bytes.prefix(length))); preconditionFailure() }
            catch FrameHeader.Failure.truncated {}
        }
        set(59, at: 0)
        do { _ = try FrameHeader.parse(bytes); preconditionFailure() } catch FrameHeader.Failure.invalidLength {}
        set(5_000_000, at: 0)
        do { _ = try FrameHeader.parse(bytes); preconditionFailure() } catch FrameHeader.Failure.oversized {}
        set(64, at: 0); set(0, at: 4)
        do { _ = try FrameHeader.parse(bytes); preconditionFailure() } catch FrameHeader.Failure.invalidMagic {}
        print("PASS: little-endian fields, all truncated headers, bad magic and length limits")
    }
}
