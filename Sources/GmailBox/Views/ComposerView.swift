import AppKit
import SwiftUI

struct ComposerView: View {
    @ObservedObject var store: MailStore
    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var subject = ""
    @State private var bodyText = NSAttributedString()
    @State private var attachments: [ComposeAttachment] = []
    @State private var showingLinkSheet = false
    @State private var linkText = ""
    @State private var linkURL = ""
    @AppStorage("DefaultSignature") private var signature = ""
    @State private var isShowingSignatureEditor = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var showSchedulePicker = false
    @State private var threadId: String?
    @State private var inReplyTo: String?
    @State private var references: String?

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            VStack(spacing: 0) {
                field("To", text: $to)
                field("Cc", text: $cc)
                field("Bcc", text: $bcc)
                field("Subject", text: $subject)

                RichTextEditor(attributedText: $bodyText)
                    .frame(minHeight: 230)
                    .background(Color.white)
                    .colorScheme(.light)
                    .padding(2)

                if !attachments.isEmpty {
                    AttachmentShelf(attachments: $attachments)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }

            Divider()

            VStack(spacing: 8) {
                formattingToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                actionToolbar
            }
            .padding(12)
        }
        .frame(width: 760, height: 620)
        .sheet(isPresented: $showingLinkSheet) {
            linkSheet
        }
        .sheet(isPresented: $isShowingSignatureEditor) {
            VStack(alignment: .leading) {
                Text("Edit Signature").font(.headline)
                TextEditor(text: $signature)
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.2))
                HStack {
                    Spacer()
                    Button("Done") { isShowingSignatureEditor = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 400)
        }
        .onAppear {
            setupComposeAction()
            if !signature.isEmpty {
                let attrSig = NSAttributedString(string: "\n\n--\n\(signature)")
                let mut = NSMutableAttributedString(attributedString: bodyText)
                mut.append(attrSig)
                bodyText = mut
            }
        }
    }

    private func setupComposeAction() {
        switch store.composeAction {
        case .new:
            break
        case .reply(let msg):
            to = msg.from
            subject = msg.subject.lowercased().hasPrefix("re:") ? msg.subject : "Re: \(msg.subject)"
            threadId = msg.threadId
            inReplyTo = msg.messageId
            references = msg.messageId
            setupQuotedBody(msg)
        case .replyAll(let msg):
            var allTo = msg.to
            if !allTo.contains(msg.from) { allTo.append(msg.from) }
            to = allTo.joined(separator: ", ")
            cc = msg.cc.joined(separator: ", ")
            subject = msg.subject.lowercased().hasPrefix("re:") ? msg.subject : "Re: \(msg.subject)"
            threadId = msg.threadId
            inReplyTo = msg.messageId
            references = msg.messageId
            setupQuotedBody(msg)
        case .forward(let msg):
            subject = msg.subject.lowercased().hasPrefix("fwd:") ? msg.subject : "Fwd: \(msg.subject)"
            threadId = msg.threadId
            setupQuotedBody(msg)
        }
    }

    private func setupQuotedBody(_ msg: GmailMessage) {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        
        let headerStr = "<br><br><div class=\"gmail_quote\" dir=\"auto\">On \(df.string(from: msg.date)), \(msg.from) wrote:<br>"
        let quotedHTML = "<blockquote>\(msg.htmlBody ?? msg.plainTextBody ?? "")</blockquote></div>"
        let finalHTML = headerStr + quotedHTML
        
        if let data = finalHTML.data(using: .utf8),
           let attrStr = try? NSMutableAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil) {
            
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
            
            self.bodyText = attrStr
        }
    }

    private func generateEmailPayload() -> (html: String, plainText: String, inlineImages: [(cid: String, data: Data, mimeType: String)]) {
        let mutableStr = NSMutableAttributedString(attributedString: bodyText)
        var inlineImages: [(cid: String, data: Data, mimeType: String)] = []
        
        var offset = 0
        bodyText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: bodyText.length), options: []) { value, range, stop in
            if let attachment = value as? NSTextAttachment,
               let image = attachment.image ?? (attachment.fileWrapper?.regularFileContents.flatMap { NSImage(data: $0) }) {
                let cid = UUID().uuidString
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) {
                    inlineImages.append((cid: cid, data: data, mimeType: "image/png"))
                    
                    let placeholder = NSAttributedString(string: "[[[CID:\(cid)]]]")
                    let adjustedRange = NSRange(location: range.location + offset, length: range.length)
                    mutableStr.replaceCharacters(in: adjustedRange, with: placeholder)
                    offset += placeholder.length - range.length
                }
            }
        }
        
        let plainText = mutableStr.string
        let htmlData = try? mutableStr.data(from: NSRange(location: 0, length: mutableStr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        var htmlString = htmlData.flatMap { String(data: $0, encoding: .utf8) } ?? plainText
        
        for img in inlineImages {
            htmlString = htmlString.replacingOccurrences(of: "[[[CID:\(img.cid)]]]", with: "<img src=\"cid:\(img.cid)\" />")
        }
        
        return (htmlString, plainText, inlineImages)
    }

    private var titleText: String {
        switch store.composeAction {
        case .new: return "New Message"
        case .reply: return "Reply"
        case .replyAll: return "Reply All"
        case .forward: return "Forward"
        }
    }

    private var titleBar: some View {
        HStack {
            Text(titleText)
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
            Button("B") { NSFontManager.shared.addFontTrait(TraitSender(tag: 2)) }
                .font(.system(size: 14, weight: .bold))
                .help("Bold (Cmd-B)")
                .focusable(false)
            Button("I") { NSFontManager.shared.addFontTrait(TraitSender(tag: 1)) }
                .font(.system(size: 14, weight: .medium).italic())
                .help("Italic (Cmd-I)")
                .focusable(false)
            Button("U") { NSApp.sendAction(#selector(NSTextView.underline(_:)), to: nil, from: nil) }
                .font(.system(size: 14, weight: .medium))
                .underline()
                .help("Underline (Cmd-U)")
                .focusable(false)
            
            Divider().frame(height: 22)

            Button("Font Panel") { NSFontManager.shared.orderFrontFontPanel(nil) }
                .help("Show Font Panel (Cmd-T)")
                .focusable(false)

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
            HStack(spacing: 0) {
                Button {
                    let payload = generateEmailPayload()
                    store.sendEmail(
                        to: to,
                        cc: cc,
                        bcc: bcc,
                        subject: subject,
                        plainText: payload.plainText,
                        htmlBody: payload.html,
                        attachments: attachments.map(\.url),
                        inlineImages: payload.inlineImages,
                        threadId: threadId,
                        inReplyTo: inReplyTo,
                        references: references
                    )
                } label: {
                    Text("Send")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send")
                
                Divider()
                    .frame(height: 26)
                    .background(Color.white.opacity(0.3))
                
                Menu {
                    Button("Schedule Send") { showSchedulePicker = true }
                } label: {
                    Image(systemName: "chevron.down")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .popover(isPresented: $showSchedulePicker) {
                    ScheduleSendView(customDate: $scheduleDate) { selectedDate in
                        let payload = generateEmailPayload()
                        store.scheduleEmail(
                            to: to, cc: cc, bcc: bcc, subject: subject,
                            plainText: payload.plainText, htmlBody: payload.html,
                            attachments: attachments.map(\.url), inlineImages: payload.inlineImages,
                            date: selectedDate,
                            threadId: threadId,
                            inReplyTo: inReplyTo,
                            references: references
                        )
                        showSchedulePicker = false
                        dismiss()
                    }
                }
            }
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

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

            toolbarButton("Signature Settings", icon: "signature") {
                isShowingSignatureEditor = true
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
                    if let url = URL(string: linkURL) {
                        let attrStr = NSMutableAttributedString(attributedString: bodyText)
                        let linkAttr = NSAttributedString(string: text, attributes: [.link: url])
                        attrStr.append(linkAttr)
                        bodyText = attrStr
                    }
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

private class TraitSender: NSObject {
    @objc var tag: Int
    init(tag: Int) { self.tag = tag }
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
