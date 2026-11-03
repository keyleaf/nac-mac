import Foundation

@main
struct SPABridgeFieldsCheck {
    static func main() {
        // Distinguishes the observed alphabet from both standard Base64 and Base64URL.
        precondition(SPABridgeFields.authentication(["a", "~~~", "???", "中文", ""]) == "YQ--|fn5_|Pz8.|5Lit5paH|")
        precondition(SPABridgeFields.authentication([]) == "")
        precondition(SPABridgeFields.authentication(["a|b"]) == "YXxi")
        // Device fields deliberately retain standard Base64 padding and an empty fourth field.
        precondition(SPABridgeFields.device(ip: "a", mac: "~~~", hardwareID: "???") == "YQ==|fn5+|Pz8/||MQ==")
        print("SPA bridge field checks passed")
    }
}
