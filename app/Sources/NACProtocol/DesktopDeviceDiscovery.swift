import Foundation

/// Desktop discovery codec. Live acceptance of first-report values is unverified.
enum DesktopDeviceDiscovery {
    static let trade = "UpdateAgentInfo"

    enum Failure: Error, Equatable {
        case mismatchedReply
        case invalidXML
        case invalidAgentID
        case mismatchedRecord
    }

    struct Reply {
        let agentID: String
        let serverID: String?
        let registration: DeviceRegistrationState

        func deviceRecord(from fields: [String: Any]) throws -> DeviceRecord {
            var fields = fields
            let record = DeviceRecord(fields: fields)
            guard record.id.isEmpty || record.id == agentID else { throw Failure.mismatchedRecord }
            let recorded = DeviceRegistrationState.parse(response: nil, recorded: record.registered)
            fields["DeviceID"] = agentID
            fields["Registered"] = (recorded == .unknown ? registration : recorded).rawValue
            return DeviceRecord(fields: fields)
        }

        func registrationQuery(context: AuthenticationRequest.Context) throws -> URLRequest {
            guard context.osType == "mac" else { throw AuthenticationRequest.Failure.invalidContext }
            return try AuthenticationRequest.prepare(route: "device/info",
                parameters: [("deviceId", agentID), ("form", "AgentReg"), ("basIP", ""), ("UrlAscid", "")],
                context: context)
        }
    }

    static func firstReport(_ device: MacDeviceReport, serial: UInt32) throws -> Data {
        // Empty initial IDs and optional fields are provisional. Only the selected route is reported.
        let values: [(String, String)] = [
            ("TradeCode", trade), ("ServerID", ""), ("AgentID", ""), ("SubType", "mac"),
            ("IP", device.ip), ("MAC", device.mac), ("GateWay", ""), ("Mask", device.subnetMask),
            ("IPs", device.ip), ("Macs", device.mac), ("IPs_IPv6", ""),
            ("Hards", ""), ("SMBIOS", ""), ("CPUID", ""), ("RealDiskId", device.hardwareUUID.uuidString),
            ("CPU", device.processor), ("DiskSize", device.formattedDiskSize), ("Memory", ""),
            ("ComputerName", device.name), ("OSName", "MacOS"), ("SPNumber", ""), ("OSLanguage", ""),
            ("OSVersion", device.system.hasPrefix("macOS ") ? String(device.system.dropFirst(6)) : device.system), ("OSInstallTime", ""),
            ("IEVersion", ""), ("SysInstallDate", ""), ("IsInNAT", "0"),
            ("AgentVersion", device.version), ("ZtpDevice", ""),
            ("UserID", ""), ("Token", ""), ("DeviceType", "300")
        ]
        let elements = values.map { name, value in "<\(name)>\(MacDeviceReport.xmlText(value))</\(name)>" }.joined()
        // Character references keep the entire document in the ASCII subset of GBK.
        let xml = "<?xml version=\"1.0\" encoding=\"gbk\"?><ASM>" + elements + "</ASM>"
        return try ASMFrame.encode(trade: trade, content: Data(xml.utf8), field8: 1, serial: serial)
    }

    static func reply(from message: ASMFrame.Message, serial: UInt32) throws -> Reply {
        guard message.trade == trade, message.header.field52 == serial else { throw Failure.mismatchedReply }
        let content = message.content
        guard !content.isEmpty, content.count <= 65_536, !content.contains(0) else { throw Failure.invalidXML }
        let ascii = String(decoding: content, as: UTF8.self).uppercased()
        guard !ascii.contains("<!DOCTYPE"), !ascii.contains("<!ENTITY") else { throw Failure.invalidXML }

        let reader = ReplyReader()
        let parser = XMLParser(data: content)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.valid else { throw Failure.invalidXML }
        guard reader.fields["TradeCode"] == trade else { throw Failure.mismatchedReply }
        guard let agentID = reader.fields["AgentID"], !agentID.isEmpty, agentID.utf8.count <= 10,
              agentID.utf8.allSatisfy({ (48...57).contains($0) }),
              let numericID = Int32(agentID), numericID > 0 else { throw Failure.invalidAgentID }
        return Reply(agentID: String(numericID), serverID: reader.fields["ServerID"],
            registration: .parse(response: reader.fields["Registered"], recorded: ""))
    }

    private final class ReplyReader: NSObject, XMLParserDelegate {
        private static let knownFields = Set(["TradeCode", "AgentID", "ServerID", "Registered"])
        private var depth = 0
        private var nodes = 0
        private var currentField: String?
        private var value = ""
        private(set) var fields: [String: String] = [:]
        private(set) var valid = true

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            depth += 1
            nodes += 1
            guard depth <= 16, nodes <= 128, depth != 1 || name == "ASM", currentField == nil else {
                reject(parser)
                return
            }
            guard depth == 2, Self.knownFields.contains(name) else { return }
            guard fields[name] == nil, attributes.isEmpty else { reject(parser); return }
            currentField = name
            value = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentField != nil else { return }
            value += string
            if value.utf8.count > 128 { reject(parser) }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if currentField != nil { reject(parser) }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if currentField == name {
                fields[name] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                currentField = nil
            }
            depth -= 1
        }

        private func reject(_ parser: XMLParser) {
            valid = false
            parser.abortParsing()
        }
    }
}
