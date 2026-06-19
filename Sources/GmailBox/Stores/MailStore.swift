import AppKit
import Foundation
import SwiftUI

@MainActor
final class MailStore: ObservableObject {
    @Published private(set) var accounts: [GmailAccount] = []
    @Published var selectedAccountId: String?
    @Published var selectedMailbox: MailboxSelection = .system(GmailSystemLabel.inbox)
    @Published var selectedThreadId: String?
    @Published var searchText = ""
    @Published private(set) var labels: [GmailLabel] = []
    @Published private(set) var threads: [GmailThread] = []
    @Published private(set) var messages: [GmailMessage] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var lastSyncDate: Date?
    @Published var errorMessage: String?
    @Published var showingComposer = false
    @Published var showingSettings = false
    @Published private(set) var oauthSummary = GoogleOAuthClientStore.currentSummary()

    @AppStorage("HiddenLabelIds") var hiddenLabelIdsRaw: String = ""

    var hiddenLabelIds: Set<String> {
        get { Set(hiddenLabelIdsRaw.split(separator: ",").map(String.init)) }
        set { hiddenLabelIdsRaw = newValue.joined(separator: ",") }
    }

    @AppStorage("isSidebarCollapsed") var isSidebarCollapsed = false
    @AppStorage("ShowLabelsOnMessages") var showLabelsOnMessages = true
    @AppStorage("ShowToolbarText") var showToolbarText = true

    @AppStorage("HiddenToolbarButtons") var hiddenToolbarButtonsRaw: String = ""
    var hiddenToolbarButtons: Set<String> {
        get { Set(hiddenToolbarButtonsRaw.split(separator: ",").map(String.init)) }
        set { hiddenToolbarButtonsRaw = newValue.joined(separator: ",") }
    }

    func toggleToolbarButton(_ id: String, isVisible: Bool) {
        var hidden = hiddenToolbarButtons
        if isVisible {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
        hiddenToolbarButtons = hidden
    }

    private let oauthService: GoogleOAuthService
    private let apiClient: GmailAPIClient
    private let cache: SQLiteCacheStore
    private let backgroundRefreshPageSize = 75
    private var refreshTask: Task<Void, Never>?

    init(
        oauthService: GoogleOAuthService = GoogleOAuthService(tokenStore: LocalTokenStore()),
        apiClient: GmailAPIClient = GmailAPIClient(),
        cache: SQLiteCacheStore = SQLiteCacheStore()
    ) {
        self.oauthService = oauthService
        self.apiClient = apiClient
        self.cache = cache
    }

    var selectedAccount: GmailAccount? {
        accounts.first { $0.id == selectedAccountId } ?? accounts.first
    }

    var selectedThread: GmailThread? {
        filteredThreads.first { $0.id == selectedThreadId } ?? filteredThreads.first
    }

    var filteredThreads: [GmailThread] {
        let selectedLabel = selectedMailbox.gmailLabelId
        let matchingMailbox = threads.filter { thread in
            if thread.labelIds.contains(GmailSystemLabel.trash) {
                return selectedLabel == GmailSystemLabel.trash
            }
            if thread.labelIds.contains(GmailSystemLabel.spam) {
                return selectedLabel == GmailSystemLabel.spam
            }
            if selectedLabel == GmailCategoryLabel.primary {
                return thread.labelIds.contains(GmailCategoryLabel.primary) || thread.labelIds.contains(GmailCategoryLabel.updates)
            }
            return selectedLabel == GmailSystemLabel.allMail || thread.labelIds.contains(selectedLabel)
        }
        let results: [GmailThread]
        if searchText.isEmpty {
            results = matchingMailbox
        } else {
            results = matchingMailbox.filter {
                $0.subject.localizedCaseInsensitiveContains(searchText)
                    || $0.senderDisplay.localizedCaseInsensitiveContains(searchText)
                    || $0.snippet.localizedCaseInsensitiveContains(searchText)
            }
        }
        return results.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    func count(for selection: MailboxSelection) -> (unread: Int, total: Int) {
        let labelId = selection.gmailLabelId
        let matchingMailbox = threads.filter { thread in
            if thread.labelIds.contains(GmailSystemLabel.trash) {
                return labelId == GmailSystemLabel.trash
            }
            if thread.labelIds.contains(GmailSystemLabel.spam) {
                return labelId == GmailSystemLabel.spam
            }
            if labelId == GmailSystemLabel.allMail {
                return true
            }
            if labelId == GmailCategoryLabel.primary {
                return thread.labelIds.contains(GmailCategoryLabel.primary) || thread.labelIds.contains(GmailCategoryLabel.updates)
            }
            return thread.labelIds.contains(labelId)
        }
        let unread = matchingMailbox.filter { $0.isUnread }.count
        return (unread, matchingMailbox.count)
    }

    var selectedMessages: [GmailMessage] {
        guard let selectedThread else { return [] }
        return messages
            .filter { $0.threadId == selectedThread.id }
            .sorted { $0.date > $1.date }
    }

    var systemLabels: [GmailLabel] {
        labels.filter { $0.type == .system && $0.id != GmailSystemLabel.unread }
    }

    var categoryLabels: [GmailLabel] {
        labels.filter { $0.type == .category }
    }

    var customLabels: [GmailLabel] {
        labels.filter { $0.type == .user }
    }

    var hasAccounts: Bool {
        !accounts.isEmpty
    }

    func load() {
        NotificationService.requestAuthorization()
        refreshOAuthSummary()
        do {
            try cache.open()
            accounts = removeDemoAccounts(from: try cache.loadAccounts())
                .filter { oauthService.hasStoredTokens(for: $0) }
            try cache.saveAccounts(accounts)
            selectedAccountId = selectedAccountId ?? accounts.first?.id
            loadCachedMailbox()
        } catch {
            errorMessage = error.localizedDescription
            accounts = []
            selectedAccountId = nil
            clearMailbox()
        }
    }

    func refreshOAuthSummary() {
        oauthSummary = GoogleOAuthClientStore.currentSummary()
    }

    func signInWithGoogle() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                let account = try await oauthService.signIn()
                if !accounts.contains(where: { $0.id == account.id }) {
                    accounts.append(account)
                }
                selectedAccountId = account.id
                try cache.saveAccounts(accounts)
                await syncAllOldMessages()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeSelectedAccount() {
        guard let account = selectedAccount else { return }
        do {
            try oauthService.removeAccount(account)
            accounts.removeAll { $0.id == account.id }
            selectedAccountId = accounts.first?.id
            try cache.saveAccounts(accounts)
            loadCachedMailbox()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchAccount(to accountId: String) {
        selectedAccountId = accountId
        selectedThreadId = nil
        loadCachedMailbox()
    }

    func selectMailbox(_ selection: MailboxSelection) {
        selectedMailbox = selection
        selectedThreadId = nil
        if let first = filteredThreads.first {
            selectedThreadId = first.id
            loadCachedMessages(for: first)
        }
    }

    func selectThread(_ thread: GmailThread) {
        selectedThreadId = thread.id
        loadCachedMessages(for: thread)
        if selectedMessages.isEmpty {
            loadSelectedThreadFromAPI()
        }
    }

    func refresh() async {
        await syncAccountMailboxes(full: true, notifyNewMail: false, showMissingAccountError: true)
    }

    func syncAllOldMessages() async {
        await syncAccountMailboxes(full: true, notifyNewMail: false, showMissingAccountError: true)
    }

    func performBackgroundCheck() async {
        await syncAccountMailboxes(full: true, notifyNewMail: true, showMissingAccountError: false)
    }

    func loadSelectedThreadFromAPI() {
        guard let account = selectedAccount, let thread = selectedThread else { return }
        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                var loadedMessages = try await apiClient.messages(for: thread.id, accessToken: token)
                loadedMessages = loadedMessages.map { message in
                    var message = message
                    message.accountId = account.id
                    return message
                }
                messages.removeAll { $0.threadId == thread.id && $0.accountId == account.id }
                messages.append(contentsOf: loadedMessages)
                try cache.saveMessages(loadedMessages, accountId: account.id)
                updateThreadSummary(threadId: thread.id, accountId: account.id, messages: loadedMessages)
                try cache.saveThreads(threads.filter { $0.accountId == account.id }, accountId: account.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func sendEmail(to: String, cc: String, bcc: String, subject: String, plainText: String, htmlBody: String?, attachments: [URL]) {
        guard let account = selectedAccount else {
            errorMessage = "Sign in with a Gmail account before sending."
            return
        }

        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                let rawMessage = try MIMEMessageBuilder.build(
                    from: account.email,
                    to: to,
                    cc: cc,
                    bcc: bcc,
                    subject: subject,
                    plainText: plainText,
                    htmlBody: htmlBody,
                    attachments: attachments
                )
                try await apiClient.sendMessage(accessToken: token, rawRFC822Base64URL: rawMessage)
                showingComposer = false
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func downloadAttachment(_ attachment: GmailAttachment, saveTo destinationURL: URL) {
        guard let account = selectedAccount else {
            errorMessage = "Sign in with a Gmail account before downloading attachments."
            return
        }

        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                let data = try await apiClient.attachmentData(
                    accessToken: token,
                    messageId: attachment.messageId,
                    attachmentId: attachment.attachmentId
                )
                try data.write(to: destinationURL, options: [.atomic])
                markAttachmentDownloaded(attachment, localFileURL: destinationURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func localPreviewURL(for attachment: GmailAttachment) async throws -> URL {
        if let localFileURL = attachment.localFileURL {
            return localFileURL
        }

        let previewURL = FileManager.default.temporaryDirectory
            .appending(path: "GmailBoxPreviews", directoryHint: .isDirectory)
            .appending(path: attachment.filename)

        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let account = selectedAccount else {
            throw MailActionError.missingActiveAccount
        }
        let token = try await oauthService.validAccessToken(for: account)
        let data = try await apiClient.attachmentData(
            accessToken: token,
            messageId: attachment.messageId,
            attachmentId: attachment.attachmentId
        )
        try data.write(to: previewURL, options: [.atomic])
        return previewURL
    }

    func archiveSelectedThread() {
        modifySelectedThread(remove: [GmailSystemLabel.inbox])
    }

    func trashSelectedThread() {
        guard let thread = selectedThread else { return }
        trashThread(thread)
    }

    func trashThread(_ thread: GmailThread) {
        guard let account = selectedAccount else { return }
        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                try await apiClient.trashThread(accessToken: token, threadId: thread.id)
                
                if let index = threads.firstIndex(where: { $0.id == thread.id && $0.accountId == account.id }) {
                    if !threads[index].labelIds.contains(GmailSystemLabel.trash) {
                        threads[index].labelIds.append(GmailSystemLabel.trash)
                    }
                    try cache.saveThreads(threads.filter { $0.accountId == account.id }, accountId: account.id)
                }
                
                if selectedThreadId == thread.id {
                    selectedThreadId = filteredThreads.first?.id
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleUnreadSelectedThread() {
        guard let thread = selectedThread else { return }
        if thread.isUnread {
            modifySelectedThread(remove: [GmailSystemLabel.unread])
        } else {
            modifySelectedThread(add: [GmailSystemLabel.unread])
        }
    }

    func modifySelectedThreadForSpam() {
        modifySelectedThread(add: [GmailSystemLabel.spam], remove: [GmailSystemLabel.inbox])
    }

    func toggleStar(_ thread: GmailThread) {
        if thread.isStarred {
            modifyThread(thread, remove: [GmailSystemLabel.starred])
        } else {
            modifyThread(thread, add: [GmailSystemLabel.starred])
        }
    }

    func apply(label: GmailLabel, to thread: GmailThread) {
        modifyThread(thread, add: [label.id])
    }

    func remove(label: GmailLabel, from thread: GmailThread) {
        modifyThread(thread, remove: [label.id])
    }

    func createLabel(name: String) {
        guard let account = selectedAccount else {
            errorMessage = "Sign in with a Gmail account before creating labels."
            return
        }

        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                var newLabel = try await apiClient.createLabel(accessToken: token, name: name)
                newLabel.accountId = account.id
                labels.append(newLabel)
                try cache.saveLabels(labels.filter { $0.accountId == account.id }, accountId: account.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteLabel(_ label: GmailLabel) {
        guard let account = selectedAccount else { return }

        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                try await apiClient.deleteLabel(accessToken: token, labelId: label.id)
                labels.removeAll { $0.id == label.id && $0.accountId == account.id }
                try cache.saveLabels(labels.filter { $0.accountId == account.id }, accountId: account.id)
                if case .label(let id) = selectedMailbox, id == label.id {
                    selectedMailbox = .system(GmailSystemLabel.inbox)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func modifySelectedThread(add: [String] = [], remove: [String] = []) {
        guard let thread = selectedThread else { return }
        modifyThread(thread, add: add, remove: remove)
    }

    private func modifyThread(_ thread: GmailThread, add: [String] = [], remove: [String] = []) {
        guard let account = selectedAccount else { return }
        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                try await apiClient.modifyThread(accessToken: token, threadId: thread.id, addLabelIds: add, removeLabelIds: remove)
                if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                    var updated = threads[index]
                    updated.labelIds.removeAll { remove.contains($0) }
                    updated.labelIds.append(contentsOf: add.filter { !updated.labelIds.contains($0) })
                    updated.isUnread = updated.labelIds.contains(GmailSystemLabel.unread)
                    updated.isStarred = updated.labelIds.contains(GmailSystemLabel.starred)
                    threads[index] = updated
                    try cache.saveThreads(threads.filter { $0.accountId == account.id }, accountId: account.id)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadCachedMailbox() {
        guard let account = selectedAccount else {
            labels = []
            threads = []
            messages = []
            return
        }
        do {
            labels = try cache.loadLabels(accountId: account.id)
            threads = try cache.loadThreads(accountId: account.id)
            if hasLegacySampleLabels(labels) {
                labels = []
                threads = []
                try cache.saveLabels(labels, accountId: account.id)
                try cache.saveThreads(threads, accountId: account.id)
            }
            selectedThreadId = filteredThreads.first?.id
            if let selectedThread {
                loadCachedMessages(for: selectedThread)
            }
        } catch {
            errorMessage = error.localizedDescription
            clearMailbox()
        }
    }

    private func loadCachedMessages(for thread: GmailThread) {
        do {
            let cached = try cache.loadMessages(threadId: thread.id, accountId: thread.accountId)
            messages.removeAll { $0.threadId == thread.id && $0.accountId == thread.accountId }
            messages.append(contentsOf: cached)
        } catch {
            errorMessage = error.localizedDescription
            messages.removeAll { $0.threadId == thread.id && $0.accountId == thread.accountId }
        }
    }

    private func clearMailbox() {
        labels = []
        threads = []
        messages = []
        selectedThreadId = nil
    }

    private func updateThreadSummary(threadId: String, accountId: String, messages: [GmailMessage]) {
        guard let latest = messages.max(by: { $0.date < $1.date }),
              let index = threads.firstIndex(where: { $0.id == threadId && $0.accountId == accountId }) else {
            return
        }

        let labelIds = Array(Set(messages.flatMap(\.labelIds)))
        threads[index].subject = latest.subject.isEmpty ? "(No subject)" : latest.subject
        threads[index].senderDisplay = displayName(fromHeader: latest.from)
        threads[index].snippet = latest.snippet
        threads[index].lastMessageDate = latest.date
        threads[index].labelIds = labelIds
        threads[index].isUnread = labelIds.contains(GmailSystemLabel.unread)
        threads[index].isStarred = labelIds.contains(GmailSystemLabel.starred)
        threads[index].hasAttachments = messages.contains { !$0.attachments.isEmpty }
    }

    private func markAttachmentDownloaded(_ attachment: GmailAttachment, localFileURL: URL) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == attachment.messageId }),
              let attachmentIndex = messages[messageIndex].attachments.firstIndex(where: { $0.id == attachment.id }) else {
            return
        }

        messages[messageIndex].attachments[attachmentIndex].isDownloaded = true
        messages[messageIndex].attachments[attachmentIndex].localFileURL = localFileURL
        messages = messages

        if let account = selectedAccount {
            try? cache.saveMessages(messages.filter { $0.accountId == account.id }, accountId: account.id)
        }
    }

    private func syncAccountMailboxes(full: Bool, notifyNewMail: Bool, showMissingAccountError: Bool) async {
        guard let account = selectedAccount else {
            if showMissingAccountError {
                errorMessage = MailActionError.missingActiveAccount.localizedDescription
            }
            return
        }
        guard !isSyncing && !isSigningIn else { return }

        let previousInboxThreadIds = Set(threads.filter { $0.accountId == account.id && $0.labelIds.contains(GmailSystemLabel.inbox) }.map(\.id))
        isSyncing = true
        defer { isSyncing = false }

        do {
            let token = try await oauthService.validAccessToken(for: account)
            var loadedLabels = try await apiClient.labels(accessToken: token)
            loadedLabels = loadedLabels.map { label in
                var label = label
                label.accountId = account.id
                return label
            }

            let loadedThreads = try await syncedThreads(
                accessToken: token,
                accountId: account.id,
                labels: loadedLabels,
                full: full
            )

            labels = loadedLabels
            threads = loadedThreads
            try cache.saveLabels(loadedLabels, accountId: account.id)
            try cache.saveThreads(loadedThreads, accountId: account.id)
            try cache.saveSyncState(SyncState(
                accountId: account.id,
                historyId: nil,
                lastFullSyncDate: full ? Date() : nil,
                lastIncrementalSyncDate: full ? nil : Date()
            ))
            lastSyncDate = Date()

            if selectedThreadId == nil || selectedThread == nil {
                selectedThreadId = filteredThreads.first?.id
            }
            if let selectedThread {
                loadCachedMessages(for: selectedThread)
                if selectedMessages.isEmpty {
                    loadSelectedThreadFromAPI()
                }
            }

            let currentInboxThreadIds = Set(threads.filter { $0.accountId == account.id && $0.labelIds.contains(GmailSystemLabel.inbox) }.map(\.id))
            let newMailCount = currentInboxThreadIds.subtracting(previousInboxThreadIds).count
            if notifyNewMail && !previousInboxThreadIds.isEmpty && newMailCount > 0 {
                NotificationService.notifyNewMail(count: newMailCount)
            }
        } catch {
            if showMissingAccountError {
                errorMessage = error.localizedDescription
            }
            loadCachedMailbox()
        }
    }

    private func syncedThreads(accessToken: String, accountId: String, labels: [GmailLabel], full: Bool) async throws -> [GmailThread] {
        var mergedThreads = Dictionary(uniqueKeysWithValues: threads
            .filter { $0.accountId == accountId }
            .map { ($0.id, $0) })

        if full {
            let accountThreads = try await apiClient.allThreads(
                accessToken: accessToken,
                pageSize: 100,
                includeSpamTrash: true
            )
            merge(accountThreads, accountId: accountId, into: &mergedThreads)
        }

        for labelId in syncLabelIds(from: labels) {
            let labelThreads = try await apiClient.threads(
                accessToken: accessToken,
                query: nil,
                labelId: labelId,
                maxResults: backgroundRefreshPageSize,
                includeSpamTrash: true
            )
            merge(labelThreads, accountId: accountId, into: &mergedThreads)
        }

        return mergedThreads.values.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    private func merge(_ freshThreads: [GmailThread], accountId: String, into mergedThreads: inout [String: GmailThread]) {
        for freshThread in freshThreads {
            var thread = freshThread
            thread.accountId = accountId

            guard var existing = mergedThreads[thread.id] else {
                mergedThreads[thread.id] = thread
                continue
            }

            if thread.lastMessageDate >= existing.lastMessageDate {
                existing.snippet = thread.snippet
                existing.subject = thread.subject
                existing.senderDisplay = thread.senderDisplay
                existing.lastMessageDate = thread.lastMessageDate
                existing.hasAttachments = thread.hasAttachments
            } else {
                existing.hasAttachments = existing.hasAttachments || thread.hasAttachments
            }

            existing.labelIds = thread.labelIds.sorted()
            existing.isUnread = existing.labelIds.contains(GmailSystemLabel.unread)
            existing.isStarred = existing.labelIds.contains(GmailSystemLabel.starred)
            mergedThreads[thread.id] = existing
        }
    }

    private func syncLabelIds(from labels: [GmailLabel]) -> [String] {
        let availableIds = Set(labels.map(\.id))
        let preferredSystemIds = [
            GmailSystemLabel.inbox,
            GmailSystemLabel.sent,
            GmailSystemLabel.drafts,
            GmailSystemLabel.starred,
            GmailSystemLabel.important,
            GmailSystemLabel.snoozed,
            GmailSystemLabel.scheduled,
            GmailSystemLabel.spam,
            GmailSystemLabel.trash,
            GmailSystemLabel.allMail,
            GmailCategoryLabel.primary,
            GmailCategoryLabel.promotions,
            GmailCategoryLabel.social,
            GmailCategoryLabel.updates,
            GmailCategoryLabel.forums,
            GmailCategoryLabel.purchases
        ].filter { availableIds.contains($0) }
        let customIds = labels.filter { $0.type == .user }.map(\.id)
        return Array(Set(preferredSystemIds + customIds)).sorted()
    }

    private func hasLegacySampleLabels(_ labels: [GmailLabel]) -> Bool {
        labels.contains { $0.id == "Label_Receipts" || $0.id == "Label_Travel" }
    }

    private func removeDemoAccounts(from accounts: [GmailAccount]) -> [GmailAccount] {
        let demoIds = Set(SampleData.accounts.map(\.id))
        return accounts.filter { !demoIds.contains($0.id) && !$0.email.hasSuffix("@example.com") }
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

    func startBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if !Task.isCancelled {
                    await performBackgroundCheck()
                }
            }
        }
    }

    func stopBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
