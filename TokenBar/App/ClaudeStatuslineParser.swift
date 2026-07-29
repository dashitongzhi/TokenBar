import Foundation

enum ClaudeStatuslineParser {
    static func parse(_ data: Data) -> LocalAgentUsageIngest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let model = nestedString(object, path: ["model", "id"])
            ?? nestedString(object, path: ["model", "name"])
            ?? stringValue(forAnyKey: ["model_id", "modelId", "model"], in: object)
        let inputTokens = intValue(forAnyKey: ["input_tokens", "inputTokens"], in: object)
        let outputTokens = intValue(forAnyKey: ["output_tokens", "outputTokens"], in: object)
        let cacheCreationTokens = intValue(forAnyKey: ["cache_creation_input_tokens", "cacheCreationInputTokens"], in: object) ?? 0
        let cacheReadTokens = intValue(forAnyKey: ["cache_read_input_tokens", "cacheReadInputTokens"], in: object) ?? 0
        let explicitTotalTokens = intValue(forAnyKey: ["total_tokens", "totalTokens", "tokens_used", "tokensUsed"], in: object)
        let computedTotalTokens = [inputTokens, outputTokens].compactMap { $0 }.reduce(0, +) + cacheCreationTokens + cacheReadTokens
        let totalTokens = explicitTotalTokens ?? (computedTotalTokens > 0 ? computedTotalTokens : nil)
        let sessionID = stringValue(forAnyKey: ["session_id", "sessionId"], in: object)
        let transcriptPath = stringValue(forAnyKey: ["transcript_path", "transcriptPath"], in: object)
        let currentDirectory = nestedString(object, path: ["workspace", "current_dir"])
            ?? nestedString(object, path: ["workspace", "currentDirectory"])
            ?? stringValue(forAnyKey: ["current_dir", "currentDirectory", "cwd"], in: object)

        return LocalAgentUsageIngest(
            agent: .claudeCode,
            providerID: nil,
            model: model,
            workspaceID: nil,
            workspaceName: nil,
            workspacePath: currentDirectory,
            workspaceClient: nil,
            dailyBudget: nil,
            monthlyBudget: nil,
            maxEstimatedRunCost: nil,
            maxEstimatedTokens: nil,
            allowedProviderIDs: nil,
            blockedModels: nil,
            requireCompanyKey: nil,
            sessionID: sessionID,
            source: "Claude Code statusline",
            currentDirectory: currentDirectory,
            transcriptPath: transcriptPath,
            costUSD: doubleValue(forAnyKey: ["total_cost_usd", "totalCostUSD", "cost_usd", "costUSD"], in: object),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            contextWindowSize: intValue(forAnyKey: ["context_window_size", "contextWindowSize"], in: object),
            requestCount: intValue(forAnyKey: ["request_count", "requestCount"], in: object),
            occurredAt: dateValue(forAnyKey: ["timestamp", "occurred_at", "occurredAt"], in: object),
            rateLimitUsedPercentage: doubleValue(forAnyKey: ["used_percentage", "usedPercentage", "rate_limit_used_percentage", "rateLimitUsedPercentage"], in: object),
            rateLimitResetAt: dateValue(forAnyKey: ["reset_at", "resetAt", "rate_limit_reset_at", "rateLimitResetAt"], in: object),
            cumulative: true
        )
    }

    private static func nestedString(_ object: Any, path: [String]) -> String? {
        var cursor = object
        for key in path {
            guard let dictionary = cursor as? [String: Any], let next = dictionary[key] else { return nil }
            cursor = next
        }
        return cursor as? String
    }

    private static func stringValue(forAnyKey keys: [String], in object: Any) -> String? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        guard let string = value as? String else { return nil }
        return string.isEmpty ? nil : string
    }

    private static func intValue(forAnyKey keys: [String], in object: Any) -> Int? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite { return Int(exactly: double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(forAnyKey keys: [String], in object: Any) -> Double? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func dateValue(forAnyKey keys: [String], in object: Any) -> Date? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        if let date = value as? Date { return date }
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds) }
        guard let string = value as? String else { return nil }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        if let seconds = TimeInterval(string) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    private static func firstValue(forAnyKey keys: [String], in object: Any) -> Any? {
        for dictionary in candidateDictionaries(in: object) {
            for key in keys {
                if let value = dictionary[key] {
                    return value
                }
            }
        }
        return nil
    }

    /// Claude statusline payloads have used a small number of named
    /// containers over time. Search those in a fixed order instead of walking
    /// arbitrary dictionary values, whose iteration order can select an
    /// unrelated same-named field.
    private static func candidateDictionaries(in object: Any) -> [[String: Any]] {
        guard let root = object as? [String: Any] else { return [] }
        let containerPaths = [
            ["usage"],
            ["cost"],
            ["context_window"],
            ["contextWindow"],
            ["rate_limits"],
            ["rateLimits"],
            ["workspace"],
            ["session"],
            ["data"],
            ["data", "usage"]
        ]
        return [root] + containerPaths.compactMap { path in
            var cursor: Any = root
            for key in path {
                guard let dictionary = cursor as? [String: Any],
                      let next = dictionary[key] else {
                    return nil
                }
                cursor = next
            }
            return cursor as? [String: Any]
        }
    }
}
