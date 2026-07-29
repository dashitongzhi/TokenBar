import Foundation

struct DeepSeekBalance {
    var isAvailable: Bool
    var currency: String
    var totalBalance: Double
    var toppedUpBalance: Double
    var grantedBalance: Double
}

struct DeepSeekBalanceResponse: Decodable {
    var isAvailable: Bool
    var balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Decodable {
        var currency: String
        var totalBalance: String
        var toppedUpBalance: String
        var grantedBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case toppedUpBalance = "topped_up_balance"
            case grantedBalance = "granted_balance"
        }
    }
}

struct MiniMaxQuotaResponse: Decodable {
    var modelRemains: [MiniMaxQuotaItem]
    var baseResp: MiniMaxBaseResponse?

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }
}

struct MiniMaxBaseResponse: Decodable {
    var statusCode: Int
    var statusMsg: String

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

struct MiniMaxQuotaItem: Decodable {
    var startTime: Double
    var endTime: Double
    var currentIntervalTotalCount: Double
    var currentIntervalUsageCount: Double
    var modelName: String
    var currentWeeklyTotalCount: Double
    var currentWeeklyUsageCount: Double
    var weeklyStartTime: Double
    var weeklyEndTime: Double
    var currentIntervalRemainingPercent: Double?
    var currentWeeklyRemainingPercent: Double?

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case currentIntervalTotalCount = "current_interval_total_count"
        case currentIntervalUsageCount = "current_interval_usage_count"
        case modelName = "model_name"
        case currentWeeklyTotalCount = "current_weekly_total_count"
        case currentWeeklyUsageCount = "current_weekly_usage_count"
        case weeklyStartTime = "weekly_start_time"
        case weeklyEndTime = "weekly_end_time"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try container.decodeLossyDouble(forKey: .startTime)
        endTime = try container.decodeLossyDouble(forKey: .endTime)
        currentIntervalTotalCount = try container.decodeLossyDouble(
            forKey: .currentIntervalTotalCount
        )
        currentIntervalUsageCount = try container.decodeLossyDouble(
            forKey: .currentIntervalUsageCount
        )
        modelName = (try? container.decode(String.self, forKey: .modelName)) ?? "unknown"
        currentWeeklyTotalCount = try container.decodeLossyDouble(
            forKey: .currentWeeklyTotalCount
        )
        currentWeeklyUsageCount = try container.decodeLossyDouble(
            forKey: .currentWeeklyUsageCount
        )
        weeklyStartTime = try container.decodeLossyDouble(forKey: .weeklyStartTime)
        weeklyEndTime = try container.decodeLossyDouble(forKey: .weeklyEndTime)
        currentIntervalRemainingPercent = try? container.decodeLossyDouble(
            forKey: .currentIntervalRemainingPercent
        )
        currentWeeklyRemainingPercent = try? container.decodeLossyDouble(
            forKey: .currentWeeklyRemainingPercent
        )
    }
}

struct MiniMaxQuotaWindow: Equatable {
    var providerID: String
    var providerDisplayName: String
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

    init(
        providerID: String = "minimax",
        providerDisplayName: String = "MiniMax",
        modelName: String,
        intervalUsedCount: Double,
        intervalTotalCount: Double,
        intervalUsedPercent: Double,
        intervalRemainingPercent: Double?,
        intervalStartAt: Date,
        intervalResetAt: Date,
        weeklyUsedCount: Double,
        weeklyTotalCount: Double,
        weeklyUsedPercent: Double,
        weeklyRemainingPercent: Double?,
        weeklyStartAt: Date,
        weeklyResetAt: Date
    ) {
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.modelName = modelName
        self.intervalUsedCount = intervalUsedCount
        self.intervalTotalCount = intervalTotalCount
        self.intervalUsedPercent = intervalUsedPercent
        self.intervalRemainingPercent = intervalRemainingPercent
        self.intervalStartAt = intervalStartAt
        self.intervalResetAt = intervalResetAt
        self.weeklyUsedCount = weeklyUsedCount
        self.weeklyTotalCount = weeklyTotalCount
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyStartAt = weeklyStartAt
        self.weeklyResetAt = weeklyResetAt
    }
}

extension MiniMaxQuotaItem {
    func quotaWindow(
        providerID: String = "minimax",
        providerDisplayName: String = "MiniMax"
    ) -> MiniMaxQuotaWindow {
        MiniMaxQuotaWindow(
            providerID: providerID,
            providerDisplayName: providerDisplayName,
            modelName: modelName,
            intervalUsedCount: currentIntervalUsageCount,
            intervalTotalCount: currentIntervalTotalCount,
            intervalUsedPercent: Self.usedPercent(
                used: currentIntervalUsageCount,
                total: currentIntervalTotalCount,
                remainingPercent: currentIntervalRemainingPercent
            ),
            intervalRemainingPercent: currentIntervalRemainingPercent,
            intervalStartAt: Self.date(milliseconds: startTime),
            intervalResetAt: Self.date(milliseconds: endTime),
            weeklyUsedCount: currentWeeklyUsageCount,
            weeklyTotalCount: currentWeeklyTotalCount,
            weeklyUsedPercent: Self.usedPercent(
                used: currentWeeklyUsageCount,
                total: currentWeeklyTotalCount,
                remainingPercent: currentWeeklyRemainingPercent
            ),
            weeklyRemainingPercent: currentWeeklyRemainingPercent,
            weeklyStartAt: Self.date(milliseconds: weeklyStartTime),
            weeklyResetAt: Self.date(milliseconds: weeklyEndTime)
        )
    }

    private static func usedPercent(used: Double, total: Double, remainingPercent: Double?) -> Double {
        if total > 0 {
            return min(max((used / total) * 100, 0), 100)
        }
        if let remainingPercent {
            return min(max(100 - remainingPercent, 0), 100)
        }
        return 0
    }

    private static func date(milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

struct MiniMaxQuotaClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func fetch(apiKey: String) async throws -> MiniMaxQuotaResponse {
        guard let url = URL(string: MiniMaxUsageSnapshot.tokenPlanURL) else {
            throw MiniMaxQuotaClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MiniMaxQuotaClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MiniMaxQuotaClientError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }
        return try JSONDecoder().decode(MiniMaxQuotaResponse.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "MiniMax returned an error without a JSON message."
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String { return message }
        if let msg = object["msg"] as? String { return msg }
        if let base = object["base_resp"] as? [String: Any], let status = base["status_msg"] as? String {
            return status
        }
        return "MiniMax returned an error without a JSON message."
    }
}

enum MiniMaxQuotaClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "MiniMax quota refresh failed: invalid endpoint URL."
        case .invalidResponse: "MiniMax quota refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message): "MiniMax quota refresh failed with HTTP \(status): \(message)"
        }
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
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected a numeric value."
        )
    }
}
