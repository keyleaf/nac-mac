import Foundation
import Security

@MainActor protocol PasswordStore {
    func read(server: String, account: String) throws -> String?
    func save(_ password: String, server: String, account: String) throws
    func remove(server: String, account: String) throws
}
@MainActor final class KeychainPasswordStore: PasswordStore {
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "钥匙串操作失败（\(status)），请手动输入密码或重试。" }
    }
    private func query(_ server: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.github.keyleaf.nac-mac.password:" + server,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    func read(server: String, account: String) throws -> String? {
        var q = query(server, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = value as? Data, let password = String(data: data, encoding: .utf8) else { throw Failure(status: errSecDecode) }
        return password
    }
    func save(_ password: String, server: String, account: String) throws {
        let q = query(server, account)
        let data = Data(password.utf8)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
    func remove(server: String, account: String) throws {
        let status = SecItemDelete(query(server, account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
