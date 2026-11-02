import SwiftUI

@main
struct GeroPluginCatalogApp: App {
    @StateObject private var store = PluginCatalogStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
    }
}
