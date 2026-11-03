@main
struct ByteTransformCheck {
    static func main() {
        let key = Array("infogo".utf8)
        // Independently calculated vectors: xor with i/n/f then swap nibbles.
        precondition(ByteTransform.encode([0, 0, 0], key: key) == [0x96, 0xe6, 0x66])
        precondition(ByteTransform.encode([0x69, 0x6e, 0x66], key: key) == [0, 0, 0])
        let allBytes = (0...255).map(UInt8.init)
        for offset in 0..<key.count {
            let input = Array(repeating: UInt8(0xa5), count: offset) + allBytes
            precondition(ByteTransform.decode(ByteTransform.encode(input, key: key), key: key) == input)
        }
        precondition(ByteTransform.encode([], key: key).isEmpty)
        print("PASS: fixed vectors, all byte values at each key alignment, empty input")
    }
}
