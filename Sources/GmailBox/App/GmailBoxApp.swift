import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct GmailBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MailStore()

    var body: some Scene {
        WindowGroup("GmailBox") {
            ContentView(store: store)
                .frame(minWidth: 1100, minHeight: 720)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    store.load()
                }
        }
        .commands {
            CommandMenu("Mailbox") {
                Button("Refresh") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Compose") {
                    store.showingComposer = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("Archive") {
                    store.archiveSelectedThread()
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Mark Read/Unread") {
                    store.toggleUnreadSelectedThread()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
