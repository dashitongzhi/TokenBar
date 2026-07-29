import Foundation

struct MiniMaxUsageSnapshot: Equatable {
    static let anthropicBaseURL = "https://api.minimaxi.com/anthropic"
    static let tokenPlanURL = "https://api.minimaxi.com/v1/token_plan/remains"

    var primaryModelName: String
    var intervalUsedPercent: Double
    var intervalRemainingPercent: Double?
    var intervalUsedCount: Double
    var intervalTotalCount: Double
    var intervalStartAt: Date
    var intervalResetAt: Date
    var weeklyUsedPercent: Double
    var weeklyRemainingPercent: Double?
    var weeklyUsedCount: Double
    var weeklyTotalCount: Double
    var weeklyStartAt: Date
    var weeklyResetAt: Date
    var modelWindows: [MiniMaxQuotaWindow]
    var fetchedAt: Date
    var history: [UsagePoint]

    var intervalWindowLabel: String {
        QuotaWindowFormatting.label(from: intervalStartAt, to: intervalResetAt)
    }

    var weeklyWindowLabel: String {
        QuotaWindowFormatting.label(from: weeklyStartAt, to: weeklyResetAt)
    }
}

enum MiniMaxUsageRefreshResult: Equatable {
    case success(MiniMaxUsageSnapshot)
    case unavailable(String)
    case failure(String)
}

struct MiniMaxUsageService {
    private let quotaClient: MiniMaxQuotaClient

    init(session: URLSession = .shared) {
        quotaClient = MiniMaxQuotaClient(session: session)
    }

    func refresh() async -> MiniMaxUsageRefreshResult {
        guard let apiKey = await miniMaxAPIKey() else {
            return .unavailable("Set MINIMAX_API_KEY in the app environment or save it to TokenBar Keychain to read MiniMax Token Plan quotas.")
        }

        do {
            let response = try await quotaClient.fetch(apiKey: apiKey)
            guard response.baseResp?.statusCode ?? 0 == 0 else {
                return .failure("MiniMax quota refresh failed: \(response.baseResp?.statusMsg ?? "unknown status").")
            }
            let snapshot = try snapshot(from: response)
            return .success(snapshot)
        } catch let error as MiniMaxUsageError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("MiniMax quota refresh failed: \(error.localizedDescription)")
        }
    }

    private func snapshot(from response: MiniMaxQuotaResponse, now: Date = .now) throws -> MiniMaxUsageSnapshot {
        let windows = response.modelRemains.map { $0.quotaWindow() }
        guard let primary = windows.first(where: { $0.modelName == "general" }) ?? windows.first else {
            throw MiniMaxUsageError.emptyQuota
        }
        return MiniMaxUsageSnapshot(
            primaryModelName: primary.modelName,
            intervalUsedPercent: primary.intervalUsedPercent,
            intervalRemainingPercent: primary.intervalRemainingPercent,
            intervalUsedCount: primary.intervalUsedCount,
            intervalTotalCount: primary.intervalTotalCount,
            intervalStartAt: primary.intervalStartAt,
            intervalResetAt: primary.intervalResetAt,
            weeklyUsedPercent: primary.weeklyUsedPercent,
            weeklyRemainingPercent: primary.weeklyRemainingPercent,
            weeklyUsedCount: primary.weeklyUsedCount,
            weeklyTotalCount: primary.weeklyTotalCount,
            weeklyStartAt: primary.weeklyStartAt,
            weeklyResetAt: primary.weeklyResetAt,
            modelWindows: windows,
            fetchedAt: now,
            history: [UsagePoint(timestamp: now, value: primary.intervalUsedPercent)]
        )
    }

    private func miniMaxAPIKey() async -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in ["MINIMAX_API_KEY", "TOKENBAR_MINIMAX_API_KEY", "MINIMAX_ANTHROPIC_API_KEY"] {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }

        for keyName in [
            "MINIMAX_API_KEY",
            "TOKENBAR_MINIMAX_API_KEY",
            "MINIMAX_ANTHROPIC_API_KEY",
            "minimax.api_key",
            "minimax.apiKey",
            "minimax.anthropic_api_key",
            "minimax.anthropicApiKey"
        ] {
            if let value = try? await KeychainService.shared.retrieve(key: keyName) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }

        return nil
    }

}

private enum MiniMaxUsageError: LocalizedError {
    case emptyQuota

    var errorDescription: String? {
        switch self {
        case .emptyQuota:
            "MiniMax quota refresh failed: response did not include quota windows."
        }
    }
}
