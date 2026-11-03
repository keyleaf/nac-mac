import Foundation
@main
struct RequestSignatureCheck {
    static func main() throws {
        let url = "http://example.test/access/1.0/ios/json/auth/index?cache=1"
        let params = [("user_name", "YSti"), ("password", "a%2Bb%2F%3D"), ("label", "中文 x-:")]
        let result = try RequestSignature.canonical(url, parameters: params)
        precondition(result == "/access/1.0/ios/json/auth/index?cache=1&user_name=YSti&password=ab/=&label=x")
        let md5 = try RequestSignature.checksum("abc", parameters: [])
        precondition(md5 == "900150983cd24fb0d6963f7d28e17f72")
        let reversed = try RequestSignature.checksum(url, parameters: params.reversed())
        let ordered = try RequestSignature.checksum(url, parameters: params)
        precondition(reversed != ordered)
        do {
            _ = try RequestSignature.canonical(url, parameters: [("x", "%ZZ")])
            preconditionFailure("invalid percent escape accepted")
        } catch RequestSignature.Failure.malformedPercentEncoding {}
        print("PASS: canonicalization, MD5 vector, parameter order, invalid escaping")
    }
}
