import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: MailStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateLabel = false
    @State private var newLabelName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close Settings")
            }
            .padding(14)
            .background(.bar)

            Form {
            Section("General Settings") {
                Toggle("Show labels on messages", isOn: $store.showLabelsOnMessages)
            }

            Section("Labels") {
                Button("Create New Label") {
                    showingCreateLabel = true
                }
            }
                
            let displayableSystemLabelIds: [String] = [
                GmailSystemLabel.inbox, GmailSystemLabel.starred, GmailSystemLabel.important,
                GmailSystemLabel.sent, GmailSystemLabel.snoozed, GmailSystemLabel.scheduled,
                GmailSystemLabel.drafts, GmailSystemLabel.allMail, GmailSystemLabel.spam, GmailSystemLabel.trash
            ]
            let visibleSystemLabels = store.systemLabels
                .filter { displayableSystemLabelIds.contains($0.id) }
                .sorted {
                    let idx1 = displayableSystemLabelIds.firstIndex(of: $0.id) ?? 0
                    let idx2 = displayableSystemLabelIds.firstIndex(of: $1.id) ?? 0
                    return idx1 < idx2
                }
            
            if !visibleSystemLabels.isEmpty {
                Section("System Labels") {
                    ForEach(visibleSystemLabels) { label in
                        Toggle(label.name.capitalized, isOn: Binding(
                            get: { !store.hiddenLabelIds.contains(label.id) },
                            set: { isVisible in
                                var hidden = store.hiddenLabelIds
                                if isVisible {
                                    hidden.remove(label.id)
                                } else {
                                    hidden.insert(label.id)
                                }
                                store.hiddenLabelIds = hidden
                            }
                        ))
                    }
                }
            }

            if !store.customLabels.isEmpty {
                Section("Custom Labels") {
                    ForEach(store.customLabels) { label in
                        Toggle(label.name, isOn: Binding(
                            get: { !store.hiddenLabelIds.contains(label.id) },
                            set: { isVisible in
                                var hidden = store.hiddenLabelIds
                                if isVisible {
                                    hidden.remove(label.id)
                                } else {
                                    hidden.insert(label.id)
                                }
                                store.hiddenLabelIds = hidden
                            }
                        ))
                    }
                }
            }
            
            Section("Reading Pane Toolbar") {
                Toggle("Show Text on Buttons", isOn: $store.showToolbarText)
                Divider()
                Toggle("Archive", isOn: Binding(
                    get: { !store.hiddenToolbarButtons.contains("archive") },
                    set: { isVisible in store.toggleToolbarButton("archive", isVisible: isVisible) }
                ))
                Toggle("Delete", isOn: Binding(
                    get: { !store.hiddenToolbarButtons.contains("delete") },
                    set: { isVisible in store.toggleToolbarButton("delete", isVisible: isVisible) }
                ))
                Toggle("Mark Unread", isOn: Binding(
                    get: { !store.hiddenToolbarButtons.contains("unread") },
                    set: { isVisible in store.toggleToolbarButton("unread", isVisible: isVisible) }
                ))
                Toggle("Report Spam", isOn: Binding(
                    get: { !store.hiddenToolbarButtons.contains("spam") },
                    set: { isVisible in store.toggleToolbarButton("spam", isVisible: isVisible) }
                ))
                Toggle("Labels", isOn: Binding(
                    get: { !store.hiddenToolbarButtons.contains("labels") },
                    set: { isVisible in store.toggleToolbarButton("labels", isVisible: isVisible) }
                ))
                Toggle("More Options", isOn: Binding(
                    get: { !store.hiddenToolbarButtons.contains("more") },
                    set: { isVisible in store.toggleToolbarButton("more", isVisible: isVisible) }
                ))
            }

            Section("Google API Setup") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.oauthSummary.isConfigured ? "OAuth client configured" : "OAuth client not configured")
                            .fontWeight(.semibold)
                        Text(store.oauthSummary.clientIdPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.oauthSummary.sourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: store.oauthSummary.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.oauthSummary.isConfigured ? .green : .orange)
                }

                Text("Import the Desktop app OAuth JSON downloaded from Google Cloud Console. GmailBox stores the JSON and OAuth tokens locally in Application Support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Import OAuth JSON") {
                        importOAuthJSON()
                    }
                    Button("Reveal Stored File") {
                        revealStoredOAuthJSON()
                    }
                    .disabled(!FileManager.default.fileExists(atPath: GoogleOAuthClientStore.userConfigURL.path))

                    Button("Remove Imported JSON", role: .destructive) {
                        removeOAuthJSON()
                    }
                    .disabled(!FileManager.default.fileExists(atPath: GoogleOAuthClientStore.userConfigURL.path))
                }
            }

            Section("Accounts") {
                ForEach(store.accounts) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.displayName)
                            Text(account.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if account.id == store.selectedAccountId {
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button("Sign in with Google") {
                        store.signInWithGoogle()
                    }
                    .disabled(!store.oauthSummary.isConfigured || store.isSigningIn)

                    if store.isSigningIn {
                        ProgressView("Waiting for browser consent...")
                            .controlSize(.small)
                    }

                    Button("Remove Selected Account", role: .destructive) {
                        store.removeSelectedAccount()
                    }
                    .disabled(store.selectedAccountId == nil)
                }
            }

            Section("Privacy") {
                Text("Gmail passwords are never entered in GmailBox. OAuth tokens are stored locally in Application Support. Attachments are not downloaded until an explicit download flow is enabled.")
                    .foregroundStyle(.secondary)
            }

            Section("Login Troubleshooting") {
                Text("Error 403: access_denied means Google blocked the account before GmailBox received a token. In Google Cloud Console, open your OAuth consent screen and add this Gmail address under Test users. For personal use, add all Gmail accounts you want to connect.")
                    .foregroundStyle(.secondary)
                Text("After you click Continue on Google's access screen, the browser should briefly open a callback page like 127.0.0.1:49152 that says sign-in is complete. If it spins for more than a few minutes, relaunch GmailBox and try again.")
                    .foregroundStyle(.secondary)
            }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 620, height: 560)
        .alert("New Label", isPresented: $showingCreateLabel) {
            TextField("Label Name", text: $newLabelName)
            Button("Create") {
                let trimmed = newLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    store.createLabel(name: trimmed)
                }
                newLabelName = ""
            }
            Button("Cancel", role: .cancel) {
                newLabelName = ""
            }
        }
    }

    private func importOAuthJSON() {
        let panel = NSOpenPanel()
        panel.title = "Choose Google OAuth Client JSON"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            _ = try GoogleOAuthClientStore.importConfig(from: url)
            store.refreshOAuthSummary()
            store.errorMessage = "OAuth client JSON imported. You can now sign in with Google."
        } catch {
            store.refreshOAuthSummary()
            store.errorMessage = "That file does not look like a valid Google Desktop OAuth client JSON. Download an OAuth client ID with Application type: Desktop app."
        }
    }

    private func revealStoredOAuthJSON() {
        NSWorkspace.shared.activateFileViewerSelecting([GoogleOAuthClientStore.userConfigURL])
    }

    private func removeOAuthJSON() {
        do {
            try GoogleOAuthClientStore.removeImportedConfig()
            store.refreshOAuthSummary()
            store.errorMessage = "Imported OAuth JSON removed."
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
