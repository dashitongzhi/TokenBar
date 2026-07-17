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

struct CCSwitchMiniMaxQuotaResponse: Decodable {
    var modelRemains: [CCSwitchMiniMaxQuotaItem]
    var baseResp: CCSwitchMiniMaxBaseResponse?

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }
}

struct CCSwitchMiniMaxBaseResponse: Decodable {
    var statusCode: Int
    var statusMsg: String

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

struct CCSwitchMiniMaxQuotaItem: Decodable {
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
