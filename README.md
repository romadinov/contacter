# Contacter

A Cardhop-style contact manager for macOS with built-in duplicate detection and merging.
It works on the system Contacts database, so iCloud, Google, Exchange and local accounts all show up.

## Build & run

```sh
xcodegen generate
xcodebuild -project Contacter.xcodeproj -scheme Contacter -derivedDataPath build build
open build/Build/Products/Debug/Contacter.app
```

Release (Developer ID sign, notarize, staple, GitHub release): `scripts/release.sh`
(`PUBLISH=0` to stop before tagging; `NOTARY_PROFILE` picks the notarytool keychain profile, default `tasker-notary`).
Icon: edit `scripts/make-icon.swift`, then `scripts/make-appiconset.sh`.

Core logic tests (no Contacts permission needed):

```sh
cd Packages/ContacterCore && swift test
```

## Features

- **One-line entry** (main window and menu bar): type `Jane Doe, CEO at Acme Inc jane@acme.com work 415 555 0100 @janed bday Apr 12`
  and it is parsed into a contact. A plain name just searches.
- **Actions**: `call Jane`, `email Jane`, `text Jane`, `facetime Jane`, `map Jane` — press ⏎.
- **Duplicate detection** (`Packages/ContacterCore/Sources/ContacterCore/DuplicateFinder.swift`):
  - signals: normalized email (case, `+tags`, Gmail dots), phone (last 9 digits, so `+61 4…` == `04…`),
    social handle, name (exact, swapped order, nickname like Bob/Robert, initial like J./John, typos),
    company (ignoring Inc/LLC/…), birthday.
  - guards against false positives: different first *and* last names (households sharing a landline,
    shared `info@` mailboxes) and different birthdays reduce the score.
  - blocking index keeps it near-linear (5,000 contacts scan in about 2 seconds in a debug build).
  - groups are clustered transitively and rated High / Medium / Possible.
- **Dedup on entry**: creating a contact that resembles an existing one offers "Add to …" instead.
- **Merge**: choose the contact to keep and see a preview of the merged result. Multi-value fields are combined with duplicates removed,
  empty fields get filled in, and abbreviations get expanded (`J` → `John`).
- **Auto-merge** (Settings › Auto-Merge, off by default): merges duplicate groups that meet stricter rules, either
  automatically whenever contacts load or change, or on demand (⚡ Auto-Merge in Duplicates). The rules:
  - Every *pair* in the group must qualify on its own (so a chain where A matches B and B matches C isn't enough).
  - Each pair must share an email, phone or social profile; a matching name alone never qualifies.
  - The score must reach the threshold: Strict ≥ 90 (default) or Standard ≥ 80.
  - Clearly different names never qualify, and groups larger than the limit (3 by default) are left for review.

  Each group's detail view says whether it qualifies and, if not, which rule blocked it
  (`Packages/ContacterCore/Sources/ContacterCore/AutoMergePolicy.swift`).
- **Merge History with Undo**: every merge, manual or automatic, is logged. Undo replaces the merged contact with the
  originals from the pre-merge backup and marks them "not duplicates" so they won't be merged again.
- **Not Duplicates** decisions are remembered (Contacts › Forget "Not Duplicates" Decisions to reset).
- **Backups**: every merge and delete first writes the affected contacts to a `.vcf` in
  `~/Library/Application Support/Contacter/Backups` (Contacts › Show Backups in Finder). Double-click it to restore.

## Layout

- `Packages/ContacterCore`: framework-free model, normalization, parser, duplicate finder and merger, plus tests.
- `App/Model`: `CNContact` mapping, `ContactsGateway` (all CNContactStore I/O), `ContactStore` (@Observable state).
- `App/Views`: SwiftUI views.
