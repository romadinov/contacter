import ContacterCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Auto-Merge", systemImage: "bolt.badge.checkmark") {
                AutoMergeSettingsView()
            }
        }
        .frame(width: 520)
    }
}

struct AutoMergeSettingsView: View {
    @Environment(ContactStore.self) private var store
    @State private var confirmEnable = false

    var body: some View {
        @Bindable var store = store
        let eligible = store.autoMergeEligible.count

        Form {
            Section {
                Toggle("Merge duplicates automatically", isOn: Binding(
                    get: { store.autoMergeEnabled },
                    set: { newValue in
                        // Turning it on acts immediately, so say how much it's about to do.
                        if newValue && eligible > 0 { confirmEnable = true } else { store.autoMergeEnabled = newValue }
                    }))
                Text("When contacts load or change, duplicates that meet the rules below are merged into their most complete contact. Everything else stays in Duplicates for you to review.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Rules") {
                Picker("Strictness", selection: $store.autoMergePolicy.strictness) {
                    ForEach(AutoMergePolicy.Strictness.allCases, id: \.self) { s in
                        Text("\(s.title) (score ≥ \(s.minimumScore))").tag(s)
                    }
                }
                Toggle("Require the same email, phone or social profile", isOn: $store.autoMergePolicy.requireSharedIdentifier)
                Stepper("Largest group to merge: \(store.autoMergePolicy.maxGroupSize)",
                        value: $store.autoMergePolicy.maxGroupSize, in: 2...10)
                Text("Every pair in a group must meet these rules on its own, and contacts with clearly different names are never merged automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Groups that qualify now", value: "\(eligible)")
                HStack {
                    Text("Every merge is backed up and can be undone from Merge History.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Merge \(eligible) Now") { Task { await store.runAutoMerge(automatic: false) } }
                        .disabled(eligible == 0 || store.isAutoMerging)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Turn on auto-merge?", isPresented: $confirmEnable) {
            Button("Turn On and Merge \(eligible) Groups") { store.autoMergeEnabled = true }
        } message: {
            Text("\(eligible) duplicate group(s) qualify and will be merged right away. You can undo any of them from Merge History.")
        }
    }
}
