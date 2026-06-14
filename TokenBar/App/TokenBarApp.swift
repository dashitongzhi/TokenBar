import SwiftUI

@main
struct TokenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            MainDashboardView()
                .environmentObject(appState)
                .frame(minWidth: 880, minHeight: 620)
                .task {
                    LocalAPIServer.shared.syncWithPreference()
                }
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 720, height: 560)
        }
    }
}
