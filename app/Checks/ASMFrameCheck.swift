import Foundation

@main
struct ASMFrameCheck {
    static func main() throws {
        // Independently generated with Python zlib + struct.pack, not the Swift encoder.
        let hex = "b800000041534d3501000000010000000100000012b070d131b3c0d121f676f696e666f676f696e666f676f696e666f676f696e62a00000098000000114b302a6516bae527c67b4cd37566eea989e3b3f7f070d4e760d744b1eff4b4f67e9b1f546e7ea9eb9f0c51941de1e4c07e7ca30e2b73b5e6c13dd7535cabb10327a311bdf5efb533267bde8277a3f5eaae39060c91e6a8b1b85dbe41c26f6fd99fe4e8693c49fad2a64d2c98b482d86259657c5d5109e66f3935cd"
        var fixture = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            fixture.append(UInt8(hex[index..<end], radix: 16)!)
            index = end
        }
        let expected = try HeartbeatMessage.content(deviceID: "synthetic", requestClientType: "mobile")
        let known = try ASMFrame.decode(fixture)
        precondition(known.content == expected && known.trade == "HeartTest" && known.header.field52 == 42)
        let encoded = try HeartbeatMessage.frame(deviceID: "synthetic", requestClientType: "mobile", serial: 42)
        let decoded = try ASMFrame.decode(encoded)
        precondition(decoded.content == expected && decoded.header.field8 == 1)
        var stream = ASMFrame.Stream()
        var messages: [ASMFrame.Message] = []
        for byte in fixture { messages += try stream.feed(Data([byte])) }
        precondition(messages.count == 1 && messages[0].content == expected)
        var batched = ASMFrame.Stream()
        let batch = try batched.feed(fixture + fixture)
        precondition(batch.count == 2)
        var corrupt = fixture; corrupt[corrupt.count - 1] ^= 255
        do { _ = try ASMFrame.decode(corrupt); preconditionFailure("corrupt zlib accepted") } catch {}
        var badLength = fixture; badLength[56] = 0
        do { _ = try ASMFrame.decode(badLength); preconditionFailure("incorrect original length accepted") } catch {}
        var badFlags = fixture; badFlags[16] = 2
        do { _ = try ASMFrame.decode(badFlags); preconditionFailure("unknown flags accepted") } catch ASMFrame.Failure.unsupportedFlags {}
        do { _ = try HeartbeatMessage.content(deviceID: "x</AgentID>", requestClientType: "mobile"); preconditionFailure("XML injection accepted") } catch HeartbeatMessage.Failure.invalidIdentifier {}
        print("PASS: independent Python frame fixture, heartbeat XML, bytewise TCP fragments, combined frames, corrupt payload and flag rejection")
    }
}
