import Foundation

/// These values belong to the observed server dialect, independent of network status.
enum DeviceRegistrationState: Equatable {
    case registered, awaitingApproval, registrationRequired, unknown

    static func parse(response: String?, recorded: String) -> Self {
        switch response ?? recorded {
        case "1": return .registered
        case "0": return .awaitingApproval
        case "-1", "-2": return .registrationRequired
        default: return .unknown
        }
    }
}
