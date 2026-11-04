import Foundation
@main struct Check {
 @MainActor static func main() throws {
  let store = KeychainPasswordStore()
  let server = "https://synthetic-" + UUID().uuidString + ".invalid"
  let account = "synthetic"
  defer { try? store.remove(server: server, account: account) }
  let absent = try store.read(server: server, account: account); precondition(absent == nil)
  try store.save("synthetic-first", server: server, account: account)
  let first = try store.read(server: server, account: account); precondition(first == "synthetic-first")
  let otherServer = try store.read(server: server + "-other", account: account); precondition(otherServer == nil)
  let otherAccount = try store.read(server: server, account: "other"); precondition(otherAccount == nil)
  try store.save("synthetic-second", server: server, account: account)
  let second = try store.read(server: server, account: account); precondition(second == "synthetic-second")
  try store.remove(server: server, account: account)
  let removed = try store.read(server: server, account: account); precondition(removed == nil)
  print("PASS: isolated Keychain save/read/update/delete and server/account isolation")
 }
}
