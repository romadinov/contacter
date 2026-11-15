import ContacterCore
import SwiftUI

enum SidebarSection: Hashable {
    case all, duplicates, history
}

/// Window navigation state. Shared with menu commands through `focusedSceneValue`.
@MainActor
@Observable
final class Navigator {
    var section: SidebarSection? = .all
    var selectedContactID: String?
    var selectedGroupID: String?
    var selectedRecordID: UUID?
    var isCreating = false

    func newContact() { isCreating = true }

    func showDuplicates(group: String? = nil) {
        section = .duplicates
        if let group { selectedGroupID = group }
    }
}

struct RootView: View {
    @Environment(ContactStore.self) private var store
    @State private var navigator = Navigator()

    var body: some View {
        Group {
            if store.access == .granted {
                splitView
            } else {
                AccessView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.errorMessage != nil },
                                                            set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .focusedSceneValue(navigator)
    }

    private var splitView: some View {
        @Bindable var navigator = navigator
        return NavigationSplitView {
            List(selection: $navigator.section) {
                Label("All Contacts", systemImage: "person.2")
                    .badge(store.cards.count)
                    .tag(SidebarSection.all)
                Label("Duplicates", systemImage: "person.2.badge.gearshape")
                    .badge(store.duplicateGroups.count)
                    .tag(SidebarSection.duplicates)
                Label("Merge History", systemImage: "clock.arrow.circlepath")
                    .badge(store.unseenAutoMerges)
                    .tag(SidebarSection.history)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            Group {
                switch navigator.section ?? .all {
                case .all: QuickEntryView(selection: $navigator.selectedContactID)
                case .duplicates: DuplicateListView(selection: $navigator.selectedGroupID)
                case .history: MergeHistoryView(selection: $navigator.selectedRecordID)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            .toolbar {
                if navigator.section == .all {
                    Button("New Contact", systemImage: "plus") { navigator.newContact() }
                }
            }
        } detail: {
            switch navigator.section ?? .all {
            case .all:
                if let id = navigator.selectedContactID {
                    ContactDetailView(contactID: id) { groupID in
                        navigator.showDuplicates(group: groupID)
                    }
                } else {
                    ContentUnavailableView("No Contact Selected", systemImage: "person.crop.circle",
                                           description: Text("Type a name to search, or a whole line like “Jane Doe jane@acme.com 555 123 4567” to add someone."))
                }
            case .duplicates:
                if let group = store.duplicateGroups.first(where: { $0.id == navigator.selectedGroupID }) {
                    DuplicateGroupView(group: group).id(group.id)
                } else {
                    ContentUnavailableView("Review Duplicates", systemImage: "person.2.badge.gearshape",
                                           description: Text("Select a group to compare and merge."))
                }
            case .history:
                if let record = store.history.first(where: { $0.id == navigator.selectedRecordID }) {
                    MergeRecordDetail(record: record).id(record.id)
                } else {
                    ContentUnavailableView("Merge History", systemImage: "clock.arrow.circlepath",
                                           description: Text("Select a merge to see what was combined, or to undo it."))
                }
            }
        }
        .navigationTitle("Contacter")
        .sheet(isPresented: $navigator.isCreating) {
            ContactEditorView(original: ContactCard()) { id in
                navigator.section = .all
                navigator.selectedContactID = id
            }
        }
    }
}

struct AccessView: View {
    @Environment(ContactStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Contacts Access", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text(store.access == .denied
                 ? "Contacter can't see your contacts. Allow access in System Settings › Privacy & Security › Contacts."
                 : "Contacter works with the contacts already on your Mac — iCloud, Google, Exchange and local accounts.")
        } actions: {
            if store.access == .denied {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!)
                }
            } else {
                Button("Allow Access") { Task { await store.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// The menu bar panel: quick entry, and a contact's details when you pick one.
struct QuickEntryPanel: View {
    @Environment(ContactStore.self) private var store
    @State private var selection: String?

    var body: some View {
        Group {
            if store.access != .granted {
                AccessView()
            } else if let id = selection {
                VStack(alignment: .leading, spacing: 0) {
                    Button("Back", systemImage: "chevron.left") { selection = nil }
                        .buttonStyle(.borderless)
                        .padding(10)
                    Divider()
                    ContactDetailView(contactID: id)
                }
            } else {
                QuickEntryView(selection: $selection, compact: true)
            }
        }
        .frame(width: 420, height: 520)
    }
}
