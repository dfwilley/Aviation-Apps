import SwiftUI

@main
struct HangarVoiceLogApp: App {
    @StateObject private var store = EntryStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .tint(Theme.accent)
        }
    }
}
