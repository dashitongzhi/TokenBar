import SwiftUI

struct IntegrationsOverviewView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    SummaryTile(
                        title: appState.localized("liveData"),
                        value: "\(appState.liveProviderCount)",
                        symbol: "checkmark.seal.fill"
                    )
                    SummaryTile(
                        title: appState.localized("unsupportedProviders"),
                        value: "\(appState.unsupportedProviderCount)",
                        symbol: "exclamationmark.triangle.fill"
                    )
                    SummaryTile(
                        title: appState.localized("localAPI"),
                        value: appState.localAPISummaryValue,
                        symbol: appState.localAPIStatus.symbolName
                    )
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 14)], spacing: 14) {
                    ForEach(appState.apiMonitors) { spec in
                        APIMonitorCard(spec: spec)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct APIMonitorCard: View {
    @EnvironmentObject private var appState: AppState
    var spec: APIMonitorSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spec.name)
                            .font(.headline)
                        Text(spec.family)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: spec.symbolName)
                        .foregroundStyle(spec.capability.status.color)
                }
                Spacer()
                if let provider = appState.providers.first(where: { $0.id == spec.id }) {
                    SourcePill(source: provider.sourceKind)
                } else {
                    Text(spec.capability.title(language: appState.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(spec.capability.status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(spec.capability.status.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let provider = appState.providers.first(where: { $0.id == spec.id }),
               provider.sourceDescription.isEmpty == false {
                Text(provider.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            KeyValueRow(title: appState.localized("models"), value: spec.models.prefix(5).joined(separator: ", "))
            KeyValueRow(title: appState.localized("subscriptionAlert"), value: spec.alertMetric)

            if let request = spec.usageRequest {
                RequestBlock(title: appState.localized("realRequest"), request: request)
            } else {
                Text(spec.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Link(appState.localized("source"), destination: URL(string: spec.docsURL)!)
                Spacer()
                Link("Console", destination: URL(string: spec.subscriptionURL)!)
            }
            .font(.caption.weight(.medium))
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RequestBlock: View {
    var title: String
    var request: APIRequestTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(curl)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(6)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var curl: String {
        var lines = ["curl -X \(request.method) \"\(request.url)\""]
        lines.append(contentsOf: request.headers.map { "  -H \"\($0)\"" })
        if let body = request.body {
            lines.append("  -d '\(body)'")
        }
        return lines.joined(separator: " \\\n")
    }
}
