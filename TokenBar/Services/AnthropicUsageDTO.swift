import Foundation

nonisolated protocol AnthropicPageResponse: Decodable {
    associatedtype Bucket

    var data: [Bucket] { get set }
    var hasMore: Bool? { get set }
    var nextPage: String? { get set }
}

nonisolated struct AnthropicUsageResponse: AnthropicPageResponse {
    var data: [AnthropicUsageBucket]
    var hasMore: Bool?
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

nonisolated struct AnthropicUsageBucket: Decodable {
    var startingAt: Date
    var endingAt: Date?
    var results: [AnthropicUsageResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

nonisolated struct AnthropicUsageResult: Decodable {
    var inputTokens: Double?
    var outputTokens: Double?
    var cacheCreationInputTokens: Double?
    var cacheCreation: AnthropicCacheCreation?
    var cacheReadInputTokens: Double?
    var uncachedInputTokens: Double?
    var requestCount: Int?
    var serverToolUse: AnthropicServerToolUse?

    var tokenTotal: Double {
        let cacheCreationTotal = cacheCreationInputTokens ?? cacheCreation?.tokenTotal ?? 0
        let fallbackInputTotal = (uncachedInputTokens ?? 0) + cacheCreationTotal + (cacheReadInputTokens ?? 0)
        let inputTotal = inputTokens ?? fallbackInputTotal
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

nonisolated struct AnthropicCacheCreation: Decodable {
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

nonisolated struct AnthropicServerToolUse: Decodable {
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

nonisolated struct AnthropicCostResponse: AnthropicPageResponse {
    var data: [AnthropicCostBucket]
    var hasMore: Bool?
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

nonisolated struct AnthropicCostBucket: Decodable {
    var startingAt: Date
    var endingAt: Date?
    var results: [AnthropicCostResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

nonisolated struct AnthropicCostResult: Decodable {
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

nonisolated struct AnthropicCostAmount: Decodable {
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
