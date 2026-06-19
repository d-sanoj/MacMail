import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: MailStore
    @AppStorage("sidebarMoreExpanded") private var isMoreExpanded = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                store.showingComposer = true
            } label: {
                if store.isSidebarCollapsed {
                    Image(systemName: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Compose", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding([.horizontal, .top], 12)

            List(selection: Binding<MailboxSelection?>(
                get: {
                    if case .category = store.selectedMailbox {
                        return .system(GmailSystemLabel.inbox)
                    }
                    return store.selectedMailbox
                },
                set: { selection in
                    if let selection {
                        // If they click Inbox while a category was selected, reset to Primary
                        if case .system(let id) = selection, id == GmailSystemLabel.inbox, case .category = store.selectedMailbox {
                            store.selectMailbox(.system(GmailSystemLabel.inbox))
                        } else {
                            store.selectMailbox(selection)
                        }
                    }
                }
            )) {
                Section(store.isSidebarCollapsed ? "" : "Mailboxes") {
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.inbox) { sidebarRow("Inbox", icon: "tray", selection: .system(GmailSystemLabel.inbox)) }
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.starred) { sidebarRow("Starred", icon: "star", selection: .system(GmailSystemLabel.starred)) }
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.important) { sidebarRow("Important", icon: "chevron.right.2", selection: .system(GmailSystemLabel.important)) }
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.sent) { sidebarRow("Sent", icon: "paperplane", selection: .system(GmailSystemLabel.sent)) }

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            isMoreExpanded.toggle()
                        }
                    } label: {
                        if store.isSidebarCollapsed {
                            Image(systemName: isMoreExpanded ? "chevron.up" : "chevron.down")
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Label(isMoreExpanded ? "Less" : "More", systemImage: isMoreExpanded ? "chevron.up" : "chevron.down")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if isMoreExpanded {
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.snoozed) { sidebarRow("Snoozed", icon: "clock", selection: .system(GmailSystemLabel.snoozed)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.scheduled) { sidebarRow("Scheduled", icon: "calendar.badge.clock", selection: .system(GmailSystemLabel.scheduled)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.drafts) { sidebarRow("Drafts", icon: "doc", selection: .system(GmailSystemLabel.drafts)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.allMail) { sidebarRow("All Mail", icon: "mail.stack", selection: .system(GmailSystemLabel.allMail)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.spam) { sidebarRow("Spam", icon: "exclamationmark.octagon", selection: .system(GmailSystemLabel.spam), emphasizeUnread: true) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.trash) { sidebarRow("Trash", icon: "trash", selection: .system(GmailSystemLabel.trash)) }
                    }
                }

                let visibleCustomLabels = store.customLabels.filter { !store.hiddenLabelIds.contains($0.id) }
                if !visibleCustomLabels.isEmpty {
                    Section {
                        ForEach(visibleCustomLabels) { label in
                            let labelSelection = MailboxSelection.label(label.id)
                            Label {
                                if !store.isSidebarCollapsed {
                                    HStack {
                                        Text(label.name)
                                        Spacer()
                                        let counts = store.count(for: labelSelection)
                                        if counts.total > 0 {
                                            Text("\(counts.unread)/\(counts.total)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } icon: {
                                Image(systemName: "tag")
                                    .foregroundStyle(Color(hex: label.colorHex) ?? .secondary)
                            }
                            .tag(labelSelection)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteLabel(label)
                                } label: {
                                    Label("Delete \"\(label.name)\"", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        if !store.isSidebarCollapsed {
                            Text("Labels")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func sidebarRow(_ title: String, icon: String, selection: MailboxSelection, emphasizeUnread: Bool = false) -> some View {
        let counts = store.count(for: selection)
        return Label {
            if !store.isSidebarCollapsed {
                HStack {
                    Text(title)
                        .fontWeight(emphasizeUnread && counts.unread > 0 ? .semibold : .regular)
                    Spacer()
                    if counts.total > 0 && selection.gmailLabelId != GmailSystemLabel.sent {
                        Text("\(counts.unread)/\(counts.total)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
        .tag(selection)
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if store.isSidebarCollapsed {
                Image(systemName: icon)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Label(title, systemImage: icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
