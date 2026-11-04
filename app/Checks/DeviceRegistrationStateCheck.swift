import Foundation

@main
struct DeviceRegistrationStateCheck {
    static func main() {
        precondition(DeviceRegistrationState.parse(response: nil, recorded: "1") == .registered)
        precondition(DeviceRegistrationState.parse(response: "0", recorded: "1") == .awaitingApproval)
        for state in ["-1", "-2"] {
            precondition(DeviceRegistrationState.parse(response: state, recorded: "1") == .registrationRequired)
        }
        precondition(DeviceRegistrationState.parse(response: "1", recorded: "0") == .registered)
        for state in ["", "2", "unexpected"] {
            precondition(DeviceRegistrationState.parse(response: state, recorded: "1") == .unknown)
        }
        precondition(DeviceRegistrationState.parse(response: nil, recorded: "") == .unknown)
        print("PASS: login registration state overrides cached record, pending approval/new registration/unknown blocked")
    }
}
