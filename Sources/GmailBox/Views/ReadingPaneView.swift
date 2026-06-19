import AppKit
import SwiftUI

struct ReadingPaneView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(spacing: 0) {
            if let thread = store.selectedThread {
                header(thread)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        subjectBlock(thread)
                        ForEach(store.selectedMessages) { message in
                            MessageCardView(message: message, store: store)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    private func header(_ thread: GmailThread) -> some View {
        HStack(spacing: 10) {
            Button {
                store.archiveSelectedThread()
            } label: {
                Image(systemName: "archivebox")
            }
            .help("Archive")

            Button {
                store.trashSelectedThread()
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete")

            Button {
                store.toggleUnreadSelectedThread()
            } label: {
                Image(systemName: thread.isUnread ? "envelope.open" : "envelope.badge")
            }
            .help(thread.isUnread ? "Mark as read" : "Mark as unread")

            Button {
                store.modifySelectedThreadForSpam()
            } label: {
                Image(systemName: "exclamationmark.octagon")
            }
            .help("Report spam")

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
                Image(systemName: "tag")
            }
            .help("Labels")

            Menu {
                Button("Load Full Thread") {
                    store.loadSelectedThreadFromAPI()
                }
                Button("Snooze") {
                    store.errorMessage = "Snooze is reserved for a follow-up implementation because Gmail's snooze behavior is not exposed as a simple public Gmail API thread action."
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("More")

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

            HStack(spacing: 6) {
                ForEach(store.labels.filter { thread.labelIds.contains($0.id) && $0.type != .system }) { label in
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

private struct MessageCardView: View {
    let message: GmailMessage
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.attachments.isEmpty {
                OutlookAttachmentStrip(attachments: message.attachments, store: store)
            }

            HStack(alignment: .top) {
                Circle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .overlay(Text(initials).font(.caption).fontWeight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.from)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
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

            if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
                HTMLMessageBodyView(html: htmlBody)
            } else {
                Text(message.plainTextBody ?? message.snippet)
                    .foregroundStyle(.black)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }

        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var initials: String {
        message.from.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.gray)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
                Text(attachment.isDownloaded ? "Downloaded" : ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Button {
                store.previewAttachment(attachment)
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
            .help("Preview")

            Button {
                saveAttachment()
            } label: {
                Image(systemName: attachment.isDownloaded ? "checkmark.circle" : "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .help(attachment.isDownloaded ? "Download again" : "Download")
        }
        .padding(8)
        .frame(width: 280, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
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
