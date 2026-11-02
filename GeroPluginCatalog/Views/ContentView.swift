import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PluginCatalogStore
    @State private var searchText = ""
    @State private var selectedFormat: PluginFormat?

    private var filteredPlugins: [PluginInstallation] {
        store.installations.filter { plugin in
            let matchesSearch = searchText.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(searchText)
                || (plugin.manufacturer?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesFormat = selectedFormat == nil || plugin.format == selectedFormat
            return matchesSearch && matchesFormat
        }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Library") {
                    Label("All Plug-ins", systemImage: "square.grid.2x2")
                        .badge(store.installations.count)
                }
                Section("Formats") {
                    ForEach(PluginFormat.allCases) { format in
                        Button {
                            selectedFormat = selectedFormat == format ? nil : format
                        } label: {
                            Label(format.rawValue, systemImage: "puzzlepiece.extension")
                                .foregroundStyle(selectedFormat == format ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Gero Plugin Catalog")
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                if filteredPlugins.isEmpty {
                    ContentUnavailableView(
                        store.installations.isEmpty ? "No Plug-ins Catalogued" : "No Matching Plug-ins",
                        systemImage: "puzzlepiece.extension",
                        description: Text(store.installations.isEmpty
                            ? "Run a scan to build your local plug-in inventory."
                            : "Try another search or format filter.")
                    )
                } else {
                    List(filteredPlugins) { plugin in
                        PluginRow(plugin: plugin)
                    }
                    .listStyle(.inset)
                }
                footer
            }
        }
        .searchable(text: $searchText, prompt: "Search name or manufacturer")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Audio Plug-ins")
                    .font(.largeTitle.bold())
                Text("\(filteredPlugins.count) shown · \(store.installations.count) catalogued")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.scan()
            } label: {
                Label(store.isScanning ? "Scanning…" : "Scan Mac", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isScanning)
        }
        .padding(22)
    }

    private var footer: some View {
        HStack {
            Text(store.scanMessage)
            Spacer()
            if let date = store.lastScanDate {
                Text("Last scan: \(date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct PluginRow: View {
    let plugin: PluginInstallation

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name).font(.headline)
                Text(plugin.manufacturer ?? "Manufacturer not available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(plugin.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(plugin.format.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                if let version = plugin.version {
                    Text("v\(version)").font(.caption2).foregroundStyle(.secondary)
                }
                Text(plugin.isUserInstalled ? "User" : "System")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}
