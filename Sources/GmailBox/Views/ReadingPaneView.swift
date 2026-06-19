import AppKit
import QuickLook
import SwiftUI

struct ReadingPaneView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(spacing: 0) {
            if let thread = store.selectedThread {
                header(thread)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    subjectBlock(thread)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    
                    ForEach(store.selectedMessages) { message in
                        MessageHeaderView(message: message, store: store)
                            .padding(.horizontal, 20)
                        
                        MessageBodyCard(message: message)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select a conversation",
                    systemImage: "envelope.open",
                    description: Text("Choose a thread from the list to read it here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func toolbarLabel(_ title: String, icon: String) -> some View {
        if store.showToolbarText {
            Label(title, systemImage: icon)
        } else {
            Image(systemName: icon)
        }
    }

    private func header(_ thread: GmailThread) -> some View {
        HStack(spacing: 10) {
            if !store.hiddenToolbarButtons.contains("archive") {
                Button {
                    store.archiveSelectedThread()
                } label: {
                    toolbarLabel("Archive", icon: "archivebox")
                }
                .help("Archive")
            }

            if !store.hiddenToolbarButtons.contains("delete") {
                Button {
                    store.trashSelectedThread()
                } label: {
                    toolbarLabel("Delete", icon: "trash")
                }
                .help("Delete")
            }

            if !store.hiddenToolbarButtons.contains("unread") {
                Button {
                    store.toggleUnreadSelectedThread()
                } label: {
                    toolbarLabel(thread.isUnread ? "Mark Read" : "Mark Unread", icon: thread.isUnread ? "envelope.open" : "envelope.badge")
                }
                .help(thread.isUnread ? "Mark as read" : "Mark as unread")
            }

            if !store.hiddenToolbarButtons.contains("spam") {
                Button {
                    store.modifySelectedThreadForSpam()
                } label: {
                    toolbarLabel("Report Spam", icon: "exclamationmark.octagon")
                }
                .help("Report Spam")
            }

            if !store.hiddenToolbarButtons.contains("labels") {
                Menu {
                    ForEach(store.customLabels) { label in
                        Button("Apply \(label.name)") {
                            store.apply(label: label, to: thread)
                        }
                    }
                    Divider()
                    ForEach(store.customLabels.filter { thread.labelIds.contains($0.id) }) { label in
                        Button("Remove \(label.name)") {
                            store.remove(label: label, from: thread)
                        }
                    }
                } label: {
                    toolbarLabel("Labels", icon: "tag")
                }
                .help("Labels")
            }

            if !store.hiddenToolbarButtons.contains("more") {
                Menu {
                    Button("Load Full Thread") {
                        store.loadSelectedThreadFromAPI()
                    }
                    Button("Snooze") {
                        store.errorMessage = "Snooze is reserved for a follow-up implementation because Gmail's snooze behavior is not exposed as a simple public Gmail API thread action."
                    }
                } label: {
                    toolbarLabel("More", icon: "ellipsis.circle")
                }
                .help("More")
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func subjectBlock(_ thread: GmailThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(thread.subject)
                .font(.title2)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            if store.showLabelsOnMessages {
                HStack(spacing: 6) {
                    ForEach(store.labels.filter { thread.labelIds.contains($0.id) && $0.type != .system && !$0.name.uppercased().hasPrefix("CATEGORY_") }) { label in
                        Text(label.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((Color(hex: label.colorHex) ?? .secondary).opacity(0.18), in: Capsule())
                    }
                }
            }
        }
    }
}

private struct MessageHeaderView: View {
    let message: GmailMessage
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Circle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .overlay(Text(initials).font(.caption).fontWeight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.from)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                    Text("to \(message.to.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }

                Spacer()

                Text(message.date.mailboxTimestamp)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            if !message.attachments.isEmpty {
                OutlookAttachmentStrip(attachments: message.attachments, store: store)
            }
        }
    }

    private var initials: String {
        message.from.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

private struct MessageBodyCard: View {
    let message: GmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
                HTMLMessageBodyView(html: htmlBody)
            } else {
                ScrollView {
                    Text(message.plainTextBody ?? message.snippet)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct OutlookAttachmentStrip: View {
    let attachments: [GmailAttachment]
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AttachmentChip(attachment: attachment, store: store)
                    }
                }
                .padding(.bottom, 1)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AttachmentChip: View {
    let attachment: GmailAttachment
    @ObservedObject var store: MailStore
    
    @State private var previewURL: URL?
    @State private var isPreparingPreview = false
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.gray)
                    .opacity(isPreparingPreview ? 0.3 : 1)
                
                if isPreparingPreview {
                    ProgressView().controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
                Text(attachment.isDownloaded ? "Downloaded" : ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer()

            if isHovering {
                Button {
                    saveAttachment()
                } label: {
                    Image(systemName: attachment.isDownloaded ? "checkmark" : "arrow.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(attachment.isDownloaded ? .green : .blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .help(attachment.isDownloaded ? "Download again" : "Download")
            } else {
                Color.clear.frame(width: 26, height: 26)
            }
        }
        .padding(8)
        .frame(width: 280, alignment: .leading)
        .background(isFocused ? Color.blue.opacity(0.1) : Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.blue : Color.black.opacity(0.1), lineWidth: 1)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.space) {
            preparePreview()
            return .handled
        }
        .quickLookPreview($previewURL)
    }

    private func preparePreview() {
        if let url = previewURL {
            previewURL = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                previewURL = url
            }
            return
        }
        isPreparingPreview = true
        Task {
            do {
                let url = try await store.localPreviewURL(for: attachment)
                previewURL = url
            } catch {
                store.errorMessage = error.localizedDescription
            }
            isPreparingPreview = false
        }
    }

    private var iconName: String {
        if attachment.mimeType.contains("pdf") { return "doc.richtext" }
        if attachment.mimeType.hasPrefix("image/") { return "photo" }
        if attachment.mimeType.contains("zip") { return "doc.zipper" }
        return "doc"
    }

    private func saveAttachment() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.filename
        panel.canCreateDirectories = true
        panel.title = "Save Attachment"
        panel.prompt = "Download"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        store.downloadAttachment(attachment, saveTo: url)
    }
}
