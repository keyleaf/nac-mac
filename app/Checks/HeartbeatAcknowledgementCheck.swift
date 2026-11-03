import Foundation
@main
struct HeartbeatAcknowledgementCheck {
    static func main() throws {
        let bare = try HeartbeatMessage.content(deviceID: "synthetic", requestClientType: "mobile")
        precondition(HeartbeatAcknowledgement.valid(bare))
        precondition(HeartbeatAcknowledgement.isRoleChangedNotification(Data("<ASM><TradeCode>RoleChanged</TradeCode></ASM>".utf8)))
        for xml in ["<ASM><TradeCode>RoleChanged</TradeCode><WhatToDo>ShutdownNetwork</WhatToDo></ASM>",
                    "<ASM><TradeCode>RoleChanged</TradeCode><TradeCode>HeartTest</TradeCode></ASM>",
                    "<ASM><TradeCode>HeartTest</TradeCode></ASM>", "<ASM><TradeCode>RoleChanged</TradeCode>"] {
            precondition(!HeartbeatAcknowledgement.isRoleChangedNotification(Data(xml.utf8)))
        }
        let notice = Data("<ASM><TradeCode>SvrNoticeToAgent</TradeCode><WhatToDo>NoticeNetStateChanged</WhatToDo><StateOfNet>1</StateOfNet><Token>synthetic-secret</Token></ASM>".utf8)
        precondition(HeartbeatAcknowledgement.tradeCode(notice) == "SvrNoticeToAgent")
        precondition(HeartbeatAcknowledgement.safeControlSummary(notice) == "WhatToDo=NoticeNetStateChanged, StateOfNet=1")
        let other = Data("<ASM><WhatToDo>synthetic-secret</WhatToDo></ASM>".utf8)
        precondition(!HeartbeatAcknowledgement.safeControlSummary(other).contains("synthetic-secret"))
        for text in ["<ASM><TradeCode>Other</TradeCode></ASM>",
                     "<ASM><TradeCode>HeartTest</TradeCode><TradeCode>Other</TradeCode></ASM>",
                     "<ASM><!--<TradeCode>HeartTest</TradeCode>--></ASM>",
                     "<!DOCTYPE ASM [<!ENTITY x 'HeartTest'>]><ASM><TradeCode>&x;</TradeCode></ASM>",
                     "<ASM><TradeCode>HeartTest</TradeCode>"] {
            precondition(!HeartbeatAcknowledgement.valid(Data(text.utf8)))
        }
        print("PASS: bare HeartTest acknowledgement; wrong, duplicate, commented, DTD and malformed XML rejection")
    }
}
