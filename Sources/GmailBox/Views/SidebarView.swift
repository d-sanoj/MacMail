import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: MailStore
    @AppStorage("sidebarMoreSectionExpanded") private var isMoreExpanded = true

    var body: some View {
        VStack(spacing: 12) {
            Button {
                store.showingComposer = true
            } label: {
                Label("Compose", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding([.horizontal, .top], 12)

            List(selection: Binding(
                get: { store.selectedMailbox },
                set: { selection in
                    if let selection {
                        store.selectMailbox(selection)
                    }
                }
            )) {
                Section("Mailboxes") {
                    sidebarRow("Inbox", icon: "tray", selection: .system(GmailSystemLabel.inbox))
                    sidebarRow("Starred", icon: "star", selection: .system(GmailSystemLabel.starred))
                    sidebarRow("Important", icon: "chevron.right.2", selection: .system(GmailSystemLabel.important))
                    sidebarRow("Sent", icon: "paperplane", selection: .system(GmailSystemLabel.sent))
                    sidebarRow("Purchases", icon: "bag", selection: .category(GmailCategoryLabel.purchases))

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            isMoreExpanded.toggle()
                        }
                    } label: {
                        Label(isMoreExpanded ? "Less" : "More", systemImage: isMoreExpanded ? "chevron.up" : "chevron.down")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if isMoreExpanded {
                        sidebarRow("Snoozed", icon: "clock", selection: .system(GmailSystemLabel.snoozed))
                        sidebarRow("Scheduled", icon: "paperplane.badge.clock", selection: .system(GmailSystemLabel.scheduled))
                        sidebarRow("Drafts", icon: "doc", selection: .system(GmailSystemLabel.drafts))
                        sidebarRow("All Mail", icon: "mail.stack", selection: .system(GmailSystemLabel.allMail))
                        sidebarRow("Spam", icon: "exclamationmark.octagon", selection: .system(GmailSystemLabel.spam), emphasizeUnread: true)
                        sidebarRow("Trash", icon: "trash", selection: .system(GmailSystemLabel.trash))
                        actionRow("Manage subscriptions", icon: "envelope.badge") {
                            store.errorMessage = "Manage subscriptions is a Gmail web setting. GmailBox can add a native subscriptions view once unsubscribe metadata is wired from message headers."
                        }
                        actionRow("Manage labels", icon: "gearshape") {
                            store.showingSettings = true
                        }
                        actionRow("Create new label", icon: "plus") {
                            store.errorMessage = "Creating Gmail labels will be added with the Gmail labels.create API."
                        }
                    }
                }

                if !store.customLabels.isEmpty {
                    Section {
                        ForEach(store.customLabels) { label in
                            Label {
                                HStack {
                                    Text(label.name)
                                    Spacer()
                                    if label.unreadCount > 0 {
                                        Text("\(label.unreadCount)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "tag")
                                    .foregroundStyle(Color(hex: label.colorHex) ?? .secondary)
                            }
                            .tag(MailboxSelection.label(label.id))
                        }
                    } header: {
                        HStack {
                            Text("Labels")
                            Spacer()
                            Button {
                                store.errorMessage = "Creating Gmail labels will be added with the Gmail labels.create API."
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func sidebarRow(_ title: String, icon: String, selection: MailboxSelection, emphasizeUnread: Bool = false) -> some View {
        let label = store.labels.first { $0.id == selection.gmailLabelId }
        return Label {
            HStack {
                Text(title)
                    .fontWeight(emphasizeUnread && (label?.unreadCount ?? 0) > 0 ? .semibold : .regular)
                Spacer()
                if let label, label.unreadCount > 0 {
                    Text("\(label.unreadCount)")
                        .foregroundStyle(.secondary)
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
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
