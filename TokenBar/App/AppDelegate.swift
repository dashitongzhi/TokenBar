import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var localAPIServer: LocalAPIServer?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusBarController = StatusBarController(appState: .shared)
        localAPIServer = .shared
        localAPIServer?.syncWithPreference()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                AppState.shared.refreshAll()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        localAPIServer?.stop()
        localAPIServer = nil
    }
}
