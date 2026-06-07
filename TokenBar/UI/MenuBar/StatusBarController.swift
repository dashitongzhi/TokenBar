import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var observer: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView()
                .environmentObject(appState)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        observer = NotificationCenter.default.addObserver(
            forName: .tokenBarStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusBar()
            }
        }

        updateStatusBar()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusBar() {
        guard let button = statusItem.button else { return }
        let color = appState.statusBarColor()
        let symbol = appState.statusBarSymbolName()
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TokenBar")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))?
            .tinted(with: color)
        button.image = image
        button.title = appState.statusBarText()
        button.contentTintColor = color
    }
}

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as? NSImage ?? self
        image.isTemplate = false
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
