import Foundation

@MainActor
protocol LocalAPIApplicationState: AnyObject {
    func policyJSON() throws -> Data
    func policyDecisionJSON(input: PolicyEvaluationInput) throws -> Data
    func ingestLocalAgentUsageJSON(input: LocalAgentUsageIngest) throws -> Data
    func ingestClaudeStatuslineJSON(data: Data) throws -> Data
    func recordSmartRoutingRunJSON(input: SmartRoutingRunInput) throws -> Data
    func smartRoutingStatsJSON() throws -> Data
    func mcpSnapshotJSON(filteredProviderID: String?) throws -> Data
    func paceJSON(providerID: String) throws -> Data
}

nonisolated final class LocalAPIApplication: @unchecked Sendable {
    private let state: any LocalAPIApplicationState
    private let authorizationToken: @Sendable () -> String

    init(
        state: any LocalAPIApplicationState,
        authorizationToken: @escaping @Sendable () -> String
    ) {
        self.state = state
        self.authorizationToken = authorizationToken
    }

    func handle(_ request: LocalAPIRequest?) async -> LocalAPIResponse {
        guard let request else {
            return .error("bad_request", statusCode: 400, reason: "Bad Request")
        }

        guard LocalAPIHTTPCodec.isAllowedHost(request.host) else {
            return .error("host_not_allowed", statusCode: 403, reason: "Forbidden")
        }

        guard LocalAPIHTTPCodec.isAllowedOrigin(request.origin) else {
            return .error("origin_not_allowed", statusCode: 403, reason: "Forbidden")
        }

        if request.method == "OPTIONS" {
            return .empty(
                statusCode: 204,
                reason: "No Content",
                headers: [
                    "Access-Control-Allow-Headers": "Authorization, Content-Type",
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                    "Access-Control-Max-Age": "600"
                ]
            )
        }

        if request.path == "/health" {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            return .json(Data(
                #"{"status":"ok","service":"TokenBar","version":"1.0","positioning":"local_ai_agent_policy_guard"}"#.utf8
            ))
        }

        guard isAuthorized(request) else {
            return .error(
                "unauthorized",
                statusCode: 401,
                reason: "Unauthorized",
                headers: ["WWW-Authenticate": #"Bearer realm="TokenBar Local API""#]
            )
        }

        switch (request.method, request.path) {
        case ("GET", "/policy"):
            return await json { try await self.state.policyJSON() }
        case (_, "/policy"):
            return methodNotAllowed(["GET"])

        case ("POST", "/policy/evaluate"):
            guard let input: PolicyEvaluationInput = decode(request.body) else {
                return .error("invalid_policy_input", statusCode: 400, reason: "Bad Request")
            }
            return await json { try await self.state.policyDecisionJSON(input: input) }
        case (_, "/policy/evaluate"):
            return methodNotAllowed(["POST"])

        case ("POST", "/usage/ingest"):
            guard let input: LocalAgentUsageIngest = decode(request.body) else {
                return .error("invalid_local_usage_input", statusCode: 400, reason: "Bad Request")
            }
            return await json { try await self.state.ingestLocalAgentUsageJSON(input: input) }
        case (_, "/usage/ingest"):
            return methodNotAllowed(["POST"])

        case ("POST", "/usage/claude-statusline"):
            return await json { try await self.state.ingestClaudeStatuslineJSON(data: request.body) }
        case (_, "/usage/claude-statusline"):
            return methodNotAllowed(["POST"])

        case ("POST", "/routing/runs"):
            guard let input: SmartRoutingRunInput = decode(request.body) else {
                return .error("invalid_smart_routing_run_input", statusCode: 400, reason: "Bad Request")
            }
            return await json { try await self.state.recordSmartRoutingRunJSON(input: input) }
        case (_, "/routing/runs"):
            return methodNotAllowed(["POST"])

        case ("GET", "/routing/stats"):
            return await json { try await self.state.smartRoutingStatsJSON() }
        case (_, "/routing/stats"):
            return methodNotAllowed(["GET"])

        case ("GET", "/quotas"):
            return await json { try await self.state.mcpSnapshotJSON(filteredProviderID: nil) }
        case (_, "/quotas"):
            return methodNotAllowed(["GET"])

        default:
            return await handleParameterizedRoute(request)
        }
    }

    private func handleParameterizedRoute(_ request: LocalAPIRequest) async -> LocalAPIResponse {
        if request.path.hasPrefix("/quotas/") {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            guard let provider = decodedPathSegment(
                String(request.path.dropFirst("/quotas/".count))
            ) else {
                return .error("invalid_provider_id", statusCode: 400, reason: "Bad Request")
            }
            return await json { try await self.state.mcpSnapshotJSON(filteredProviderID: provider) }
        }

        if request.path.hasPrefix("/pace/") {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            guard let provider = decodedPathSegment(
                String(request.path.dropFirst("/pace/".count))
            ) else {
                return .error("invalid_provider_id", statusCode: 400, reason: "Bad Request")
            }
            return await json { try await self.state.paceJSON(providerID: provider) }
        }

        return .error("not_found", statusCode: 404, reason: "Not Found")
    }

    private func methodNotAllowed(_ methods: [String]) -> LocalAPIResponse {
        .error(
            "method_not_allowed",
            statusCode: 405,
            reason: "Method Not Allowed",
            headers: ["Allow": methods.joined(separator: ", ")]
        )
    }

    private func json(_ body: () async throws -> Data) async -> LocalAPIResponse {
        do {
            let data = try await body()
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["error"] as? String == "provider_not_found" {
                return .error("provider_not_found", statusCode: 404, reason: "Not Found")
            }
            return .json(data)
        } catch {
            return .error(
                "payload_encoding_failed",
                statusCode: 500,
                reason: "Internal Server Error"
            )
        }
    }

    private func decodedPathSegment(_ rawValue: String) -> String? {
        guard rawValue.isEmpty == false,
              let decoded = rawValue.removingPercentEncoding,
              decoded.isEmpty == false,
              decoded.contains("/") == false else {
            return nil
        }
        return decoded
    }

    private func isAuthorized(_ request: LocalAPIRequest) -> Bool {
        guard let header = request.headers["authorization"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let pieces = header.split(separator: " ", maxSplits: 1).map(String.init)
        guard pieces.count == 2, pieces[0].lowercased() == "bearer" else { return false }
        return Self.secureCompare(pieces[1], authorizationToken())
    }

    private func decode<Value: Decodable>(_ data: Data) -> Value? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    private static func secureCompare(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }

        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}
