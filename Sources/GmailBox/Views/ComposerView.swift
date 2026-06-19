import AppKit
import SwiftUI

struct ComposerView: View {
    @ObservedObject var store: MailStore
    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var showFormatting = true
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var selectedFont = "Sans Serif"
    @State private var selectedSize = "Normal"
    @State private var attachments: [ComposeAttachment] = []
    @State private var showingLinkSheet = false
    @State private var linkText = ""
    @State private var linkURL = ""

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            VStack(spacing: 0) {
                field("To", text: $to)
                field("Cc", text: $cc)
                field("Bcc", text: $bcc)
                field("Subject", text: $subject)

                TextEditor(text: $bodyText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 230)

                if !attachments.isEmpty {
                    AttachmentShelf(attachments: $attachments)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }

            Divider()

            VStack(spacing: 8) {
                if showFormatting {
                    formattingToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                actionToolbar
            }
            .padding(12)
        }
        .frame(width: 760, height: 620)
        .sheet(isPresented: $showingLinkSheet) {
            linkSheet
        }
    }

    private var titleBar: some View {
        HStack {
            Text("New Message")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.bar)
    }

    private var formattingToolbar: some View {
        HStack(spacing: 6) {
            Picker("Font", selection: $selectedFont) {
                Text("Sans Serif").tag("Sans Serif")
                Text("Serif").tag("Serif")
                Text("Fixed Width").tag("Fixed Width")
            }
            .frame(width: 128)

            Divider().frame(height: 22)

            Picker("Size", selection: $selectedSize) {
                Text("Small").tag("Small")
                Text("Normal").tag("Normal")
                Text("Large").tag("Large")
                Text("Huge").tag("Huge")
            }
            .frame(width: 104)

            Divider().frame(height: 22)

            toggleFormat("Bold", icon: "bold", isOn: $isBold)
            toggleFormat("Italic", icon: "italic", isOn: $isItalic)
            toggleFormat("Underline", icon: "underline", isOn: $isUnderlined)

            Menu {
                Button("Black") {}
                Button("Gray") {}
                Button("Blue") {}
                Button("Red") {}
            } label: {
                Image(systemName: "textformat")
            }
            .help("Text color")

            Divider().frame(height: 22)

            Menu {
                Button("Align left") {}
                Button("Align center") {}
                Button("Align right") {}
            } label: {
                Image(systemName: "text.alignleft")
            }
            .help("Alignment")

            Button {} label: { Image(systemName: "list.number") }
                .help("Numbered list")
            Button {} label: { Image(systemName: "list.bullet") }
                .help("Bulleted list")
            Button {} label: { Image(systemName: "decrease.indent") }
                .help("Decrease indent")
            Button {} label: { Image(systemName: "increase.indent") }
                .help("Increase indent")

            Divider().frame(height: 22)

            Button {} label: { Image(systemName: "arrow.uturn.backward") }
                .help("Undo")
            Button {} label: { Image(systemName: "arrow.uturn.forward") }
                .help("Redo")
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.55), in: Capsule())
    }

    private var actionToolbar: some View {
        HStack(spacing: 10) {
            Button {
                store.sendPlainTextEmail(to: to, cc: cc, bcc: bcc, subject: subject, body: bodyText)
            } label: {
                HStack(spacing: 0) {
                    Text("Send")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 18)
                    Divider().frame(height: 26)
                    Image(systemName: "chevron.down")
                        .padding(.horizontal, 10)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .help("Send")
            .disabled(to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            toolbarButton("Formatting", icon: "textformat.size") {
                withAnimation(.snappy(duration: 0.18)) {
                    showFormatting.toggle()
                }
            }

            toolbarButton("Attach files", icon: "paperclip") {
                pickFiles(allowedImageOnly: false)
            }

            toolbarButton("Insert link", icon: "link") {
                showingLinkSheet = true
            }

            toolbarButton("Insert files using Drive", icon: "triangleshape") {
                store.errorMessage = "Drive insert needs Google Drive picker/API wiring. The compose control is now present and ready for that integration."
            }

            toolbarButton("Insert photo", icon: "photo") {
                pickFiles(allowedImageOnly: true)
            }

            toolbarButton("Confidential mode", icon: "lock.clock") {
                store.errorMessage = "Confidential mode is a Gmail server-side feature. The control is present; sending support needs Gmail-compatible confidential metadata."
            }

            toolbarButton("Insert signature", icon: "signature") {
                bodyText += bodyText.hasSuffix("\n") || bodyText.isEmpty ? "--\n" : "\n--\n"
            }

            Menu {
                Button("Schedule send") {
                    store.errorMessage = "Schedule send control is present. Gmail API send scheduling requires a local scheduler or server-side draft workflow."
                }
                Button("Print") {
                    store.errorMessage = "Print compose draft will be wired through NSPrintOperation."
                }
                Button("Check spelling") {
                    store.errorMessage = "macOS spelling is available in text controls; richer compose validation will be added with the HTML editor."
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .help("More options")

            Spacer()

            Button(role: .destructive) {
                dismiss()
            } label: {
                Image(systemName: "trash")
            }
            .help("Discard draft")
        }
        .buttonStyle(.plain)
        .controlSize(.large)
    }

    private var linkSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Insert Link")
                .font(.headline)
            TextField("Text to display", text: $linkText)
            TextField("Web address", text: $linkURL)
            HStack {
                Spacer()
                Button("Cancel") {
                    showingLinkSheet = false
                }
                Button("Insert") {
                    let text = linkText.isEmpty ? linkURL : linkText
                    bodyText += "[\(text)](\(linkURL))"
                    showingLinkSheet = false
                    linkText = ""
                    linkURL = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(linkURL.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            TextField(title, text: text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func toggleFormat(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: icon)
                .padding(5)
                .background((isOn.wrappedValue ? Color.secondary.opacity(0.18) : Color.clear), in: RoundedRectangle(cornerRadius: 5))
        }
        .help(title)
    }

    private func toolbarButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .help(title)
    }

    private func pickFiles(allowedImageOnly: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if allowedImageOnly {
            panel.allowedContentTypes = [.image]
        }

        if panel.runModal() == .OK {
            let newAttachments = panel.urls.map {
                ComposeAttachment(url: $0, isInlineImage: allowedImageOnly)
            }
            attachments.append(contentsOf: newAttachments)
        }
    }
}

private struct ComposeAttachment: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isInlineImage: Bool

    var filename: String {
        url.lastPathComponent
    }

    var sizeText: String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

private struct AttachmentShelf: View {
    @Binding var attachments: [ComposeAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                HStack(spacing: 10) {
                    Image(systemName: attachment.isInlineImage ? "photo" : "paperclip")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .lineLimit(1)
                        Text(attachment.isInlineImage ? "Inline image - \(attachment.sizeText)" : attachment.sizeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove attachment")
                }
                .padding(8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
