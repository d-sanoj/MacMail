import SwiftUI

struct ContentView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(store: store)
            Divider()
            HSplitView {
                SidebarView(store: store)
                    .frame(
                        minWidth: store.isSidebarCollapsed ? 60 : 220,
                        idealWidth: store.isSidebarCollapsed ? 60 : 260,
                        maxWidth: store.isSidebarCollapsed ? 60 : 320,
                        maxHeight: .infinity
                    )
                    .animation(.default, value: store.isSidebarCollapsed)

                ThreadListView(store: store)
                    .frame(minWidth: 360, idealWidth: 440, maxHeight: .infinity)

                ReadingPaneView(store: store)
                    .frame(minWidth: 460, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if !store.hasAccounts {
                SetupEmptyStateView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $store.showingComposer) {
            ComposerView(store: store)
        }
        .sheet(isPresented: $store.showingSettings) {
            SettingsView(store: store)
        }

        .alert("GmailBox", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task(id: store.selectedAccountId) {
            guard store.selectedAccountId != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                await store.performBackgroundCheck()
            }
        }
    }
}

private struct SetupEmptyStateView: View {
    @ObservedObject var store: MailStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Connect GmailBox to your Gmail")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Import your Google OAuth desktop-client JSON in Settings, then sign in with Google. GmailBox never asks for your Gmail password.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
            }

            HStack {
                Button("Open Settings") {
                    store.showingSettings = true
                }
                .buttonStyle(.borderedProminent)

                Button("Sign in with Google") {
                    store.signInWithGoogle()
                }
                .disabled(!store.oauthSummary.isConfigured || store.isSigningIn)
            }

            if store.isSigningIn {
                ProgressView("Finish Google sign-in in your browser...")
                    .controlSize(.small)
            }

            if !store.oauthSummary.isConfigured {
                Text("OAuth JSON is not configured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }
}
