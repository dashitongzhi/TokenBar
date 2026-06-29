import SwiftUI

@main
struct TokenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    init() {
        // Used by script/build_and_run.sh --verify to exercise LocalAPIServer without LaunchServices.
        if CommandLine.arguments.contains("--tokenbar-verify-local-api") {
            FileHandle.standardError.write(Data("TokenBar verify mode: starting local API\n".utf8))
            AppState.shared.localAPIEnabled = true
            AppState.shared.refreshAll()
            LocalAPIServer.shared.syncWithPreference()
            RunLoop.main.run()
        }
    }

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
