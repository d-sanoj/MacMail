import Foundation

enum SampleData {
    static let accounts: [GmailAccount] = [
        GmailAccount(id: "personal", email: "personal@example.com", displayName: "Personal", avatarURL: nil, isActive: true),
        GmailAccount(id: "work", email: "work@example.com", displayName: "Work", avatarURL: nil, isActive: true),
        GmailAccount(id: "projects", email: "projects@example.com", displayName: "Projects", avatarURL: nil, isActive: true)
    ]

    static func labels(for accountId: String) -> [GmailLabel] {
        [
            GmailLabel(id: GmailSystemLabel.inbox, accountId: accountId, name: "Inbox", type: .system, colorHex: nil, unreadCount: 8, totalCount: 42),
            GmailLabel(id: GmailSystemLabel.starred, accountId: accountId, name: "Starred", type: .system, colorHex: nil, unreadCount: 1, totalCount: 9),
            GmailLabel(id: GmailSystemLabel.important, accountId: accountId, name: "Important", type: .system, colorHex: nil, unreadCount: 0, totalCount: 6),
            GmailLabel(id: GmailSystemLabel.sent, accountId: accountId, name: "Sent", type: .system, colorHex: nil, unreadCount: 0, totalCount: 120),
            GmailLabel(id: GmailCategoryLabel.purchases, accountId: accountId, name: "Purchases", type: .category, colorHex: nil, unreadCount: 0, totalCount: 8),
            GmailLabel(id: GmailSystemLabel.snoozed, accountId: accountId, name: "Snoozed", type: .system, colorHex: nil, unreadCount: 0, totalCount: 3),
            GmailLabel(id: GmailSystemLabel.scheduled, accountId: accountId, name: "Scheduled", type: .system, colorHex: nil, unreadCount: 0, totalCount: 0),
            GmailLabel(id: GmailSystemLabel.drafts, accountId: accountId, name: "Drafts", type: .system, colorHex: nil, unreadCount: 0, totalCount: 2),
            GmailLabel(id: GmailSystemLabel.allMail, accountId: accountId, name: "All Mail", type: .system, colorHex: nil, unreadCount: 11, totalCount: 450),
            GmailLabel(id: GmailSystemLabel.spam, accountId: accountId, name: "Spam", type: .system, colorHex: nil, unreadCount: 20, totalCount: 20),
            GmailLabel(id: GmailSystemLabel.trash, accountId: accountId, name: "Trash", type: .system, colorHex: nil, unreadCount: 0, totalCount: 7),
            GmailLabel(id: "Label_Conversation_History", accountId: accountId, name: "Conversation History", type: .user, colorHex: "#5F6368", unreadCount: 0, totalCount: 3)
        ]
    }

    static func threads(for accountId: String) -> [GmailThread] {
        [
            GmailThread(id: "\(accountId)-1", accountId: accountId, snippet: "The review notes are ready. I kept the thread context intact so the next pass is easier.", subject: "Review notes for the dashboard", senderDisplay: "Avery", lastMessageDate: Date().addingTimeInterval(-900), labelIds: [GmailSystemLabel.inbox, GmailCategoryLabel.primary, GmailSystemLabel.unread], isUnread: true, isStarred: true, hasAttachments: false),
            GmailThread(id: "\(accountId)-2", accountId: accountId, snippet: "Your June statement is available. Open the attachment only when you want to download it.", subject: "Monthly statement", senderDisplay: "North Bank", lastMessageDate: Date().addingTimeInterval(-3600 * 3), labelIds: [GmailSystemLabel.inbox, GmailCategoryLabel.purchases], isUnread: false, isStarred: false, hasAttachments: true),
            GmailThread(id: "\(accountId)-3", accountId: accountId, snippet: "Flights changed by 12 minutes. No action is needed unless you want a different seat.", subject: "Trip update: Chicago to San Francisco", senderDisplay: "Airline Alerts", lastMessageDate: Date().addingTimeInterval(-3600 * 7), labelIds: [GmailSystemLabel.inbox, GmailSystemLabel.important], isUnread: true, isStarred: false, hasAttachments: false),
            GmailThread(id: "\(accountId)-4", accountId: accountId, snippet: "Three new posts from people you follow and one event invite for this weekend.", subject: "Your weekly social digest", senderDisplay: "Neighborhood", lastMessageDate: Date().addingTimeInterval(-3600 * 18), labelIds: [GmailSystemLabel.inbox, GmailCategoryLabel.social], isUnread: false, isStarred: false, hasAttachments: false),
            GmailThread(id: "\(accountId)-5", accountId: accountId, snippet: "A few quiet deals surfaced in tools you already use.", subject: "Friday software deals", senderDisplay: "Toolbox", lastMessageDate: Date().addingTimeInterval(-3600 * 30), labelIds: [GmailSystemLabel.inbox, GmailCategoryLabel.promotions], isUnread: false, isStarred: false, hasAttachments: false)
        ]
    }

    static func messages(for thread: GmailThread) -> [GmailMessage] {
        [
            GmailMessage(
                id: "\(thread.id)-message",
                threadId: thread.id,
                accountId: thread.accountId,
                from: "\(thread.senderDisplay) <sender@example.com>",
                to: ["me@example.com"],
                cc: [],
                bcc: [],
                subject: thread.subject,
                date: thread.lastMessageDate,
                snippet: thread.snippet,
                plainTextBody: "\(thread.snippet)\n\nThis is sample cached content. Once Google OAuth is configured, GmailBox loads thread messages through the Gmail API and stores them locally.",
                htmlBody: nil,
                labelIds: thread.labelIds,
                isUnread: thread.isUnread,
                isStarred: thread.isStarred,
                attachments: thread.hasAttachments ? [
                    GmailAttachment(id: "\(thread.id)-attachment", messageId: "\(thread.id)-message", filename: "statement.pdf", mimeType: "application/pdf", size: 245_760, attachmentId: "sample-attachment", isDownloaded: false, localFileURL: nil)
                ] : []
            )
        ]
    }
}
