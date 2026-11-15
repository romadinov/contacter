import SwiftUI

@main
struct ContacterApp: App {
    @State private var store = ContactStore()

    var body: some Scene {
        Window("Contacter", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 500)
        }
        .commands { ContacterCommands(store: store) }

        MenuBarExtra("Contacter", systemImage: "person.crop.circle") {
            QuickEntryPanel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

struct ContacterCommands: Commands {
    let store: ContactStore
    @FocusedValue(Navigator.self) private var navigator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Contact") { navigator?.newContact() }
                .keyboardShortcut("n")
                .disabled(navigator == nil)
        }
        CommandMenu("Contacts") {
            Button("Show Duplicates") { navigator?.showDuplicates() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(navigator == nil)
            Button("Rescan for Duplicates") { Task { await store.scanForDuplicates() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Auto-Merge Now") { Task { await store.runAutoMerge(automatic: false) } }
                .disabled(store.autoMergeEligible.isEmpty)
            Button("Forget “Not Duplicates” Decisions") { Task { await store.resetIgnoredPairs() } }
            Divider()
            Button("Show Backups in Finder") {
                try? FileManager.default.createDirectory(at: store.backupsDirectory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(store.backupsDirectory)
            }
            Button("Reload Contacts") { Task { await store.reload() } }
                .keyboardShortcut("r")
        }
    }
}
