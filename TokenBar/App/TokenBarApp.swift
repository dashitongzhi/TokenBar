import Darwin
import SwiftUI

@main
struct TokenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--tokenbar-verify-minimax-ccswitch-fallback-audit") {
            do {
                try AppState.shared.verifyMiniMaxCCSwitchFallbackAuditSmoke()
                FileHandle.standardError.write(Data("TokenBar verify mode: MiniMax CC Switch fallback audit smoke passed\n".utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("TokenBar verify mode: MiniMax CC Switch fallback audit smoke failed: \(error)\n".utf8))
                exit(1)
            }
        }
        #endif

        // Used by script/build_and_run.sh --verify to exercise LocalAPIServer without LaunchServices.
        if CommandLine.arguments.contains("--tokenbar-verify-local-api") {
            FileHandle.standardError.write(Data("TokenBar verify mode: starting local API\n".utf8))
            let state = AppState.shared
            let workspace = state.selectedWorkspace
            FileHandle.standardError.write(Data("""
            TokenBar verify mode: startup policy workspace=\(state.selectedWorkspaceID) model=\(state.selectedModel) estimated_cost=\(state.estimatedRunCost) estimated_tokens=\(Int(state.estimatedTokens)) session_budget=\(state.sessionBudget) workspace_daily_budget=\(workspace?.dailyBudget ?? 0) workspace_monthly_budget=\(workspace?.monthlyBudget ?? 0) per_run_cap=\(workspace?.maxEstimatedRunCost ?? 0)

            """.utf8))
            state.localAPIEnabled = true
            state.refreshAll()
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
