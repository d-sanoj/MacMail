import Foundation

struct GmailAccount: Identifiable, Codable, Hashable {
    let id: String
    var email: String
    var displayName: String
    var avatarURL: URL?
    var isActive: Bool
}

struct GmailLabel: Identifiable, Codable, Hashable {
    enum LabelType: String, Codable {
        case system
        case category
        case user
    }

    let id: String
    var accountId: String
    var name: String
    var type: LabelType
    var colorHex: String?
    var unreadCount: Int
    var totalCount: Int
}

struct GmailThread: Identifiable, Codable, Hashable {
    let id: String
    var accountId: String
    var snippet: String
    var subject: String
    var senderDisplay: String
    var lastMessageDate: Date
    var labelIds: [String]
    var isUnread: Bool
    var isStarred: Bool
    var hasAttachments: Bool
}

struct GmailMessage: Identifiable, Codable, Hashable {
    let id: String
    var threadId: String
    var accountId: String
    var from: String
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var messageId: String?
    var date: Date
    var snippet: String
    var plainTextBody: String?
    var htmlBody: String?
    var labelIds: [String]
    var isUnread: Bool
    var isStarred: Bool
    var attachments: [GmailAttachment]
}

struct GmailAttachment: Identifiable, Codable, Hashable {
    let id: String
    var messageId: String
    var filename: String
    var mimeType: String
    var size: Int
    var attachmentId: String
    var isDownloaded: Bool
    var localFileURL: URL?
}

struct GmailProfile: Decodable {
    let emailAddress: String
    let messagesTotal: Int
    let threadsTotal: Int
    let historyId: String
}

struct GmailHistoryResponse: Decodable {
    let history: [GmailHistoryRecord]?
    let nextPageToken: String?
    let historyId: String
}

struct GmailHistoryRecord: Decodable {
    let id: String
    let messages: [HistoryMessage]?
    let messagesAdded: [HistoryMessageAdded]?
    let messagesDeleted: [HistoryMessageDeleted]?
    let labelsAdded: [HistoryLabelAdded]?
    let labelsRemoved: [HistoryLabelRemoved]?

    struct HistoryMessage: Decodable {
        let id: String
        let threadId: String
    }
    struct HistoryMessageAdded: Decodable {
        let message: HistoryMessage
    }
    struct HistoryMessageDeleted: Decodable {
        let message: HistoryMessage
    }
    struct HistoryLabelAdded: Decodable {
        let message: HistoryMessage
        let labelIds: [String]
    }
    struct HistoryLabelRemoved: Decodable {
        let message: HistoryMessage
        let labelIds: [String]
    }
}

struct GmailDraft: Identifiable, Codable, Hashable {
    let id: String
    var accountId: String
    var threadId: String?
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var body: String
    var updatedAt: Date
}

struct SyncState: Codable, Hashable {
    var accountId: String
    var historyId: String?
    var lastFullSyncDate: Date?
    var lastIncrementalSyncDate: Date?
}

enum MailboxSelection: Hashable, Identifiable {
    case system(String)
    case category(String)
    case label(String)

    var id: String {
        switch self {
        case .system(let id): "system:\(id)"
        case .category(let id): "category:\(id)"
        case .label(let id): "label:\(id)"
        }
    }

    var gmailLabelId: String {
        switch self {
        case .system(let id), .category(let id), .label(let id):
            id
        }
    }
}

enum GmailSystemLabel {
    static let inbox = "INBOX"
    static let starred = "STARRED"
    static let important = "IMPORTANT"
    static let snoozed = "SNOOZED"
    static let scheduled = "SCHEDULED"
    static let sent = "SENT"
    static let drafts = "DRAFT"
    static let trash = "TRASH"
    static let spam = "SPAM"
    static let allMail = "ALL_MAIL"
    static let unread = "UNREAD"
}

enum GmailCategoryLabel {
    static let primary = "CATEGORY_PERSONAL"
    static let social = "CATEGORY_SOCIAL"
    static let promotions = "CATEGORY_PROMOTIONS"
    static let updates = "CATEGORY_UPDATES"
    static let forums = "CATEGORY_FORUMS"
    static let purchases = "CATEGORY_PURCHASES"
}

enum MailActionError: LocalizedError {
    case missingActiveAccount
    case missingOAuthConfiguration
    case invalidOAuthCallback
    case oauthTimedOut
    case tokenExchangeFailed
    case cacheFailure(String)
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingActiveAccount:
            "Add or select a Gmail account first."
        case .missingOAuthConfiguration:
            "Replace GoogleOAuthClient.json with the downloaded Google desktop OAuth client file."
        case .invalidOAuthCallback:
            "Google did not return a valid OAuth callback."
        case .oauthTimedOut:
            "Google sign-in timed out. Finish the browser consent screen, then try again if the page did not return to GmailBox."
        case .tokenExchangeFailed:
            "Google OAuth token exchange failed."
        case .cacheFailure(let message):
            "Local cache failed: \(message)"
        case .apiFailure(let message):
            "Gmail API failed: \(message)"
        }
    }
}
