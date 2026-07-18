import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedMainSection) {
                ForEach(MainSection.allCases) { section in
                    Label(section.title(language: appState.language), systemImage: section.symbolName)
                        .tag(section)
                }
            }
            .navigationTitle(appState.localized("app.title"))
            .toolbar {
                Button {
                    appState.refreshAll()
                } label: {
                    Label(appState.localized("refresh"), systemImage: "arrow.clockwise")
                }
            }
        } detail: {
            switch appState.selectedMainSection {
            case .guardrail:
                GuardDashboardView()
                    .navigationTitle(appState.localized("guard"))
            case .workspaces:
                WorkspacePoliciesView()
                    .navigationTitle(appState.localized("workspaces"))
            case .summary:
                SummaryOverviewView()
                    .navigationTitle(appState.localized("summary"))
            case .integrations:
                IntegrationsOverviewView()
                    .navigationTitle(appState.localized("integrations"))
            }
        }
        .environmentObject(appState)
    }
}
