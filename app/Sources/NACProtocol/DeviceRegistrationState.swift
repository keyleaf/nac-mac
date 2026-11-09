import Foundation

/// These values belong to the observed server dialect, independent of network status.
enum DeviceRegistrationState: String {
    case registered = "1"
    case awaitingApproval = "0"
    case registrationRequired = "-2"
    case reregistrationRequired = "-1"
    case unknown = ""

    static func parse(response: String?, recorded: String) -> Self {
        Self(rawValue: response ?? recorded) ?? .unknown
    }
}
