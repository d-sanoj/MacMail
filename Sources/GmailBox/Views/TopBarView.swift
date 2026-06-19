import SwiftUI

struct TopBarView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        HStack(spacing: 12) {
            Text("GmailBox")
                .font(.headline)
                .frame(width: 180, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search mail", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await store.refresh() }
                    }
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 680)

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: store.isSyncing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(store.isSyncing)

            Button {
                Task { await store.syncAllOldMessages() }
            } label: {
                Label("Sync all", systemImage: "tray.and.arrow.down")
            }
            .help("Sync all old messages for the selected account")
            .disabled(store.isSyncing)

            Picker("Account", selection: Binding(
                get: { store.selectedAccountId ?? "" },
                set: { store.switchAccount(to: $0) }
            )) {
                ForEach(store.accounts) { account in
                    Text(account.email).tag(account.id)
                }
            }
            .frame(width: 220)

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
