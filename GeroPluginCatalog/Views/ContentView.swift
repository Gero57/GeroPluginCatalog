import SwiftUI
import AppKit

private enum ArtworkImageCache {
    static let cache = NSCache<NSString, NSImage>()

    static func image(at path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: PluginCatalogStore
    @State private var searchText = ""
    @State private var selectedFormat: PluginFormat?
    @State private var selectedCategory: PluginCategory?
    @State private var selectedProduct: PluginProduct?
    @State private var showingAddPlugin = false
    @State private var showingAppearance = false
    @AppStorage("interfaceScale") private var interfaceScale = 1.0
    @AppStorage("interfaceTheme") private var interfaceTheme = "System"
    @AppStorage("interfaceAccent") private var interfaceAccent = "Blue"

    private var accentColor: Color {
        switch interfaceAccent {
        case "Purple": return .purple
        case "Green": return .green
        case "Orange": return .orange
        case "Pink": return .pink
        case "Red": return .red
        default: return .blue
        }
    }

    private var colorScheme: ColorScheme? {
        switch interfaceTheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }

    private var dynamicType: DynamicTypeSize {
        switch interfaceScale {
        case ..<0.9: return .small
        case ..<1.05: return .medium
        case ..<1.18: return .large
        case ..<1.3: return .xLarge
        default: return .xxLarge
        }
    }

    private var filteredProducts: [PluginProduct] {
        store.products.filter { product in
            let matchesSearch = searchText.isEmpty
                || product.name.localizedCaseInsensitiveContains(searchText)
                || (product.manufacturer?.localizedCaseInsensitiveContains(searchText) ?? false)
                || product.installations.contains { $0.path.localizedCaseInsensitiveContains(searchText) }
            let matchesFormat = selectedFormat == nil
                || product.installations.contains { $0.format == selectedFormat }
                || product.manualFormat == selectedFormat?.rawValue
            let matchesCategory = selectedCategory == nil || product.category == selectedCategory
            return matchesSearch && matchesFormat && matchesCategory
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
                    }.buttonStyle(.plain)
                }
                Section("Categories") {
                    ForEach(PluginCategory.allCases.filter { (store.categoryCounts[$0] ?? 0) > 0 }, id: \.self) { category in
                        Button {
                            selectedCategory = selectedCategory == category ? nil : category
                        } label: {
                            Label(category.rawValue, systemImage: category.symbol)
                                .badge(store.categoryCounts[category] ?? 0)
                                .foregroundStyle(selectedCategory == category ? Color.accentColor : .primary)
                        }.buttonStyle(.plain)
                    }
                }
                Section("Formats") {
                    ForEach(PluginFormat.allCases) { format in
                        Button {
                            selectedFormat = selectedFormat == format ? nil : format
                        } label: {
                            Label(format.rawValue, systemImage: "puzzlepiece.extension")
                                .badge(store.formatCounts[format] ?? 0)
                                .foregroundStyle(selectedFormat == format ? Color.accentColor : .primary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Gero Plugin Catalog")
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                if filteredProducts.isEmpty {
                    ContentUnavailableView("No Plug-ins Catalogued", systemImage: "puzzlepiece.extension",
                        description: Text("Run a scan or add a plug-in manually."))
                } else {
                    GeometryReader { geometry in
                        let spacing = 12 * interfaceScale
                        let minimumWidth = 190 * interfaceScale
                        let availableWidth = max(1, geometry.size.width - 28)
                        let columnCount = max(1, Int((availableWidth + spacing) / (minimumWidth + spacing)))
                        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)

                        ScrollView {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                                ForEach(filteredProducts) { product in
                                    Button { selectedProduct = product } label: {
                                        PluginCard(product: product, artworkPath: store.artworkPaths[product.id], scale: interfaceScale)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }
                    }
                }
                footer
            }
        }
        .tint(accentColor)
        .preferredColorScheme(colorScheme)
        .environment(\.dynamicTypeSize, dynamicType)
        .searchable(text: $searchText, prompt: "Search plug-in or manufacturer")
        .sheet(item: $selectedProduct) { product in
            PluginDetailSheet(product: product).frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $showingAddPlugin) {
            AddPluginSheet { name, maker, category, format in
                store.addManualPlugin(name: name, manufacturer: maker, category: category, format: format)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCategory?.rawValue ?? "Your Audio Plug-ins").font(.largeTitle.bold())
                Text("\(filteredProducts.count) products · \(filteredProducts.reduce(0) { $0 + max($1.installations.count, $1.manualFormat == nil ? 0 : 1) }) entries")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showingAddPlugin = true } label: {
                Label("Add Plug-in", systemImage: "plus")
            }.buttonStyle(.bordered)
            Button { showingAppearance = true } label: {
                Label("Appearance", systemImage: "paintpalette")
            }.buttonStyle(.bordered)
            .popover(isPresented: $showingAppearance, arrowEdge: .bottom) {
                AppearanceSettings(theme: $interfaceTheme, accent: $interfaceAccent, scale: $interfaceScale)
                    .padding(18)
                    .frame(width: 300)
            }
            Button { store.scan() } label: {
                Label(store.isScanning ? "Scanning…" : "Scan Mac", systemImage: "arrow.clockwise")
            }.buttonStyle(.borderedProminent).disabled(store.isScanning)
        }.padding(22)
    }

    private var footer: some View {
        HStack {
            Text(store.scanMessage)
            Spacer()
            if let date = store.lastScanDate {
                Text("Last scan: \(date.formatted(date: .abbreviated, time: .shortened))")
            }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
    }
}

private struct PluginCard: View {
    let product: PluginProduct
    let artworkPath: String?
    var scale: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.10))
                if let artwork = ArtworkImageCache.image(at: artworkPath) {
                    Image(nsImage: artwork).resizable().scaledToFit().padding(8)
                } else {
                    Image(systemName: product.category.symbol).font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
                }
            }.frame(height: 92 * scale)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name).font(.headline).lineLimit(1).foregroundStyle(.primary)
                Text(product.manufacturer?.isEmpty == false ? product.manufacturer! : "Manufacturer not available")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                ForEach(Array(Set(product.installations.map(\.format))).sorted { $0.rawValue < $1.rawValue }) { format in
                    Text(format.rawValue).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 4).background(.quaternary, in: Capsule())
                }
                if let manualFormat = product.manualFormat {
                    Text(manualFormat).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 4).background(.quaternary, in: Capsule())
                    Text("Manual").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(product.category.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(9 * scale)
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
                if let artwork = ArtworkImageCache.image(at: store.artworkPaths[product.id]) {
                    Image(nsImage: artwork).resizable().scaledToFit().frame(width: 76, height: 64)
                } else {
                    Image(systemName: product.category.symbol).font(.system(size: 34)).foregroundStyle(.secondary).frame(width: 76, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.title.bold())
                    Text(product.manufacturer?.isEmpty == false ? product.manufacturer! : "Manufacturer not available").foregroundStyle(.secondary)
                    if let manualFormat = product.manualFormat { Text("Manual catalog entry · \(manualFormat)").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button { store.chooseArtwork(for: product.id) } label: { Label("Choose image…", systemImage: "photo") }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            Text(product.installations.isEmpty ? "Catalog entry" : "Installed formats and locations").font(.headline)
            if product.installations.isEmpty {
                Text("This is a visual catalog entry. It does not represent an installed plug-in.").foregroundStyle(.secondary)
                Text("Format: \(product.manualFormat ?? "Not specified")").foregroundStyle(.secondary)
            } else {
                List(product.installations) { installation in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(installation.format.rawValue).font(.subheadline.bold())
                            Spacer()
                            Text(installation.version.map { "Version \($0)" } ?? "Version unknown").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(installation.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(.vertical, 4)
                }
            }
            Text("This catalog only reads plug-in information. It never loads, moves or changes plug-ins.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22)
    }
}

private struct AppearanceSettings: View {
    @Binding var theme: String
    @Binding var accent: String
    @Binding var scale: Double
    private let accents = ["Blue", "Purple", "Green", "Orange", "Pink", "Red"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Interface appearance", systemImage: "paintpalette").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme").font(.subheadline.weight(.semibold))
                Picker("Theme", selection: $theme) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Interface color").font(.subheadline.weight(.semibold))
                HStack(spacing: 11) {
                    ForEach(accents, id: \.self) { item in
                        Button { accent = item } label: {
                            Circle().fill(color(for: item)).frame(width: 25, height: 25)
                                .overlay(Circle().strokeBorder(.primary.opacity(accent == item ? 0.8 : 0), lineWidth: 2).padding(-3))
                        }.buttonStyle(.plain).help(item)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Interface size").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(scale * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $scale, in: 0.8...1.35, step: 0.05)
                HStack {
                    Text("Smaller")
                    Spacer()
                    Text("Larger")
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Reset") { theme = "System"; accent = "Blue"; scale = 1.0 }
            }
        }
    }

    private func color(for name: String) -> Color {
        switch name {
        case "Purple": return .purple
        case "Green": return .green
        case "Orange": return .orange
        case "Pink": return .pink
        case "Red": return .red
        default: return .blue
        }
    }
}

private struct AddPluginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String, PluginCategory, String) -> Void
    @State private var name = ""
    @State private var manufacturer = "Steinberg"
    @State private var category: PluginCategory = .reverb
    @State private var format = "Cubase Internal"
    private let formats = ["Cubase Internal", "VST3", "VST2", "AU", "Other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Plug-in").font(.title.bold())
            Text("Create a visual catalog entry for a plug-in that the automatic scan did not find.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Plug-in name", text: $name)
                TextField("Manufacturer", text: $manufacturer)
                Picker("Category", selection: $category) {
                    ForEach(PluginCategory.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
                }
                Picker("Format", selection: $format) {
                    ForEach(formats, id: \.self) { item in Text(item).tag(item) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Plug-in") {
                    onSave(name, manufacturer, category, format)
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 460, height: 360)
    }
}
