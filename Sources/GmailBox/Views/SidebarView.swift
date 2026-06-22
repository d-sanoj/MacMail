import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: MailStore
    @AppStorage("sidebarMoreExpanded") private var isMoreExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                store.openComposer()
            } label: {
                ZStack(alignment: .leading) {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .frame(width: store.isSidebarCollapsed ? 40 : 20, alignment: .center)
                    Text("Compose")
                        .padding(.leading, 32)
                        .opacity(store.isSidebarCollapsed ? 0 : 1)
                        .frame(width: store.isSidebarCollapsed ? 0 : nil, alignment: .leading)
                        .clipped()
                }
                .padding(.horizontal, store.isSidebarCollapsed ? 0 : 8)
                .frame(height: 36)
                .frame(maxWidth: store.isSidebarCollapsed ? 40 : .infinity, alignment: store.isSidebarCollapsed ? .center : .leading)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: store.isSidebarCollapsed ? 18 : 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, store.isSidebarCollapsed ? 10 : 12)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 4) {
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.inbox) { sidebarRow("Inbox", icon: "tray", selection: .system(GmailSystemLabel.inbox)) }
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.starred) { sidebarRow("Starred", icon: "star", selection: .system(GmailSystemLabel.starred)) }
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.important) { sidebarRow("Important", icon: "chevron.right.2", selection: .system(GmailSystemLabel.important)) }
                    if !store.hiddenLabelIds.contains(GmailSystemLabel.sent) { sidebarRow("Sent", icon: "paperplane", selection: .system(GmailSystemLabel.sent)) }

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            isMoreExpanded.toggle()
                        }
                    } label: {
                        ZStack(alignment: .leading) {
                            Image(systemName: isMoreExpanded ? "chevron.up" : "chevron.down")
                                .frame(width: store.isSidebarCollapsed ? 40 : 20, alignment: .center)
                            Text(isMoreExpanded ? "Less" : "More")
                                .padding(.leading, 32)
                                .opacity(store.isSidebarCollapsed ? 0 : 1)
                                .frame(width: store.isSidebarCollapsed ? 0 : nil, alignment: .leading)
                                .clipped()
                        }
                        .padding(.horizontal, store.isSidebarCollapsed ? 0 : 8)
                        .frame(height: 36)
                        .frame(maxWidth: store.isSidebarCollapsed ? 40 : .infinity, alignment: store.isSidebarCollapsed ? .center : .leading)
                        .contentShape(Rectangle())
                        .modifier(SidebarHoverBackground(isSelected: false))
                        .clipShape(RoundedRectangle(cornerRadius: store.isSidebarCollapsed ? 18 : 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, store.isSidebarCollapsed ? 10 : 12)

                    if isMoreExpanded {
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.snoozed) { sidebarRow("Snoozed", icon: "clock", selection: .system(GmailSystemLabel.snoozed)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.scheduled) { sidebarRow("Scheduled", icon: "calendar.badge.clock", selection: .system(GmailSystemLabel.scheduled)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.drafts) { sidebarRow("Drafts", icon: "doc", selection: .system(GmailSystemLabel.drafts)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.allMail) { sidebarRow("All Mail", icon: "mail.stack", selection: .system(GmailSystemLabel.allMail)) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.spam) { sidebarRow("Spam", icon: "exclamationmark.octagon", selection: .system(GmailSystemLabel.spam), emphasizeUnread: true) }
                        if !store.hiddenLabelIds.contains(GmailSystemLabel.trash) { sidebarRow("Trash", icon: "trash", selection: .system(GmailSystemLabel.trash)) }
                    }

                    let visibleCustomLabels = store.customLabels.filter { !store.hiddenLabelIds.contains($0.id) }
                    if !visibleCustomLabels.isEmpty {
                        Divider().padding(.vertical, 8)
                        ForEach(visibleCustomLabels) { label in
                            let labelSelection = MailboxSelection.label(label.id)
                            let isSelected = store.selectedMailbox == labelSelection
                            let counts = store.count(for: labelSelection)
                            
                            Button {
                                store.selectMailbox(labelSelection)
                            } label: {
                                ZStack(alignment: .leading) {
                                    Image(systemName: "tag")
                                        .foregroundStyle(isSelected ? .white : (Color(hex: label.colorHex) ?? .secondary))
                                        .frame(width: store.isSidebarCollapsed ? 40 : 20, alignment: .center)
                                    
                                    HStack {
                                        Text(label.name)
                                        Spacer()
                                        if counts.total > 0 {
                                            Text("\(counts.unread)/\(counts.total)")
                                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                                        }
                                    }
                                    .padding(.leading, 32)
                                    .opacity(store.isSidebarCollapsed ? 0 : 1)
                                    .frame(width: store.isSidebarCollapsed ? 0 : nil, alignment: .leading)
                                    .clipped()
                                }
                                .padding(.horizontal, store.isSidebarCollapsed ? 0 : 8)
                                .frame(height: 36)
                                .frame(maxWidth: store.isSidebarCollapsed ? 40 : .infinity, alignment: store.isSidebarCollapsed ? .center : .leading)
                                .contentShape(Rectangle())
                                .modifier(SidebarHoverBackground(isSelected: isSelected))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: store.isSidebarCollapsed ? 18 : 8))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, store.isSidebarCollapsed ? 10 : 12)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteLabel(label)
                                } label: {
                                    Label("Delete \"\(label.name)\"", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sidebarRow(_ title: String, icon: String, selection: MailboxSelection, emphasizeUnread: Bool = false) -> some View {
        let isSelected = {
            if case .category = store.selectedMailbox, case .system(let id) = selection, id == GmailSystemLabel.inbox {
                return true
            }
            return store.selectedMailbox == selection
        }()
        let counts = store.count(for: selection)
        
        return Button {
            store.selectMailbox(selection)
        } label: {
            ZStack(alignment: .leading) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: store.isSidebarCollapsed ? 40 : 20, alignment: .center)

                HStack {
                    Text(title)
                        .fontWeight(emphasizeUnread && counts.unread > 0 ? .semibold : .regular)
                    Spacer()
                    if counts.total > 0 && selection.gmailLabelId != GmailSystemLabel.sent {
                        Text("\(counts.unread)/\(counts.total)")
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                .padding(.leading, 32)
                .opacity(store.isSidebarCollapsed ? 0 : 1)
                .frame(width: store.isSidebarCollapsed ? 0 : nil, alignment: .leading)
                .clipped()
            }
            .padding(.horizontal, store.isSidebarCollapsed ? 0 : 8)
            .frame(height: 36)
            .frame(maxWidth: store.isSidebarCollapsed ? 40 : .infinity, alignment: store.isSidebarCollapsed ? .center : .leading)
            .contentShape(Rectangle())
            .modifier(SidebarHoverBackground(isSelected: isSelected))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: store.isSidebarCollapsed ? 18 : 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, store.isSidebarCollapsed ? 10 : 12)
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

private struct SidebarHoverBackground: ViewModifier {
    let isSelected: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(isSelected ? Color.accentColor : (isHovering ? Color.secondary.opacity(0.15) : Color.clear))
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
