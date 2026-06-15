import SwiftUI

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
