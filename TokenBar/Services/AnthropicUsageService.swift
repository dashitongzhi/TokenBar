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
    private let session: URLSession
    private let calendar: Calendar

    init(session: URLSession = .shared, calendar: Calendar = .current) {
        self.session = session
        self.calendar = calendar
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

        async let usageResponse = paginatedRequest(
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
        async let costResponse = paginatedRequest(
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
            return .success(snapshot(from: usage, costs: cost, now: now, resetAt: nextMonth))
        } catch let error as AnthropicUsageError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("Anthropic usage refresh failed: \(error.localizedDescription)")
        }
    }

    private func paginatedRequest<T: AnthropicPageResponse>(_ type: T.Type, path: String, queryItems: [URLQueryItem], adminKey: String) async throws -> T {
        var items = queryItems
        var response = try await request(type, path: path, queryItems: items, adminKey: adminKey)
        var pagesSeen = 1

        while response.hasMore == true, let nextPage = response.nextPage, nextPage.isEmpty == false, pagesSeen < 20 {
            items.removeAll { $0.name == "page" }
            items.append(URLQueryItem(name: "page", value: nextPage))
            let nextResponse = try await request(type, path: path, queryItems: items, adminKey: adminKey)
            response.data.append(contentsOf: nextResponse.data)
            response.hasMore = nextResponse.hasMore
            response.nextPage = nextResponse.nextPage
            pagesSeen += 1
        }

        return response
    }

    private func request<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], adminKey: String) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.anthropic.com"
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw AnthropicUsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicUsageError.httpStatus(http.statusCode, AnthropicUsageService.errorMessage(from: data))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeAPIDate)
        return try decoder.decode(type, from: data)
    }

    private func snapshot(from usage: AnthropicUsageResponse, costs: AnthropicCostResponse, now: Date, resetAt: Date) -> AnthropicUsageSnapshot {
        let sortedUsageBuckets = usage.data.sorted { $0.startingAt < $1.startingAt }
        var cumulativeTokens = 0.0
        var tokensToday = 0.0
        var requestsMonth = 0
        var requestsToday = 0
        let todayStart = calendar.startOfDay(for: now)

        let history = sortedUsageBuckets.map { bucket in
            let bucketTokens = bucket.results.reduce(0.0) { $0 + $1.tokenTotal }
            let bucketRequests = bucket.results.reduce(0) { $0 + ($1.requestCount ?? 0) }
            cumulativeTokens += bucketTokens
            requestsMonth += bucketRequests
            if bucket.startingAt >= todayStart {
                tokensToday += bucketTokens
                requestsToday += bucketRequests
            }
            return UsagePoint(timestamp: bucket.startingAt, value: cumulativeTokens)
        }

        var currency = "usd"
        var spendToday = 0.0
        let spendMonth = costs.data.reduce(0.0) { total, bucket in
            let bucketSpend = bucket.results.reduce(0.0) { subtotal, result in
                if let resultCurrency = result.currency?.trimmingCharacters(in: .whitespacesAndNewlines), resultCurrency.isEmpty == false {
                    currency = resultCurrency
                }
                return subtotal + result.amountMajorUnits
            }
            if bucket.startingAt >= todayStart {
                spendToday += bucketSpend
            }
            return total + bucketSpend
        }

        return AnthropicUsageSnapshot(
            tokenTotal: cumulativeTokens,
            tokenToday: tokensToday,
            requestCountMonth: requestsMonth,
            requestCountToday: requestsToday,
            spendToday: spendToday,
            spendMonth: spendMonth,
            currency: currency,
            resetAt: resetAt,
            fetchedAt: now,
            history: history
        )
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

    private nonisolated static func decodeAPIDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let internetDateFormatter = ISO8601DateFormatter()
        internetDateFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetDateFormatter.date(from: value) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Anthropic date: \(value)")
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Anthropic returned an error without a JSON message."
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        return "Anthropic returned an error without a JSON message."
    }
}

private nonisolated protocol AnthropicPageResponse: Decodable {
    associatedtype Bucket

    var data: [Bucket] { get set }
    var hasMore: Bool? { get set }
    var nextPage: String? { get set }
}

private enum AnthropicUsageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Anthropic usage refresh failed: invalid endpoint URL."
        case .invalidResponse:
            "Anthropic usage refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message):
            "Anthropic usage refresh failed with HTTP \(status): \(message)"
        }
    }
}

private nonisolated struct AnthropicUsageResponse: AnthropicPageResponse {
    var data: [AnthropicUsageBucket]
    var hasMore: Bool?
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

private nonisolated struct AnthropicUsageBucket: Decodable {
    var startingAt: Date
    var endingAt: Date?
    var results: [AnthropicUsageResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

private nonisolated struct AnthropicUsageResult: Decodable {
    var inputTokens: Double?
    var outputTokens: Double?
    var cacheCreationInputTokens: Double?
    var cacheCreation: AnthropicCacheCreation?
    var cacheReadInputTokens: Double?
    var uncachedInputTokens: Double?
    var requestCount: Int?
    var serverToolUse: AnthropicServerToolUse?

    var tokenTotal: Double {
        let inputTotal = inputTokens ?? ((uncachedInputTokens ?? 0) + (cacheCreationInputTokens ?? cacheCreation?.tokenTotal ?? 0) + (cacheReadInputTokens ?? 0))
        return inputTotal + (outputTokens ?? 0) + (serverToolUse?.tokenTotal ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheCreation = "cache_creation"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case uncachedInputTokens = "uncached_input_tokens"
        case requestCount = "request_count"
        case serverToolUse = "server_tool_use"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeLossyDoubleIfPresent(forKey: .inputTokens)
        outputTokens = try container.decodeLossyDoubleIfPresent(forKey: .outputTokens)
        cacheCreationInputTokens = try container.decodeLossyDoubleIfPresent(forKey: .cacheCreationInputTokens)
        cacheCreation = try container.decodeIfPresent(AnthropicCacheCreation.self, forKey: .cacheCreation)
        cacheReadInputTokens = try container.decodeLossyDoubleIfPresent(forKey: .cacheReadInputTokens)
        uncachedInputTokens = try container.decodeLossyDoubleIfPresent(forKey: .uncachedInputTokens)
        requestCount = try container.decodeLossyIntIfPresent(forKey: .requestCount)
        serverToolUse = try container.decodeIfPresent(AnthropicServerToolUse.self, forKey: .serverToolUse)
    }
}

private nonisolated struct AnthropicCacheCreation: Decodable {
    var ephemeral1hInputTokens: Double?
    var ephemeral5mInputTokens: Double?

    var tokenTotal: Double {
        (ephemeral1hInputTokens ?? 0) + (ephemeral5mInputTokens ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ephemeral1hInputTokens = try container.decodeLossyDoubleIfPresent(forKey: .ephemeral1hInputTokens)
        ephemeral5mInputTokens = try container.decodeLossyDoubleIfPresent(forKey: .ephemeral5mInputTokens)
    }
}

private nonisolated struct AnthropicServerToolUse: Decodable {
    var inputTokens: Double?
    var outputTokens: Double?

    var tokenTotal: Double {
        (inputTokens ?? 0) + (outputTokens ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeLossyDoubleIfPresent(forKey: .inputTokens)
        outputTokens = try container.decodeLossyDoubleIfPresent(forKey: .outputTokens)
    }
}

private nonisolated struct AnthropicCostResponse: AnthropicPageResponse {
    var data: [AnthropicCostBucket]
    var hasMore: Bool?
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

private nonisolated struct AnthropicCostBucket: Decodable {
    var startingAt: Date
    var endingAt: Date?
    var results: [AnthropicCostResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

private nonisolated struct AnthropicCostResult: Decodable {
    var amount: AnthropicCostAmount?
    var amountNumber: Double?
    var currency: String?

    var amountMajorUnits: Double {
        let minorUnits = amount?.value ?? amountNumber ?? 0
        return minorUnits / 100
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try? container.decode(AnthropicCostAmount.self, forKey: .amount)
        amountNumber = try container.decodeLossyDoubleIfPresent(forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? amount?.currency
    }
}

private nonisolated struct AnthropicCostAmount: Decodable {
    var value: Double?
    var currency: String?

    enum CodingKeys: String, CodingKey {
        case value
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeLossyDoubleIfPresent(forKey: .value)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeLossyDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    nonisolated func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}
