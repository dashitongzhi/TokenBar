import Foundation

struct OpenAIUsageSnapshot: Equatable {
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

enum OpenAIUsageRefreshResult: Equatable {
    case success(OpenAIUsageSnapshot)
    case unavailable(String)
    case failure(String)
}

struct OpenAIUsageService {
    private let session: URLSession
    private let calendar: Calendar

    init(session: URLSession = .shared, calendar: Calendar = .current) {
        self.session = session
        self.calendar = calendar
    }

    func refresh() async -> OpenAIUsageRefreshResult {
        guard let adminKey = await openAIAdminKey() else {
            return .unavailable("Set OPENAI_ADMIN_KEY in the app environment or save it to TokenBar Keychain to enable live OpenAI organization usage.")
        }

        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now.addingTimeInterval(30 * 86_400)
        let dayCount = max(calendar.dateComponents([.day], from: monthStart, to: now).day ?? 0, 0) + 1
        let limit = min(max(dayCount, 1), 31)
        let startTime = Int(monthStart.timeIntervalSince1970)
        let endTime = Int(now.timeIntervalSince1970)

        async let usageResponse = paginatedRequest(
            OpenAIUsageResponse.self,
            path: "/v1/organization/usage/completions",
            queryItems: [
                URLQueryItem(name: "start_time", value: "\(startTime)"),
                URLQueryItem(name: "end_time", value: "\(endTime)"),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ],
            adminKey: adminKey
        )
        async let costsResponse = paginatedRequest(
            OpenAICostsResponse.self,
            path: "/v1/organization/costs",
            queryItems: [
                URLQueryItem(name: "start_time", value: "\(startTime)"),
                URLQueryItem(name: "end_time", value: "\(endTime)"),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ],
            adminKey: adminKey
        )

        do {
            let (usage, costs) = try await (usageResponse, costsResponse)
            return .success(snapshot(from: usage, costs: costs, now: now, resetAt: nextMonth))
        } catch let error as OpenAIUsageError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("OpenAI usage refresh failed: \(error.localizedDescription)")
        }
    }

    private func paginatedRequest<T: OpenAIPageResponse>(_ type: T.Type, path: String, queryItems: [URLQueryItem], adminKey: String) async throws -> T {
        var items = queryItems
        var response = try await request(type, path: path, queryItems: items, adminKey: adminKey)
        var pagesSeen = 1

        while let nextPage = response.nextPage, nextPage.isEmpty == false, pagesSeen < 20 {
            items.removeAll { $0.name == "page" }
            items.append(URLQueryItem(name: "page", value: nextPage))
            let nextResponse = try await request(type, path: path, queryItems: items, adminKey: adminKey)
            response.data.append(contentsOf: nextResponse.data)
            response.nextPage = nextResponse.nextPage
            pagesSeen += 1
        }

        return response
    }

    private func request<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], adminKey: String) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openai.com"
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OpenAIUsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIUsageError.httpStatus(http.statusCode, OpenAIUsageService.errorMessage(from: data))
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func snapshot(from usage: OpenAIUsageResponse, costs: OpenAICostsResponse, now: Date, resetAt: Date) -> OpenAIUsageSnapshot {
        let sortedUsageBuckets = usage.data.sorted { $0.startTime < $1.startTime }
        var cumulativeTokens = 0.0
        var tokensToday = 0.0
        var requestsMonth = 0
        var requestsToday = 0
        let todayStart = calendar.startOfDay(for: now)
        let history = sortedUsageBuckets.map { bucket in
            let bucketTokens = bucket.results.reduce(0.0) { total, result in
                total + result.tokenTotal
            }
            let bucketRequests = bucket.results.reduce(0) { $0 + ($1.numModelRequests ?? 0) }
            cumulativeTokens += bucketTokens
            requestsMonth += bucketRequests
            let timestamp = Date(timeIntervalSince1970: TimeInterval(bucket.startTime))
            if timestamp >= todayStart {
                tokensToday += bucketTokens
                requestsToday += bucketRequests
            }
            return UsagePoint(timestamp: timestamp, value: cumulativeTokens)
        }

        var currency = "usd"
        var spendToday = 0.0
        let spendMonth = costs.data.reduce(0.0) { total, bucket in
            let bucketSpend = bucket.results.reduce(0.0) { subtotal, result in
                if let bucketCurrency = result.amount?.currency, bucketCurrency.isEmpty == false {
                    currency = bucketCurrency
                }
                return subtotal + (result.amount?.value ?? 0)
            }
            if Date(timeIntervalSince1970: TimeInterval(bucket.startTime)) >= todayStart {
                spendToday += bucketSpend
            }
            return total + bucketSpend
        }

        return OpenAIUsageSnapshot(
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

    private func openAIAdminKey() async -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in ["OPENAI_ADMIN_KEY", "TOKENBAR_OPENAI_ADMIN_KEY"] {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }

        for keyName in ["OPENAI_ADMIN_KEY", "TOKENBAR_OPENAI_ADMIN_KEY", "openai.admin_key", "openai.adminKey"] {
            if let value = try? await KeychainService.shared.retrieve(key: keyName) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }

        return nil
    }

    private static func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return "OpenAI returned an error without a JSON message."
        }
        return message
    }
}

private nonisolated protocol OpenAIPageResponse: Decodable {
    associatedtype Bucket

    var data: [Bucket] { get set }
    var nextPage: String? { get set }
}

private enum OpenAIUsageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "OpenAI usage refresh failed: invalid endpoint URL."
        case .invalidResponse:
            "OpenAI usage refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message):
            "OpenAI usage refresh failed with HTTP \(status): \(message)"
        }
    }
}

private nonisolated struct OpenAIUsageResponse: OpenAIPageResponse {
    var data: [OpenAIUsageBucket]
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextPage = "next_page"
    }
}

private nonisolated struct OpenAIUsageBucket: Decodable {
    var startTime: Int
    var results: [OpenAIUsageResult]

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case results
    }
}

private nonisolated struct OpenAIUsageResult: Decodable {
    var inputTokens: Int?
    var outputTokens: Int?
    var inputAudioTokens: Int?
    var outputAudioTokens: Int?
    var numModelRequests: Int?

    var tokenTotal: Double {
        Double(inputTokens ?? 0)
        + Double(outputTokens ?? 0)
        + Double(inputAudioTokens ?? 0)
        + Double(outputAudioTokens ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputAudioTokens = "input_audio_tokens"
        case outputAudioTokens = "output_audio_tokens"
        case numModelRequests = "num_model_requests"
    }
}

private nonisolated struct OpenAICostsResponse: OpenAIPageResponse {
    var data: [OpenAICostBucket]
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextPage = "next_page"
    }
}

private nonisolated struct OpenAICostBucket: Decodable {
    var startTime: Int
    var results: [OpenAICostResult]

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case results
    }
}

private nonisolated struct OpenAICostResult: Decodable {
    var amount: OpenAICostAmount?
}

private nonisolated struct OpenAICostAmount: Decodable {
    var value: Double?
    var currency: String?
}
