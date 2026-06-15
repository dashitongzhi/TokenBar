import SwiftUI

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
