import AppKit
import Foundation
import SwiftUI

enum ComposeAction: Equatable {
    case new
    case reply(GmailMessage)
    case replyAll(GmailMessage)
    case forward(GmailMessage)
}

@MainActor
final class MailStore: ObservableObject {
    @Published private(set) var accounts: [GmailAccount] = []
    @Published var selectedAccountId: String?
    @Published var selectedMailbox: MailboxSelection = .system(GmailSystemLabel.inbox)
    @Published var selectedThreadIds: Set<String> = []
    @Published var searchText = ""
    @Published private(set) var labels: [GmailLabel] = []
    @Published private(set) var threads: [GmailThread] = []
    @Published private(set) var messages: [GmailMessage] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var syncProgressCount: Int = 0
    @Published private(set) var syncProgressTotal: Int = 0
    @Published private(set) var isSigningIn = false
    @Published private(set) var lastSyncDate: Date?
    @Published var errorMessage: String?
    @Published var showingComposer = false
    @Published var composeAction: ComposeAction = .new
    @Published var showingSettings = false
    @Published private(set) var oauthSummary = GoogleOAuthClientStore.currentSummary()

    var hiddenLabelIds: Set<String> {
        get {
            guard let accountId = selectedAccountId else { return [] }
            let raw = UserDefaults.standard.string(forKey: "HiddenLabelIds_\(accountId)") ?? ""
            return Set(raw.split(separator: ",").map(String.init))
        }
        set {
            guard let accountId = selectedAccountId else { return }
            UserDefaults.standard.set(newValue.joined(separator: ","), forKey: "HiddenLabelIds_\(accountId)")
            objectWillChange.send()
        }
    }

    @AppStorage("isSidebarCollapsed") var isSidebarCollapsed = false
    @AppStorage("ShowLabelsOnMessages") var showLabelsOnMessages = true
    @AppStorage("ShowToolbarText") var showToolbarText = true

    @AppStorage("HiddenToolbarButtons") var hiddenToolbarButtonsRaw: String = ""
    var hiddenToolbarButtons: Set<String> {
        get { Set(hiddenToolbarButtonsRaw.split(separator: ",").map(String.init)) }
        set { hiddenToolbarButtonsRaw = newValue.joined(separator: ",") }
    }

    func openComposer(for action: ComposeAction = .new) {
        composeAction = action
        showingComposer = true
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
        if selectedThreadIds.count == 1, let id = selectedThreadIds.first {
            return filteredThreads.first { $0.id == id }
        }
        return nil
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
        guard selectedThreadIds.count == 1, let id = selectedThreadIds.first else { return [] }
        return messages
            .filter { $0.threadId == id }
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

    var isTrashFolder: Bool {
        if case .system(let id) = selectedMailbox, id == GmailSystemLabel.trash {
            return true
        }
        return false
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
            let defaultId = UserDefaults.standard.string(forKey: "defaultAccountId") ?? ""
            if !defaultId.isEmpty, let defaultAcc = accounts.first(where: { $0.id == defaultId }) {
                selectedAccountId = selectedAccountId ?? defaultAcc.id
            } else {
                selectedAccountId = selectedAccountId ?? accounts.first?.id
            }
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
        selectedThreadIds.removeAll()
        loadCachedMailbox()
    }

    func selectMailbox(_ selection: MailboxSelection) {
        if selection == .system(GmailSystemLabel.inbox) {
            selectedMailbox = .category(GmailCategoryLabel.primary)
        } else {
            selectedMailbox = selection
        }
        selectedThreadIds.removeAll()
        if let first = filteredThreads.first {
            selectedThreadIds.insert(first.id)
            loadCachedMessages(for: first)
        }
    }

    func selectThread(id: String) {
        selectedThreadIds = [id]
        if let thread = filteredThreads.first(where: { $0.id == id }) {
            loadCachedMessages(for: thread)
            if selectedMessages.isEmpty {
                loadSelectedThreadFromAPI()
            }
            if thread.isUnread {
                markThreadAsRead(thread)
            }
        }
    }

    func markThreadAsRead(_ thread: GmailThread) {
        guard let account = accounts.first(where: { $0.id == thread.accountId }) else { return }
        
        // Optimistically update local state
        if let index = threads.firstIndex(where: { $0.id == thread.id && $0.accountId == account.id }) {
            threads[index].isUnread = false
            threads[index].labelIds.removeAll(where: { $0 == GmailSystemLabel.unread })
            try? cache.saveThreads(threads.filter { $0.accountId == account.id }, accountId: account.id)
        }
        
        // Update label cache count if necessary (optional UI polish)
        if let index = labels.firstIndex(where: { $0.id == GmailSystemLabel.inbox }) {
            labels[index].unreadCount = max(0, labels[index].unreadCount - 1)
        }
        
        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                try await apiClient.modifyThread(accessToken: token, threadId: thread.id, addLabelIds: [], removeLabelIds: [GmailSystemLabel.unread])
            } catch {
                print("Failed to mark thread as read: \(error)")
            }
        }
    }

    func refresh() async {
        await syncAccountMailboxes(full: false, notifyNewMail: false, showMissingAccountError: true, isBackground: false)
    }

    func syncAllOldMessages() async {
        await syncAccountMailboxes(full: true, notifyNewMail: false, showMissingAccountError: true, isBackground: false)
    }

    func performBackgroundCheck() async {
        await syncAccountMailboxes(full: false, notifyNewMail: true, showMissingAccountError: false, isBackground: true)
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

    func sendEmail(to: String, cc: String, bcc: String, subject: String, plainText: String, htmlBody: String?, attachments: [URL], inlineImages: [(cid: String, data: Data, mimeType: String)] = [], threadId: String? = nil, inReplyTo: String? = nil, references: String? = nil) {
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
                    attachments: attachments,
                    inlineImages: inlineImages,
                    inReplyTo: inReplyTo,
                    references: references
                )
                try await apiClient.sendMessage(accessToken: token, rawRFC822Base64URL: rawMessage, threadId: threadId)
                showingComposer = false
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func scheduleEmail(to: String, cc: String, bcc: String, subject: String, plainText: String, htmlBody: String?, attachments: [URL], inlineImages: [(cid: String, data: Data, mimeType: String)] = [], date: Date, threadId: String? = nil, inReplyTo: String? = nil, references: String? = nil) {
        guard let account = selectedAccount else {
            errorMessage = "Sign in with a Gmail account before scheduling."
            return
        }
        
        let rawMessage: String
        do {
            rawMessage = try MIMEMessageBuilder.build(
                from: account.email,
                to: to,
                cc: cc,
                bcc: bcc,
                subject: subject,
                plainText: plainText,
                htmlBody: htmlBody,
                attachments: attachments,
                inlineImages: inlineImages,
                inReplyTo: inReplyTo,
                references: references
            )
        } catch {
            errorMessage = "Failed to build scheduled message: \(error.localizedDescription)"
            return
        }
        
        Task {
            do {
                let token = try await oauthService.validAccessToken(for: account)
                let draftId = try await apiClient.createDraft(accessToken: token, rawRFC822Base64URL: rawMessage, threadId: threadId)
                
                // Set up local timer to send it when the date arrives. 
                // A robust solution would persist this to UserDefaults.
                let delay = max(0, date.timeIntervalSinceNow)
                Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        let freshToken = try await oauthService.validAccessToken(for: account)
                        try await apiClient.sendDraft(accessToken: freshToken, draftId: draftId)
                        await refresh()
                    } catch {
                        print("Failed to send scheduled draft: \(error)")
                    }
                }
                
                showingComposer = false
            } catch {
                errorMessage = "Failed to schedule email: \(error.localizedDescription)"
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

    func archiveSelectedThreads() {
        guard !isTrashFolder else { return }
        modifySelectedThreads(remove: [GmailSystemLabel.inbox])
    }

    func trashSelectedThreads() {
        guard !isTrashFolder else { return }
        let threadsToTrash = filteredThreads.filter { selectedThreadIds.contains($0.id) }
        for thread in threadsToTrash {
            trashThread(thread)
        }
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
                
                if selectedThreadIds.contains(thread.id) {
                    selectedThreadIds.remove(thread.id)
                    if selectedThreadIds.isEmpty, let first = filteredThreads.first {
                        selectedThreadIds.insert(first.id)
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleUnreadSelectedThreads() {
        let selected = filteredThreads.filter { selectedThreadIds.contains($0.id) }
        let allRead = selected.allSatisfy { !$0.isUnread }
        if allRead {
            modifySelectedThreads(add: [GmailSystemLabel.unread])
        } else {
            modifySelectedThreads(remove: [GmailSystemLabel.unread])
        }
    }

    func modifySelectedThreadsForSpam() {
        modifySelectedThreads(add: [GmailSystemLabel.spam], remove: [GmailSystemLabel.inbox])
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

    private func modifySelectedThreads(add: [String] = [], remove: [String] = []) {
        let selected = filteredThreads.filter { selectedThreadIds.contains($0.id) }
        for thread in selected {
            modifyThread(thread, add: add, remove: remove)
        }
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
            selectedThreadIds.removeAll()
            if let first = filteredThreads.first {
                selectedThreadIds.insert(first.id)
            }
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
        selectedThreadIds.removeAll()
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

    private func syncAccountMailboxes(full: Bool, notifyNewMail: Bool, showMissingAccountError: Bool, isBackground: Bool = false) async {
        guard let account = selectedAccount else {
            if showMissingAccountError {
                errorMessage = MailActionError.missingActiveAccount.localizedDescription
            }
            return
        }
        guard !isSyncing && !isSigningIn else { return }

        let previousInboxThreadIds = Set(threads.filter { $0.accountId == account.id && $0.labelIds.contains(GmailSystemLabel.inbox) }.map(\.id))
        
        if !isBackground {
            isSyncing = true
            syncProgressCount = 0
            syncProgressTotal = 0
        }
        
        defer { 
            if !isBackground {
                isSyncing = false 
                syncProgressCount = 0
                syncProgressTotal = 0
            }
        }

        let progressHandler: (Int) -> Void = { count in
            DispatchQueue.main.async {
                self.syncProgressCount += count
            }
        }

        do {
            let token = try await oauthService.validAccessToken(for: account)
            let profile = try await apiClient.profile(accessToken: token)
            let syncState = try? cache.loadSyncState(accountId: account.id)

            let loadedLabels = (try await apiClient.labels(accessToken: token)).map { label in
                var label = label
                label.accountId = account.id
                return label
            }

            var loadedThreads: [GmailThread]? = nil

            if !full, let lastHistoryId = syncState?.historyId {
                do {
                    let historyRecords = try await apiClient.history(accessToken: token, startHistoryId: lastHistoryId)
                    var changedThreadIds = Set<String>()
                    for record in historyRecords {
                        if let added = record.messagesAdded { changedThreadIds.formUnion(added.map(\.message.threadId)) }
                        if let deleted = record.messagesDeleted { changedThreadIds.formUnion(deleted.map(\.message.threadId)) }
                        if let labelsAdded = record.labelsAdded { changedThreadIds.formUnion(labelsAdded.map(\.message.threadId)) }
                        if let labelsRemoved = record.labelsRemoved { changedThreadIds.formUnion(labelsRemoved.map(\.message.threadId)) }
                    }

                    if !changedThreadIds.isEmpty {
                        syncProgressTotal = changedThreadIds.count
                        let hydratedThreads = try await apiClient.hydrateSpecificThreads(Array(changedThreadIds), accessToken: token, progress: progressHandler)
                        
                        var merged = Dictionary(uniqueKeysWithValues: threads.filter { $0.accountId == account.id }.map { ($0.id, $0) })
                        // Remove deleted threads that failed to hydrate (returned nil)
                        let successfulHydrationIds = Set(hydratedThreads.map(\.id))
                        let deletedIds = changedThreadIds.subtracting(successfulHydrationIds)
                        for id in deletedIds {
                            merged.removeValue(forKey: id)
                        }
                        
                        merge(hydratedThreads, accountId: account.id, into: &merged)
                        loadedThreads = merged.values.sorted { $0.lastMessageDate > $1.lastMessageDate }
                    } else {
                        loadedThreads = threads.filter { $0.accountId == account.id }
                    }
                } catch {
                    // History API failed (likely 404 because historyId expired), fallback to incremental sync
                }
            }

            if loadedThreads == nil {
                let syncIds = syncLabelIds(from: loadedLabels)
                let incrementalEstimate = syncIds.count * backgroundRefreshPageSize
                if full {
                    syncProgressTotal = profile.threadsTotal + incrementalEstimate
                } else {
                    syncProgressTotal = incrementalEstimate
                }

                loadedThreads = try await syncedThreads(
                    accessToken: token,
                    accountId: account.id,
                    labels: loadedLabels,
                    full: full,
                    progress: progressHandler
                )
            }

            labels = loadedLabels
            threads = loadedThreads ?? []
            try cache.saveLabels(loadedLabels, accountId: account.id)
            try cache.saveThreads(loadedThreads ?? [], accountId: account.id)
            try cache.saveSyncState(SyncState(
                accountId: account.id,
                historyId: profile.historyId,
                lastFullSyncDate: full ? Date() : syncState?.lastFullSyncDate,
                lastIncrementalSyncDate: full ? syncState?.lastIncrementalSyncDate : Date()
            ))
            lastSyncDate = Date()

            if selectedThreadIds.isEmpty || selectedThread == nil {
                selectedThreadIds.removeAll()
                if let first = filteredThreads.first {
                    selectedThreadIds.insert(first.id)
                }
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

    private func syncedThreads(accessToken: String, accountId: String, labels: [GmailLabel], full: Bool, progress: ((Int) -> Void)? = nil) async throws -> [GmailThread] {
        var mergedThreads = Dictionary(uniqueKeysWithValues: threads
            .filter { $0.accountId == accountId }
            .map { ($0.id, $0) })

        if full {
            let accountThreads = try await apiClient.allThreads(
                accessToken: accessToken,
                pageSize: 100,
                includeSpamTrash: true,
                progress: progress
            )
            merge(accountThreads, accountId: accountId, into: &mergedThreads)
        }

        for labelId in syncLabelIds(from: labels) {
            let labelThreads = try await apiClient.threads(
                accessToken: accessToken,
                query: nil,
                labelId: labelId,
                maxResults: backgroundRefreshPageSize,
                includeSpamTrash: true,
                progress: progress
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
