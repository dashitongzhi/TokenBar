import SwiftUI

struct CompactRuntimeSnapshotView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("runtimeSnapshot"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Text(appState.localized("today"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                runtimeMetric(
                    title: appState.localized("localAPI"),
                    value: appState.localAPISummaryValue,
                    detail: appState.localAPIStatusTitle,
                    symbol: localAPISymbol,
                    color: localAPIColor
                )
                Divider()
                runtimeMetric(
                    title: appState.localized("liveData"),
                    value: "\(liveDataProviderCount)",
                    detail: liveDataProviderCount > 0 ? appState.localized("connectedSources") : appState.localized("sourcesNeedWork"),
                    symbol: "antenna.radiowaves.left.and.right",
                    color: liveDataProviderCount > 0 ? .green : .orange
                )
                Divider()
                runtimeMetric(
                    title: appState.localized("attention"),
                    value: urgentProviderValue,
                    detail: urgentProviderDetail,
                    symbol: urgentProviderSymbol,
                    color: urgentProviderColor
                )
            }
            .frame(minHeight: 50)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func runtimeMetric(title: String, value: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(title): \(detail)")
    }

    private var liveDataProviderCount: Int {
        appState.providers.filter(\.isLive).count
    }

    private var localAPIColor: Color {
        switch appState.localAPIStatus {
        case .running:
            .green
        case .starting:
            .orange
        case .disabled, .stopped:
            .secondary
        case .failed:
            .red
        }
    }

    private var localAPISymbol: String {
        switch appState.localAPIStatus {
        case .running:
            "checkmark.circle.fill"
        case .starting:
            "clock.badge"
        case .disabled:
            "power.circle"
        case .stopped:
            "pause.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var urgentProvider: ProviderUsage? {
        guard let provider = appState.mostUrgentProvider, provider.status != .healthy else {
            return nil
        }
        return provider
    }

    private var urgentProviderValue: String {
        urgentProvider?.name ?? appState.localized("noProviderAlerts")
    }

    private var urgentProviderDetail: String {
        guard let provider = urgentProvider else {
            return appState.localized("budgetSafe")
        }
        if let alert = provider.displayHealthAlert {
            return alert.title
        }
        return appState.localized("providerNeedsAttention")
    }

    private var urgentProviderSymbol: String {
        urgentProvider == nil ? "checkmark.shield" : "exclamationmark.triangle.fill"
    }

    private var urgentProviderColor: Color {
        urgentProvider?.status.color ?? .green
    }
}
