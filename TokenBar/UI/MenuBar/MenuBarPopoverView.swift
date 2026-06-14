import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    CompactDecisionView(decision: appState.currentDecision)
                    InsightPanel()
                    FocusBudgetView(compact: true)
                    ForEach(appState.workspacePolicies.prefix(2)) { workspace in
                        CompactWorkspaceView(workspace: workspace)
                    }
                    AuditPanel(limit: 4)
                }
                .padding(14)
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.localized("app.title"))
                    .font(.headline)
                Text(appState.localized("productTagline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                appState.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(appState.localized("refresh"))
        }
        .padding(14)
        .background(.thinMaterial)
    }

    private var footer: some View {
        HStack {
            Text("\(appState.currentDecision.status.rawValue.uppercased()) · \(appState.currentDecision.workspaceName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appState.localized("settings")) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button(appState.localized("quit")) {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .background(.thinMaterial)
    }
}

struct InsightPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("smartInsights"), systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusPill(status: appState.policyStatus)
            }
            Text(appState.insightText())
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CompactDecisionView: View {
    @EnvironmentObject private var appState: AppState
    var decision: PolicyDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: decision.status.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(decision.status.usageStatus.color)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("\(decision.workspaceName) · \(decision.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: decision.status.usageStatus)
            }

            Text(decision.recommendation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                appState.runPolicyCheck()
            } label: {
                Label(appState.localized("checkPolicy"), systemImage: "shield")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch decision.status {
        case .allow: appState.localized("decisionAllow")
        case .warn: appState.localized("decisionWarn")
        case .block: appState.localized("decisionBlock")
        }
    }
}

struct CompactWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    var workspace: WorkspacePolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(workspace.name, systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("$\(appState.formatMoney(workspace.spendToday)) / $\(appState.formatMoney(workspace.dailyBudget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(workspace.dailyRatio, 1))
                .tint(workspace.status.color)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FocusBudgetView: View {
    @EnvironmentObject private var appState: AppState
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("focusMode"), systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(appState.budgetStatus == .healthy ? appState.localized("budgetSafe") : appState.localized("budgetAtRisk"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appState.budgetStatus.color)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("$\(appState.formatMoney(appState.sessionSpend))")
                    .font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                Text("/ $\(appState.formatMoney(appState.sessionBudget))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(appState.focusModeEnabled ? appState.localized("stop") : appState.localized("start")) {
                    appState.focusModeEnabled.toggle()
                }
                Button {
                    appState.resetSessionBudget()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset")
            }

            ProgressView(value: min(appState.budgetRatio, 1))
                .tint(appState.budgetStatus.color)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ProviderCardView: View {
    @EnvironmentObject private var appState: AppState
    var provider: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(provider.name)
                            .font(.subheadline.weight(.semibold))
                        Text(provider.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: provider.symbolName)
                        .foregroundStyle(provider.status.color)
                }
                Spacer()
                SourcePill(source: provider.sourceKind)
            }

            if provider.sourceDescription.isEmpty == false {
                Text(provider.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(primaryUsageText)
                    .font(.title3.weight(.semibold))
                Text(secondaryUsageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if provider.hasKnownQuotaLimit {
                    Text("\(Int(provider.usageRatio * 100))%")
                        .font(.callout.monospacedDigit().weight(.medium))
                } else if provider.sourceKind == .live {
                    Text(provider.displayCurrency)
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if provider.hasKnownQuotaLimit {
                ProgressView(value: min(provider.usageRatio, 1))
                    .tint(provider.status.color)
            }

            MiniTrendLine(points: provider.history, color: provider.status.color)
                .frame(height: 46)

            HStack {
                metric(appState.localized("today"), "$\(appState.formatMoney(provider.spendToday))")
                Spacer()
                metric(appState.localized("requests"), "\(provider.requestCount)")
                Spacer()
                metric(appState.localized("burnRate"), "\(Int(provider.burnRatePerHour))/h")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryUsageText: String {
        if provider.sourceKind == .live {
            return "\(Int(provider.current))"
        }
        return "\(Int(provider.current))"
    }

    private var secondaryUsageText: String {
        if provider.hasKnownQuotaLimit {
            return "/ \(Int(provider.limit)) \(provider.unit)"
        }
        if provider.sourceKind == .live {
            return "\(provider.unit) month-to-date"
        }
        return provider.unit
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

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

struct SourcePill: View {
    @EnvironmentObject private var appState: AppState
    var source: UsageDataSource

    var body: some View {
        Label(source.title(language: appState.language), systemImage: source.symbolName)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(source.color)
            .background(source.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct AuditPanel: View {
    @EnvironmentObject private var appState: AppState
    var limit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(appState.localized("privacyAudit"), systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(appState.auditEvents.prefix(limit ?? appState.auditEvents.count))) { event in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.provider) · \(event.action)")
                            .font(.caption.weight(.medium))
                        Text(event.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MiniTrendLine: View {
    var points: [UsagePoint]
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let values = points.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let range = max(maxValue - minValue, 1)

            Path { path in
                for index in points.indices {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let normalized = (points[index].value - minValue) / range
                    let y = proxy.size.height - proxy.size.height * CGFloat(normalized)
                    if index == points.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
