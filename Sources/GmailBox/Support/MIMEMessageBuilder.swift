import Foundation
import UniformTypeIdentifiers

enum MIMEMessageBuilder {
    static func build(
        from: String,
        to: String,
        cc: String,
        bcc: String,
        subject: String,
        plainText: String,
        htmlBody: String?,
        attachments: [URL]
    ) throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let altBoundary = "AltBoundary-\(UUID().uuidString)"

        var lines = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(encodedHeader(subject))",
            "MIME-Version: 1.0"
        ]

        if !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Cc: \(cc)")
        }
        if !bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Bcc: \(bcc)")
        }

        let isMultipart = !attachments.isEmpty
        if isMultipart {
            lines.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
            lines.append("")
            lines.append("--\(boundary)")
        }

        let hasHTML = htmlBody != nil && !htmlBody!.isEmpty
        if hasHTML {
            lines.append("Content-Type: multipart/alternative; boundary=\"\(altBoundary)\"")
            lines.append("")
            
            // Plain text part
            lines.append("--\(altBoundary)")
            lines.append("Content-Type: text/plain; charset=utf-8")
            lines.append("Content-Transfer-Encoding: 8bit")
            lines.append("")
            lines.append(plainText)
            
            // HTML part
            lines.append("--\(altBoundary)")
            lines.append("Content-Type: text/html; charset=utf-8")
            lines.append("Content-Transfer-Encoding: 8bit")
            lines.append("")
            lines.append(htmlBody!)
            
            lines.append("--\(altBoundary)--")
        } else {
            lines.append("Content-Type: text/plain; charset=utf-8")
            lines.append("Content-Transfer-Encoding: 8bit")
            lines.append("")
            lines.append(plainText)
        }

        if isMultipart {
            for url in attachments {
                guard let data = try? Data(contentsOf: url) else { continue }
                let filename = url.lastPathComponent
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                
                lines.append("--\(boundary)")
                lines.append("Content-Type: \(mimeType); name=\"\(filename)\"")
                lines.append("Content-Disposition: attachment; filename=\"\(filename)\"")
                lines.append("Content-Transfer-Encoding: base64")
                lines.append("")
                
                let base64 = data.base64EncodedString(options: .lineLength64Characters)
                lines.append(base64)
            }
            lines.append("--\(boundary)--")
        }

        let message = lines.joined(separator: "\r\n")
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
