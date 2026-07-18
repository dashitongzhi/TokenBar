import Foundation

struct AnthropicUsageSnapshot: Equatable {
    var tokenTotal: Double
    var tokenToday: Double
    var requestCountMonth: Int
    var requestCountToday: Int
    var spendToday: Double
    var spendMonth: Double
    var currency: String
    var resetAt: Date
    var fetchedAt: Date
    var history: [UsagePoint]
}

enum AnthropicUsageRefreshResult: Equatable {
    case success(AnthropicUsageSnapshot)
    case unavailable(String)
    case failure(String)
}

struct AnthropicUsageService {
    private let calendar: Calendar
    private let transport: AnthropicUsageTransport
    private let snapshotMapper: AnthropicUsageSnapshotMapper

    init(session: URLSession = .shared, calendar: Calendar = .current) {
        self.calendar = calendar
        transport = AnthropicUsageTransport(session: session)
        snapshotMapper = AnthropicUsageSnapshotMapper(calendar: calendar)
    }

    func refresh() async -> AnthropicUsageRefreshResult {
        guard let adminKey = await anthropicAdminKey() else {
            return .unavailable("Set ANTHROPIC_ADMIN_KEY in the app environment or save an Anthropic Admin API key to TokenBar Keychain to enable live Claude usage.")
        }

        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now.addingTimeInterval(30 * 86_400)
        let dayCount = max(calendar.dateComponents([.day], from: monthStart, to: now).day ?? 0, 0) + 1
        let limit = min(max(dayCount, 1), 31)
        let endingAt = now

        async let usageResponse = transport.paginatedRequest(
            AnthropicUsageResponse.self,
            path: "/v1/organizations/usage_report/messages",
            queryItems: [
                URLQueryItem(name: "starting_at", value: iso8601String(monthStart)),
                URLQueryItem(name: "ending_at", value: iso8601String(endingAt)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ],
            adminKey: adminKey
        )
        async let costResponse = transport.paginatedRequest(
            AnthropicCostResponse.self,
            path: "/v1/organizations/cost_report",
            queryItems: [
                URLQueryItem(name: "starting_at", value: iso8601String(monthStart)),
                URLQueryItem(name: "ending_at", value: iso8601String(endingAt)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ],
            adminKey: adminKey
        )

        do {
            let (usage, cost) = try await (usageResponse, costResponse)
            return .success(snapshotMapper.snapshot(from: usage, costs: cost, now: now, resetAt: nextMonth))
        } catch let error as AnthropicUsageError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("Anthropic usage refresh failed: \(error.localizedDescription)")
        }
    }

    private func anthropicAdminKey() async -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in ["ANTHROPIC_ADMIN_KEY", "TOKENBAR_ANTHROPIC_ADMIN_KEY"] {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }

        for keyName in ["ANTHROPIC_ADMIN_KEY", "TOKENBAR_ANTHROPIC_ADMIN_KEY", "anthropic.admin_key", "anthropic.adminKey"] {
            if let value = try? await KeychainService.shared.retrieve(key: keyName) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }

        return nil
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

}
