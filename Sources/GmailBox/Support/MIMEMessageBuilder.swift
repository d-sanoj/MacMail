import Foundation

enum MIMEMessageBuilder {
    static func plainText(from: String, to: String, cc: String, bcc: String, subject: String, body: String) -> String {
        var lines = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(encodedHeader(subject))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: 8bit"
        ]

        if !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.insert("Cc: \(cc)", at: 2)
        }
        if !bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.insert("Bcc: \(bcc)", at: cc.isEmpty ? 2 : 3)
        }

        let message = (lines + ["", body]).joined(separator: "\r\n")
        return Data(message.utf8).base64URLEncodedString()
    }

    private static func encodedHeader(_ value: String) -> String {
        guard value.canBeConverted(to: .ascii) else {
            return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
        }
        return value
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
