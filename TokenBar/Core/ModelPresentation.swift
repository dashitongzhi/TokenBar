import AppKit
import SwiftUI

extension UsageStatus {
    var color: Color {
        switch self {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .healthy: .systemGreen
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    var symbolName: String {
        switch self {
        case .healthy: "chart.bar.fill"
        case .warning: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }
}

extension LocalAPIStatus {
    var status: UsageStatus {
        switch self {
        case .running: .healthy
        case .disabled, .starting, .stopped: .warning
        case .failed: .critical
        }
    }

    var color: Color {
        switch self {
        case .running: .green
        case .starting: .orange
        case .failed: .red
        case .disabled, .stopped: .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .running: "network"
        case .disabled: "network.slash"
        case .starting: "hourglass"
        case .stopped: "pause.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

extension UsageDataSource {
    var color: Color {
        switch self {
        case .live: .green
        case .localAgent: .blue
        case .liveUnavailable: .orange
        case .unsupported: .secondary
        case .error: .red
        }
    }

    var symbolName: String {
        switch self {
        case .live: "checkmark.seal.fill"
        case .localAgent: "terminal.fill"
        case .liveUnavailable: "key.slash.fill"
        case .unsupported: "slash.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.live, .english): "Live"
        case (.localAgent, .english): "Local"
        case (.liveUnavailable, .english): "Needs key"
        case (.unsupported, .english): "Unsupported"
        case (.error, .english): "Error"
        case (.live, .chinese): "实时"
        case (.localAgent, .chinese): "本地"
        case (.liveUnavailable, .chinese): "需要密钥"
        case (.unsupported, .chinese): "未支持"
        case (.error, .chinese): "错误"
        }
    }
}
