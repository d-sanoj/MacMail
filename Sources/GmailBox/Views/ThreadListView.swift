import SwiftUI

struct ThreadListView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("", isOn: .constant(false))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Text("\(store.filteredThreads.count) threads")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            CategoryTabsView(store: store)

            Divider()

            if store.filteredThreads.isEmpty {
                ContentUnavailableView(
                    "No mail here",
                    systemImage: "tray",
                    description: Text("Try another label or search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { store.selectedThreadId },
                    set: { id in
                        guard let id, let thread = store.filteredThreads.first(where: { $0.id == id }) else { return }
                        store.selectThread(thread)
                    }
                )) {
                    ForEach(store.filteredThreads) { thread in
                        ThreadRowView(
                            thread: thread,
                            labels: store.labels.filter { thread.labelIds.contains($0.id) && $0.type == .user },
                            toggleStar: { store.toggleStar(thread) }
                        )
                        .tag(thread.id)
                        .contextMenu {
                            Button("Archive") { store.archiveSelectedThread() }
                            Button(thread.isUnread ? "Mark as Read" : "Mark as Unread") { store.toggleUnreadSelectedThread() }
                            Button("Trash", role: .destructive) { store.trashSelectedThread() }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CategoryTabsView: View {
    @ObservedObject var store: MailStore

    private let tabs: [(title: String, icon: String, selection: MailboxSelection)] = [
        ("Primary", "tray.fill", .category(GmailCategoryLabel.primary)),
        ("Promotions", "tag", .category(GmailCategoryLabel.promotions)),
        ("Social", "person.2", .category(GmailCategoryLabel.social)),
        ("Updates", "info.circle", .category(GmailCategoryLabel.updates))
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.title) { tab in
                Button {
                    store.selectMailbox(tab.selection)
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                            Text(tab.title)
                                .fontWeight(isSelected(tab.selection) ? .semibold : .medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(isSelected(tab.selection) ? .blue : .secondary)

                        Rectangle()
                            .fill(isSelected(tab.selection) ? Color.blue : Color.clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(.bar)
    }

    private func isSelected(_ selection: MailboxSelection) -> Bool {
        store.selectedMailbox == selection
    }
}

private struct ThreadRowView: View {
    let thread: GmailThread
    let labels: [GmailLabel]
    let toggleStar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: .constant(false))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

            Button(action: toggleStar) {
                Image(systemName: thread.isStarred ? "star.fill" : "star")
                    .foregroundStyle(thread.isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(thread.senderDisplay)
                        .fontWeight(thread.isUnread ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    if thread.hasAttachments {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                    }
                    Text(thread.lastMessageDate.mailboxTimestamp)
                        .font(.caption)
                        .foregroundStyle(thread.isUnread ? .primary : .secondary)
                }

                Text(thread.subject)
                    .font(.subheadline)
                    .fontWeight(thread.isUnread ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !thread.snippet.isEmpty {
                    Text(thread.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(labels) { label in
                            Text(label.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((Color(hex: label.colorHex) ?? .secondary).opacity(0.18), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
