import SwiftUI

struct TopBarView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation {
                    store.isSidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Toggle Sidebar")

            Spacer()

            if store.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    if store.syncProgressTotal > 0 {
                        let percent = min(100, Int((Double(store.syncProgressCount) / Double(store.syncProgressTotal)) * 100))
                        Text(store.syncProgressCount > 0 ? "Downloading \(percent)%" : "Syncing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.default, value: percent)
                    } else {
                        Text(store.syncProgressCount > 0 ? "Downloading \(store.syncProgressCount)" : "Syncing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.default, value: store.syncProgressCount)
                    }
                }
                .padding(.trailing, 8)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Button {
                    Task { await store.syncAllOldMessages() }
                } label: {
                    Label("Sync all", systemImage: "tray.and.arrow.down")
                }
                .help("Sync all old messages for the selected account")
            }

            Picker("Account", selection: Binding(
                get: { store.selectedAccountId ?? "" },
                set: { id in
                    if id == "ADD_ACCOUNT" {
                        store.signInWithGoogle()
                    } else {
                        store.switchAccount(to: id)
                    }
                }
            )) {
                ForEach(store.accounts) { account in
                    Text(account.email).tag(account.id)
                }
                Divider()
                Text("Add Account...").tag("ADD_ACCOUNT")
            }
            .frame(width: 320)

            Button {
                store.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
