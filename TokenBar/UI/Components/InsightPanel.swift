import SwiftUI

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
