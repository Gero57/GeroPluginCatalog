# Gero Plugin Catalog

A native macOS visual catalog for audio plug-ins (VST2, VST3 and Audio Units).

## Principles
- Read-only: never installs, moves, enables, disables, modifies or loads plug-ins.
- Scans standard system and current-user Audio Plug-Ins folders.
- Keeps an inventory independent of DAWs such as Cubase and Ableton.
- Treats a plug-in product separately from each installed format/location.
- Missing artwork never prevents cataloguing.

## Initial development status
This repository contains the first SwiftUI application skeleton and a read-only filesystem scanner. Category classification, persistent database, artwork management and the visual browser will be added incrementally.

## Build
Open `GeroPluginCatalog.xcodeproj` in Xcode and run the `GeroPluginCatalog` scheme on macOS 14 or later.

## Scan locations
System:
- `/Library/Audio/Plug-Ins/VST` (VST2)
- `/Library/Audio/Plug-Ins/VST3` (VST3)
- `/Library/Audio/Plug-Ins/Components` (Audio Units)

Current user:
- `~/Library/Audio/Plug-Ins/VST`
- `~/Library/Audio/Plug-Ins/VST3`
- `~/Library/Audio/Plug-Ins/Components`

The scanner reports what it can read and gracefully skips inaccessible or malformed entries.
