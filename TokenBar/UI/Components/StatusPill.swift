import SwiftUI

struct StatusPill: View {
    @EnvironmentObject private var appState: AppState
    var status: UsageStatus

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var title: String {
        switch status {
        case .healthy: appState.localized("healthy")
        case .warning: appState.localized("warning")
        case .critical: appState.localized("critical")
        }
    }
}
