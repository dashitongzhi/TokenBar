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
        Self.windowLabel(from: intervalStartAt, to: intervalResetAt)
    }

    var weeklyWindowLabel: String {
        Self.windowLabel(from: weeklyStartAt, to: weeklyResetAt)
    }

    private static func windowLabel(from start: Date, to end: Date) -> String {
        let seconds = max(end.timeIntervalSince(start), 0)
        if seconds >= 86_400 {
            let days = max(Int(round(seconds / 86_400)), 1)
            return days == 1 ? "1-day window" : "\(days)-day window"
        }
        if seconds >= 3_600 {
            let hours = max(Int(round(seconds / 3_600)), 1)
            return hours == 1 ? "1-hour window" : "\(hours)-hour window"
        }
        let minutes = max(Int(round(seconds / 60)), 1)
        return minutes == 1 ? "1-minute window" : "\(minutes)-minute window"
    }
}

struct MiniMaxQuotaWindow: Equatable {
    var modelName: String
    var intervalUsedCount: Double
    var intervalTotalCount: Double
    var intervalUsedPercent: Double
    var intervalRemainingPercent: Double?
    var intervalStartAt: Date
    var intervalResetAt: Date
    var weeklyUsedCount: Double
    var weeklyTotalCount: Double
    var weeklyUsedPercent: Double
    var weeklyRemainingPercent: Double?
    var weeklyStartAt: Date
    var weeklyResetAt: Date
}

enum MiniMaxUsageRefreshResult: Equatable {
    case success(MiniMaxUsageSnapshot)
    case unavailable(String)
    case failure(String)
}

struct MiniMaxUsageService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refresh() async -> MiniMaxUsageRefreshResult {
        guard let apiKey = await miniMaxAPIKey() else {
            return .unavailable("Set MINIMAX_API_KEY in the app environment or save it to TokenBar Keychain to read MiniMax Token Plan quotas.")
        }

        do {
            let response = try await request(MiniMaxQuotaResponse.self, apiKey: apiKey)
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

    private func request<T: Decodable>(_ type: T.Type, apiKey: String) async throws -> T {
        guard let url = URL(string: MiniMaxUsageSnapshot.tokenPlanURL) else {
            throw MiniMaxUsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MiniMaxUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MiniMaxUsageError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func snapshot(from response: MiniMaxQuotaResponse, now: Date = .now) throws -> MiniMaxUsageSnapshot {
        let windows = response.modelRemains.map { item in
            MiniMaxQuotaWindow(
                modelName: item.modelName,
                intervalUsedCount: item.currentIntervalUsageCount,
                intervalTotalCount: item.currentIntervalTotalCount,
                intervalUsedPercent: usedPercent(
                    used: item.currentIntervalUsageCount,
                    total: item.currentIntervalTotalCount,
                    remainingPercent: item.currentIntervalRemainingPercent
                ),
                intervalRemainingPercent: item.currentIntervalRemainingPercent,
                intervalStartAt: Self.date(milliseconds: item.startTime),
                intervalResetAt: Self.date(milliseconds: item.endTime),
                weeklyUsedCount: item.currentWeeklyUsageCount,
                weeklyTotalCount: item.currentWeeklyTotalCount,
                weeklyUsedPercent: usedPercent(
                    used: item.currentWeeklyUsageCount,
                    total: item.currentWeeklyTotalCount,
                    remainingPercent: item.currentWeeklyRemainingPercent
                ),
                weeklyRemainingPercent: item.currentWeeklyRemainingPercent,
                weeklyStartAt: Self.date(milliseconds: item.weeklyStartTime),
                weeklyResetAt: Self.date(milliseconds: item.weeklyEndTime)
            )
        }
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

    private func usedPercent(used: Double, total: Double, remainingPercent: Double?) -> Double {
        if total > 0 {
            return min(max((used / total) * 100, 0), 100)
        }
        if let remainingPercent {
            return min(max(100 - remainingPercent, 0), 100)
        }
        return 0
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

    private static func date(milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "MiniMax returned an error without a JSON message."
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        if let msg = object["msg"] as? String {
            return msg
        }
        if let base = object["base_resp"] as? [String: Any], let status = base["status_msg"] as? String {
            return status
        }
        return "MiniMax returned an error without a JSON message."
    }
}

private enum MiniMaxUsageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyQuota
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "MiniMax quota refresh failed: invalid endpoint URL."
        case .invalidResponse:
            "MiniMax quota refresh failed: invalid HTTP response."
        case .emptyQuota:
            "MiniMax quota refresh failed: response did not include quota windows."
        case .httpStatus(let status, let message):
            "MiniMax quota refresh failed with HTTP \(status): \(message)"
        }
    }
}

private struct MiniMaxQuotaResponse: Decodable {
    var modelRemains: [MiniMaxQuotaItem]
    var baseResp: MiniMaxBaseResponse?

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }
}

private struct MiniMaxBaseResponse: Decodable {
    var statusCode: Int
    var statusMsg: String

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

private struct MiniMaxQuotaItem: Decodable {
    var startTime: Double
    var endTime: Double
    var remainsTime: Double
    var currentIntervalTotalCount: Double
    var currentIntervalUsageCount: Double
    var modelName: String
    var currentWeeklyTotalCount: Double
    var currentWeeklyUsageCount: Double
    var weeklyStartTime: Double
    var weeklyEndTime: Double
    var weeklyRemainsTime: Double
    var currentIntervalRemainingPercent: Double?
    var currentWeeklyRemainingPercent: Double?

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case remainsTime = "remains_time"
        case currentIntervalTotalCount = "current_interval_total_count"
        case currentIntervalUsageCount = "current_interval_usage_count"
        case modelName = "model_name"
        case currentWeeklyTotalCount = "current_weekly_total_count"
        case currentWeeklyUsageCount = "current_weekly_usage_count"
        case weeklyStartTime = "weekly_start_time"
        case weeklyEndTime = "weekly_end_time"
        case weeklyRemainsTime = "weekly_remains_time"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try container.decodeLossyDouble(forKey: .startTime)
        endTime = try container.decodeLossyDouble(forKey: .endTime)
        remainsTime = try container.decodeLossyDouble(forKey: .remainsTime)
        currentIntervalTotalCount = try container.decodeLossyDouble(forKey: .currentIntervalTotalCount)
        currentIntervalUsageCount = try container.decodeLossyDouble(forKey: .currentIntervalUsageCount)
        modelName = (try? container.decode(String.self, forKey: .modelName)) ?? "unknown"
        currentWeeklyTotalCount = try container.decodeLossyDouble(forKey: .currentWeeklyTotalCount)
        currentWeeklyUsageCount = try container.decodeLossyDouble(forKey: .currentWeeklyUsageCount)
        weeklyStartTime = try container.decodeLossyDouble(forKey: .weeklyStartTime)
        weeklyEndTime = try container.decodeLossyDouble(forKey: .weeklyEndTime)
        weeklyRemainsTime = try container.decodeLossyDouble(forKey: .weeklyRemainsTime)
        currentIntervalRemainingPercent = try? container.decodeLossyDouble(forKey: .currentIntervalRemainingPercent)
        currentWeeklyRemainingPercent = try? container.decodeLossyDouble(forKey: .currentWeeklyRemainingPercent)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key), let number = Double(value) {
            return number
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a numeric value.")
    }
}
