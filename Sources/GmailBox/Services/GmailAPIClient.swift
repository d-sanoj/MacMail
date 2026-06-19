import Foundation

final class GmailAPIClient {
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func labels(accessToken: String) async throws -> [GmailLabel] {
        let data = try await send(path: "labels", accessToken: accessToken)
        struct Response: Decodable {
            let labels: [Label]
        }
        struct Label: Decodable {
            let id: String
            let name: String
            let type: String?
            let messagesTotal: Int?
            let messagesUnread: Int?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.labels.map {
            GmailLabel(
                id: $0.id,
                accountId: "",
                name: $0.name,
                type: labelType(id: $0.id, apiType: $0.type),
                colorHex: nil,
                unreadCount: $0.messagesUnread ?? 0,
                totalCount: $0.messagesTotal ?? 0
            )
        }
    }

    func threads(accessToken: String, query: String?, labelId: String?, maxResults: Int = 50, includeSpamTrash: Bool = false) async throws -> [GmailThread] {
        let page = try await threadPage(accessToken: accessToken, query: query, labelId: labelId, maxResults: maxResults, pageToken: nil, includeSpamTrash: includeSpamTrash)
        return try await hydrateThreadSummaries(page.threads, accessToken: accessToken)
    }

    func allThreads(accessToken: String, query: String? = nil, labelId: String? = nil, pageSize: Int = 100, includeSpamTrash: Bool = false) async throws -> [GmailThread] {
        var allThreads: [GmailThread] = []
        var pageToken: String?

        repeat {
            let page = try await threadPage(accessToken: accessToken, query: query, labelId: labelId, maxResults: pageSize, pageToken: pageToken, includeSpamTrash: includeSpamTrash)
            allThreads.append(contentsOf: try await hydrateThreadSummaries(page.threads, accessToken: accessToken))
            pageToken = page.nextPageToken
        } while pageToken != nil

        return allThreads
    }

    private func hydrateThreadSummaries(_ threads: [GmailThread], accessToken: String) async throws -> [GmailThread] {
        var hydrated: [GmailThread] = []
        var index = threads.startIndex

        while index < threads.endIndex {
            let end = threads.index(index, offsetBy: 10, limitedBy: threads.endIndex) ?? threads.endIndex
            let batch = Array(threads[index..<end])
            let hydratedBatch = try await withThrowingTaskGroup(of: GmailThread.self) { group in
                for thread in batch {
                    group.addTask {
                        try await self.threadSummary(for: thread.id, fallback: thread, accessToken: accessToken)
                    }
                }

                var values: [GmailThread] = []
                for try await value in group {
                    values.append(value)
                }
                return values
            }
            hydrated.append(contentsOf: hydratedBatch)
            index = end
        }

        return hydrated.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    private func threadSummary(for threadId: String, fallback: GmailThread, accessToken: String) async throws -> GmailThread {
        var queryItems = [URLQueryItem(name: "format", value: "metadata")]
        ["From", "Subject", "Date"].forEach {
            queryItems.append(URLQueryItem(name: "metadataHeaders", value: $0))
        }

        let data = try await send(path: "threads/\(threadId)", queryItems: queryItems, accessToken: accessToken)
        let decoded = try JSONDecoder().decode(GmailThreadResponse.self, from: data)
        guard let latest = decoded.messages.max(by: { ($0.internalDateMillis ?? 0) < ($1.internalDateMillis ?? 0) }) else {
            return fallback
        }

        let labelIds = Array(Set(decoded.messages.flatMap { $0.labelIds ?? [] }))
        let subject = latest.header("Subject") ?? decoded.messages.compactMap { $0.header("Subject") }.first ?? "(No subject)"
        let from = latest.header("From") ?? decoded.messages.compactMap { $0.header("From") }.last ?? "Unknown sender"
        let hasAttachments = decoded.messages.contains { $0.payload?.hasAttachments ?? false }

        return GmailThread(
            id: decoded.id,
            accountId: fallback.accountId,
            snippet: latest.snippet ?? decoded.snippet ?? fallback.snippet,
            subject: subject.isEmpty ? "(No subject)" : subject,
            senderDisplay: displayName(fromHeader: from),
            lastMessageDate: latest.internalDateMillis.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? fallback.lastMessageDate,
            labelIds: labelIds,
            isUnread: labelIds.contains(GmailSystemLabel.unread),
            isStarred: labelIds.contains(GmailSystemLabel.starred),
            hasAttachments: hasAttachments
        )
    }

    private func threadPage(accessToken: String, query: String?, labelId: String?, maxResults: Int, pageToken: String?, includeSpamTrash: Bool) async throws -> ThreadPage {
        var queryItems = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let labelId, !labelId.isEmpty {
            queryItems.append(URLQueryItem(name: "labelIds", value: labelId))
        }
        if includeSpamTrash {
            queryItems.append(URLQueryItem(name: "includeSpamTrash", value: "true"))
        }
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        let data = try await send(path: "threads", queryItems: queryItems, accessToken: accessToken)
        struct Response: Decodable {
            struct Thread: Decodable {
                let id: String
                let snippet: String?
                let historyId: String?
            }
            let threads: [Thread]?
            let nextPageToken: String?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return ThreadPage(threads: (decoded.threads ?? []).map {
            GmailThread(
                id: $0.id,
                accountId: "",
                snippet: $0.snippet ?? "",
                subject: "(No subject)",
                senderDisplay: "Unknown sender",
                lastMessageDate: Date(),
                labelIds: labelId.map { [$0] } ?? [],
                isUnread: false,
                isStarred: false,
                hasAttachments: false
            )
        }, nextPageToken: decoded.nextPageToken)
    }

    func messages(for threadId: String, accessToken: String) async throws -> [GmailMessage] {
        let data = try await send(path: "threads/\(threadId)", queryItems: [URLQueryItem(name: "format", value: "full")], accessToken: accessToken)
        let decoded = try JSONDecoder().decode(GmailThreadResponse.self, from: data)
        var messages: [GmailMessage] = []

        for message in decoded.messages {
            let resolvedHTML = try await resolvedHTMLBody(for: message, accessToken: accessToken)
            messages.append(GmailMessage(
                id: message.id,
                threadId: decoded.id,
                accountId: "",
                from: message.header("From") ?? "",
                to: message.header("To").map { [$0] } ?? [],
                cc: message.header("Cc").map { [$0] } ?? [],
                bcc: message.header("Bcc").map { [$0] } ?? [],
                subject: message.header("Subject") ?? "(No subject)",
                date: message.internalDate.flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(),
                snippet: message.snippet ?? "",
                plainTextBody: message.payload?.plainTextBody,
                htmlBody: resolvedHTML,
                labelIds: message.labelIds ?? [],
                isUnread: message.labelIds?.contains(GmailSystemLabel.unread) ?? false,
                isStarred: message.labelIds?.contains(GmailSystemLabel.starred) ?? false,
                attachments: message.payload?.attachments(messageId: message.id) ?? []
            ))
        }

        return messages
    }

    func modifyThread(accessToken: String, threadId: String, addLabelIds: [String], removeLabelIds: [String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "addLabelIds": addLabelIds,
            "removeLabelIds": removeLabelIds
        ])
        _ = try await send(path: "threads/\(threadId)/modify", method: "POST", body: body, accessToken: accessToken)
    }

    func trashThread(accessToken: String, threadId: String) async throws {
        _ = try await send(path: "threads/\(threadId)/trash", method: "POST", accessToken: accessToken)
    }

    func sendMessage(accessToken: String, rawRFC822Base64URL: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["raw": rawRFC822Base64URL])
        _ = try await send(path: "messages/send", method: "POST", body: body, accessToken: accessToken)
    }

    func attachmentData(accessToken: String, messageId: String, attachmentId: String) async throws -> Data {
        let data = try await send(path: "messages/\(messageId)/attachments/\(attachmentId)", accessToken: accessToken)
        struct Response: Decodable {
            let data: String?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let encoded = decoded.data, let attachmentData = Data(base64URLEncoded: encoded) else {
            throw MailActionError.apiFailure("Unable to decode Gmail attachment data.")
        }
        return attachmentData
    }

    private func resolvedHTMLBody(for message: GmailAPIMessage, accessToken: String) async throws -> String? {
        guard var html = message.payload?.htmlBody else {
            return nil
        }

        for inlineImage in message.payload?.inlineImages ?? [] {
            let imageData: Data?
            if let embeddedData = inlineImage.embeddedData {
                imageData = embeddedData
            } else if let attachmentId = inlineImage.attachmentId {
                imageData = try await attachmentData(accessToken: accessToken, messageId: message.id, attachmentId: attachmentId)
            } else {
                imageData = nil
            }

            guard let imageData else { continue }
            let dataURL = "data:\(inlineImage.mimeType);base64,\(imageData.base64EncodedString())"
            for cid in inlineImage.cidVariants {
                html = html.replacingOccurrences(of: "cid:\(cid)", with: dataURL)
            }
        }

        return html
    }

    private func send(path: String, queryItems: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, accessToken: String) async throws -> Data {
        var url = baseURL.appending(path: path)
        if !queryItems.isEmpty {
            url.append(queryItems: queryItems)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP request failed."
            throw MailActionError.apiFailure(message)
        }
        return data
    }

    private func labelType(id: String, apiType: String?) -> GmailLabel.LabelType {
        if id.hasPrefix("CATEGORY_") {
            return .category
        }
        if apiType == "user" {
            return .user
        }
        return .system
    }
}

private struct ThreadPage {
    let threads: [GmailThread]
    let nextPageToken: String?
}

private struct GmailThreadResponse: Decodable {
    let id: String
    let snippet: String?
    let messages: [GmailAPIMessage]
}

private struct GmailAPIMessage: Decodable {
    struct Header: Decodable {
        let name: String
        let value: String
    }

    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let internalDate: String?
    let payload: GmailMessagePart?

    var internalDateMillis: Int64? {
        internalDate.flatMap(Int64.init)
    }

    func header(_ name: String) -> String? {
        payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct GmailMessagePart: Decodable {
    let partId: String?
    let mimeType: String?
    let filename: String?
    let body: Body?
    let headers: [GmailAPIMessage.Header]?
    let parts: [GmailMessagePart]?

    struct Body: Decodable {
        let attachmentId: String?
        let size: Int?
        let data: String?
    }

    var plainTextBody: String? {
        bodyText(mimeType: "text/plain")
    }

    var htmlBody: String? {
        bodyText(mimeType: "text/html")
    }

    var inlineImages: [InlineImageReference] {
        flattenedParts.compactMap { part in
            guard let mimeType = part.mimeType,
                  mimeType.hasPrefix("image/"),
                  let contentID = part.header("Content-ID") ?? part.header("Content-Id") else {
                return nil
            }

            let cid = contentID
                .trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
            guard !cid.isEmpty else { return nil }

            return InlineImageReference(
                cid: cid,
                mimeType: mimeType,
                attachmentId: part.body?.attachmentId,
                embeddedData: part.body?.data.flatMap { Data(base64URLEncoded: $0) }
            )
        }
    }

    var hasAttachments: Bool {
        flattenedParts.contains { part in
            part.isUserFacingAttachment
        }
    }

    func attachments(messageId: String) -> [GmailAttachment] {
        flattenedParts.compactMap { part in
            guard part.isUserFacingAttachment,
                  let filename = part.filename,
                  let attachmentId = part.body?.attachmentId else {
                return nil
            }
            return GmailAttachment(
                id: "\(messageId)-\(attachmentId)",
                messageId: messageId,
                filename: filename,
                mimeType: part.mimeType ?? "application/octet-stream",
                size: part.body?.size ?? 0,
                attachmentId: attachmentId,
                isDownloaded: false,
                localFileURL: nil
            )
        }
    }

    private var flattenedParts: [GmailMessagePart] {
        [self] + (parts ?? []).flatMap(\.flattenedParts)
    }

    private var isUserFacingAttachment: Bool {
        guard let filename, !filename.isEmpty, body?.attachmentId != nil else {
            return false
        }

        let lowercasedFilename = filename.lowercased()
        let contentDisposition = header("Content-Disposition")?.lowercased() ?? ""
        let contentID = header("Content-ID") ?? header("Content-Id")

        if contentID != nil || contentDisposition.contains("inline") {
            return false
        }

        if (mimeType?.hasPrefix("image/") ?? false) {
            let size = body?.size ?? 0
            let likelyLogoName = ["logo", "icon", "spacer", "pixel", "tracking", "signature", "facebook", "twitter", "instagram", "linkedin", "youtube"]
                .contains { lowercasedFilename.contains($0) }
            if size > 0 && size < 12_000 {
                return false
            }
            if size < 80_000 && likelyLogoName {
                return false
            }
        }

        return true
    }

    private func bodyText(mimeType target: String) -> String? {
        flattenedParts.first { $0.mimeType == target }?.body?.data?.base64URLDecodedString
    }

    private func header(_ name: String) -> String? {
        headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct InlineImageReference {
    let cid: String
    let mimeType: String
    let attachmentId: String?
    let embeddedData: Data?

    var cidVariants: [String] {
        [
            cid,
            cid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cid
        ]
    }
}

private func displayName(fromHeader: String) -> String {
    let trimmed = fromHeader.trimmingCharacters(in: .whitespacesAndNewlines)
    if let range = trimmed.range(of: "<") {
        let name = trimmed[..<range.lowerBound]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        if !name.isEmpty {
            return String(name)
        }
    }
    return trimmed.isEmpty ? "Unknown sender" : trimmed
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var encoded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 {
            encoded.append("=")
        }
        self.init(base64Encoded: encoded)
    }
}
