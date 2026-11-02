# Roadmap

## Phase 1 — Read-only inventory
- [x] Repository and native SwiftUI skeleton
- [x] Scan standard system and user plug-in folders
- [x] Read basic bundle metadata without loading plug-ins
- [x] Recursive scan of vendor subfolders
- [ ] Validate scanner against the user's installed collection
- [ ] Investigate a small number of Acustica Audio VST3 bundles separately

## Phase 2 — Catalog experience
- [x] Product grouping across VST2/VST3/AU (initial bundle-ID/name matching)
- [x] Automatic first-pass category suggestions based on plug-in names
- [x] Category browser and format filters
- [x] Visual product grid with manufacturer and installed-format labels
- [x] Product detail sheet showing every installed format and path
- [ ] Persistent local database and incremental refresh
- [ ] Editable categories and favorites
- [ ] Manufacturer browser

## Phase 3 — Artwork
- [ ] Optional automatic artwork lookup
- [ ] Manual screenshot import
- [ ] Artwork remains optional and never blocks inventory

## Non-goals
- No plug-in activation/deactivation
- No installation, removal or file movement
- No plug-in loading or instantiation
- No DAW integration that changes projects or plug-in state
