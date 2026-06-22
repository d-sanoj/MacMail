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
        attachments: [URL],
        inlineImages: [(cid: String, data: Data, mimeType: String)] = [],
        inReplyTo: String? = nil,
        references: String? = nil
    ) throws -> String {
        let mixedBoundary = "MixedBoundary-\(UUID().uuidString)"
        let relatedBoundary = "RelatedBoundary-\(UUID().uuidString)"
        let altBoundary = "AltBoundary-\(UUID().uuidString)"

        var lines = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(encodedHeader(subject))",
            "MIME-Version: 1.0"
        ]

        if let inReplyTo = inReplyTo {
            lines.append("In-Reply-To: \(inReplyTo)")
        }
        if let references = references {
            lines.append("References: \(references)")
        }

        if !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Cc: \(cc)")
        }
        if !bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Bcc: \(bcc)")
        }

        let hasAttachments = !attachments.isEmpty
        let hasInline = !inlineImages.isEmpty

        if hasAttachments {
            lines.append("Content-Type: multipart/mixed; boundary=\"\(mixedBoundary)\"")
            lines.append("")
            lines.append("--\(mixedBoundary)")
        }

        if hasInline {
            lines.append("Content-Type: multipart/related; boundary=\"\(relatedBoundary)\"")
            lines.append("")
            lines.append("--\(relatedBoundary)")
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

        if hasInline {
            for img in inlineImages {
                lines.append("--\(relatedBoundary)")
                lines.append("Content-Type: \(img.mimeType); name=\"inline-image.png\"")
                lines.append("Content-ID: <\(img.cid)>")
                lines.append("Content-Disposition: inline; filename=\"inline-image.png\"")
                lines.append("Content-Transfer-Encoding: base64")
                lines.append("")
                lines.append(img.data.base64EncodedString(options: .lineLength64Characters))
            }
            lines.append("--\(relatedBoundary)--")
        }

        if hasAttachments {
            for url in attachments {
                guard let data = try? Data(contentsOf: url) else { continue }
                let filename = url.lastPathComponent
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                
                lines.append("--\(mixedBoundary)")
                lines.append("Content-Type: \(mimeType); name=\"\(filename)\"")
                lines.append("Content-Disposition: attachment; filename=\"\(filename)\"")
                lines.append("Content-Transfer-Encoding: base64")
                lines.append("")
                
                let base64 = data.base64EncodedString(options: .lineLength64Characters)
                lines.append(base64)
            }
            lines.append("--\(mixedBoundary)--")
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
    }
}
