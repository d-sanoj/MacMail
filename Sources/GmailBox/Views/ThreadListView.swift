import SwiftUI

struct ThreadListView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(spacing: 0) {

            if isInboxOrCategory {
                Divider()
                CategoryTabsView(store: store)
            }

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
                    ForEach(groupedThreads, id: \.0) { section, threads in
                        Section(header: Text(section.rawValue).font(.subheadline.bold()).foregroundStyle(.secondary).padding(.vertical, 4)) {
                            ForEach(threads) { thread in
                                ThreadRowView(
                                    thread: thread,
                                    labels: store.labels.filter { thread.labelIds.contains($0.id) && $0.type == .user },
                                    trashAction: { store.trashThread(thread) }
                                )
                                .tag(thread.id)
                                .contextMenu {
                                    Button("Archive") { store.archiveSelectedThread() }
                                    Button(thread.isUnread ? "Mark as Read" : "Mark as Unread") { store.toggleUnreadSelectedThread() }
                                    Button("Trash", role: .destructive) { store.trashSelectedThread() }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isInboxOrCategory: Bool {
        switch store.selectedMailbox {
        case .system(let id) where id == GmailSystemLabel.inbox:
            return true
        case .category:
            return true
        default:
            return false
        }
    }

    private var groupedThreads: [(TimeSection, [GmailThread])] {
        var groups: [TimeSection: [GmailThread]] = [:]
        for thread in store.filteredThreads {
            let section = thread.lastMessageDate.timeSection
            groups[section, default: []].append(thread)
        }
        return TimeSection.allCases.compactMap { section in
            guard let threads = groups[section], !threads.isEmpty else { return nil }
            return (section, threads)
        }
    }
}

private struct CategoryTabsView: View {
    @ObservedObject var store: MailStore

    private let tabs: [(title: String, icon: String, selection: MailboxSelection)] = [
        ("Primary", "tray.fill", .category(GmailCategoryLabel.primary)),
        ("Promotions", "tag", .category(GmailCategoryLabel.promotions)),
        ("Social", "person.2", .category(GmailCategoryLabel.social))
    ]

    var body: some View {
        HStack {
            Menu {
                ForEach(tabs, id: \.title) { tab in
                    Button {
                        store.selectMailbox(tab.selection)
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
            } label: {
                let current = tabs.first(where: { $0.selection == store.selectedMailbox }) ?? tabs[0]
                HStack(spacing: 6) {
                    Image(systemName: current.icon)
                    Text(current.title)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct ThreadRowView: View {
    let thread: GmailThread
    let labels: [GmailLabel]
    let trashAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(thread.senderDisplay)
                        .fontWeight(thread.isUnread ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    if isHovering {
                        Button(action: trashAction) {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .help("Delete")
                    } else if thread.hasAttachments {
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
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
