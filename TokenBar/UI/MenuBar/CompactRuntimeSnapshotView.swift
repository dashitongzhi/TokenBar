import SwiftUI

// Card structure adapted from codexU's RuntimeSummaryCard.
// Copyright (c) 2026 Guomeiqing. Licensed under the MIT License.
// See README.third-party-notices.md.
struct CompactRuntimeSnapshotView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label(appState.localized("runtimeSnapshot"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Label(appState.localAPIStatusTitle, systemImage: localAPISymbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(localAPIColor)
                    .lineLimit(1)
            }

            if displayedProviders.isEmpty {
                Text(appState.localized("noProvider"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            } else {
                ForEach(displayedProviders) { provider in
                    ProviderRuntimeCard(
                        provider: provider,
                        isSelected: provider.id == appState.selectedProviderID
                    )
                }
            }
        }
    }

    private var displayedProviders: [ProviderUsage] {
        var result: [ProviderUsage] = []

        func append(_ provider: ProviderUsage?) {
            guard let provider, result.contains(where: { $0.id == provider.id }) == false else { return }
            result.append(provider)
        }

        append(appState.selectedProvider)
        append(appState.mostUrgentProvider)

        for provider in appState.providers where provider.isLive || provider.sourceKind == .localAgent || provider.sourceKind == .ccSwitch {
            append(provider)
            if result.count == 2 { break }
        }

        for provider in appState.providers where result.count < 2 {
            append(provider)
        }

        return Array(result.prefix(2))
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
}

private struct ProviderRuntimeCard: View {
    @EnvironmentObject private var appState: AppState
    let provider: ProviderUsage
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: provider.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(provider.status.color)
                    .frame(width: 24, height: 24)
                    .background(provider.status.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(provider.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                StatusPill(status: provider.status)
                    .scaleEffect(0.88, anchor: .trailing)
            }

            HStack(alignment: .top, spacing: 10) {
                metricColumn(
                    title: appState.localized("remaining"),
                    value: remainingText,
                    detail: resetText
                )
                Divider()
                metricColumn(
                    title: appState.localized("tokens"),
                    value: tokenText,
                    detail: appState.localized("today")
                )
                Divider()
                metricColumn(
                    title: appState.localized("spend"),
                    value: spendText,
                    detail: appState.localized("today")
                )
            }
            .frame(height: 42)

            if provider.hasKnownQuotaLimit {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                        Capsule(style: .continuous)
                            .fill(provider.status.color.opacity(0.72))
                            .frame(width: proxy.size.width * remainingRatio)
                    }
                }
                .frame(height: 4)
            }

            HStack(spacing: 5) {
                Image(systemName: provider.sourceKind.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(provider.sourceKind.color)
                Text(sourceText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.38) : Color(nsColor: .separatorColor).opacity(0.55),
                            lineWidth: 0.9
                        )
                )
        )
        .help(provider.sourceDescription.isEmpty ? provider.name : provider.sourceDescription)
    }

    private func metricColumn(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remainingRatio: CGFloat {
        CGFloat(max(0, min(1, 1 - min(provider.usageRatio, 1))))
    }

    private var remainingText: String {
        guard provider.hasKnownQuotaLimit else { return "--" }
        return "\(Int((remainingRatio * 100).rounded()))%"
    }

    private var resetText: String {
        guard provider.hasKnownQuotaLimit else { return appState.localized("noLiveQuotaYet") }
        return "\(appState.localized("reset")) \(appState.shortCountdown(to: provider.resetAt))"
    }

    private var tokenText: String {
        abbreviated(provider.todayTokenCount)
    }

    private var spendText: String {
        provider.hasKnownSpendToday ? "$\(appState.formatMoney(provider.spendToday))" : "--"
    }

    private var sourceText: String {
        let source = provider.sourceKind.title(language: appState.language)
        guard provider.sourceDescription.isEmpty == false else { return source }
        return "\(source) · \(provider.sourceDescription)"
    }

    private func abbreviated(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(Int(value))"
    }
}
