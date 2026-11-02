import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: PluginCatalogStore
    @State private var searchText = ""
    @State private var selectedFormat: PluginFormat?
    @State private var selectedCategory: PluginCategory?
    @State private var selectedProduct: PluginProduct?

    private var filteredProducts: [PluginProduct] {
        PluginProduct.catalog(from: store.installations).filter { product in
            let matchesSearch = searchText.isEmpty
                || product.name.localizedCaseInsensitiveContains(searchText)
                || (product.manufacturer?.localizedCaseInsensitiveContains(searchText) ?? false)
                || product.installations.contains { $0.path.localizedCaseInsensitiveContains(searchText) }
            let matchesFormat = selectedFormat == nil
                || product.installations.contains { $0.format == selectedFormat }
            let matchesCategory = selectedCategory == nil || product.category == selectedCategory
            return matchesSearch && matchesFormat && matchesCategory
        }
    }

    private var categoryCounts: [(PluginCategory, Int)] {
        let products = PluginProduct.catalog(from: store.installations)
        return PluginCategory.allCases.compactMap { category in
            let count = products.filter { $0.category == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Library") {
                    Button {
                        selectedCategory = nil
                        selectedFormat = nil
                    } label: {
                        Label("All Plug-ins", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)
                }

                Section("Categories") {
                    ForEach(PluginCategory.allCases.filter { category in
                        categoryCounts.contains { $0.0 == category }
                    }, id: \.self) { category in
                        Button {
                            selectedCategory = selectedCategory == category ? nil : category
                        } label: {
                            Label(category.rawValue, systemImage: category.symbol)
                                .badge(categoryCounts.first { $0.0 == category }?.1 ?? 0)
                                .foregroundStyle(selectedCategory == category ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Formats") {
                    ForEach(PluginFormat.allCases) { format in
                        Button {
                            selectedFormat = selectedFormat == format ? nil : format
                        } label: {
                            Label(format.rawValue, systemImage: "puzzlepiece.extension")
                                .badge(store.installations.filter { $0.format == format }.count)
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
                if filteredProducts.isEmpty {
                    ContentUnavailableView(
                        store.installations.isEmpty ? "No Plug-ins Catalogued" : "No Matching Plug-ins",
                        systemImage: "puzzlepiece.extension",
                        description: Text(store.installations.isEmpty
                            ? "Run a scan to build your local plug-in inventory."
                            : "Try another search, category or format filter.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(filteredProducts) { product in
                                Button {
                                    selectedProduct = product
                                } label: {
                                    PluginCard(product: product, artworkPath: store.artworkPaths[product.id])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
                footer
            }
        }
        .searchable(text: $searchText, prompt: "Search plug-in or manufacturer")
        .sheet(item: $selectedProduct) { product in
            PluginDetailSheet(product: product)
                .frame(minWidth: 560, minHeight: 420)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCategory?.rawValue ?? "Your Audio Plug-ins")
                    .font(.largeTitle.bold())
                Text("\(filteredProducts.count) products · \(filteredProducts.reduce(0) { $0 + $1.installations.count }) installations")
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

private struct PluginCard: View {
    let product: PluginProduct
    let artworkPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.10))
                if let artworkPath, let artwork = NSImage(contentsOfFile: artworkPath) {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: product.category.symbol)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 112)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(product.manufacturer ?? "Manufacturer not available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                ForEach(Array(Set(product.installations.map(\.format))).sorted { $0.rawValue < $1.rawValue }) { format in
                    Text(format.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 0)
                Text(product.category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct PluginDetailSheet: View {
    let product: PluginProduct
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PluginCatalogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                if let artworkPath = store.artworkPaths[product.id],
                   let artwork = NSImage(contentsOfFile: artworkPath) {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 64)
                } else {
                    Image(systemName: product.category.symbol)
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                        .frame(width: 76, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.title.bold())
                    Text(product.manufacturer ?? "Manufacturer not available")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.chooseArtwork(for: product.id)
                } label: {
                    Label("Choose image…", systemImage: "photo")
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()
            Text("Installed formats and locations")
                .font(.headline)

            List(product.installations) { installation in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(installation.format.rawValue).font(.subheadline.bold())
                        Spacer()
                        Text(installation.version.map { "Version \($0)" } ?? "Version unknown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(installation.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            Text("This catalog only reads plug-in information. It never loads, moves or changes plug-ins.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
    }
}
