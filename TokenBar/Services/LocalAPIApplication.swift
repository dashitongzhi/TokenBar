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

@MainActor
final class LocalAPIApplication {
    private let state: any LocalAPIApplicationState
    private let authorizationToken: () -> String

    init(
        state: any LocalAPIApplicationState,
        authorizationToken: @escaping () -> String
    ) {
        self.state = state
        self.authorizationToken = authorizationToken
    }

    func handle(_ request: LocalAPIRequest?) -> LocalAPIResponse {
        guard let request else {
            return .error("bad_request", statusCode: 400, reason: "Bad Request")
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
            return json { try state.policyJSON() }
        case (_, "/policy"):
            return methodNotAllowed(["GET"])

        case ("POST", "/policy/evaluate"):
            guard let input: PolicyEvaluationInput = decode(request.body) else {
                return .error("invalid_policy_input", statusCode: 400, reason: "Bad Request")
            }
            return json { try state.policyDecisionJSON(input: input) }
        case (_, "/policy/evaluate"):
            return methodNotAllowed(["POST"])

        case ("POST", "/usage/ingest"):
            guard let input: LocalAgentUsageIngest = decode(request.body) else {
                return .error("invalid_local_usage_input", statusCode: 400, reason: "Bad Request")
            }
            return json { try state.ingestLocalAgentUsageJSON(input: input) }
        case (_, "/usage/ingest"):
            return methodNotAllowed(["POST"])

        case ("POST", "/usage/claude-statusline"):
            return json { try state.ingestClaudeStatuslineJSON(data: request.body) }
        case (_, "/usage/claude-statusline"):
            return methodNotAllowed(["POST"])

        case ("POST", "/routing/runs"):
            guard let input: SmartRoutingRunInput = decode(request.body) else {
                return .error("invalid_smart_routing_run_input", statusCode: 400, reason: "Bad Request")
            }
            return json { try state.recordSmartRoutingRunJSON(input: input) }
        case (_, "/routing/runs"):
            return methodNotAllowed(["POST"])

        case ("GET", "/routing/stats"):
            return json { try state.smartRoutingStatsJSON() }
        case (_, "/routing/stats"):
            return methodNotAllowed(["GET"])

        case ("GET", "/quotas"):
            return json { try state.mcpSnapshotJSON(filteredProviderID: nil) }
        case (_, "/quotas"):
            return methodNotAllowed(["GET"])

        default:
            return handleParameterizedRoute(request)
        }
    }

    private func handleParameterizedRoute(_ request: LocalAPIRequest) -> LocalAPIResponse {
        if request.path.hasPrefix("/quotas/") {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            let provider = String(request.path.dropFirst("/quotas/".count))
            return json { try state.mcpSnapshotJSON(filteredProviderID: provider) }
        }

        if request.path.hasPrefix("/pace/") {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            let provider = String(request.path.dropFirst("/pace/".count))
            return json { try state.paceJSON(providerID: provider) }
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

    private func json(_ body: () throws -> Data) -> LocalAPIResponse {
        do {
            return .json(try body())
        } catch {
            return .error(
                "payload_encoding_failed",
                statusCode: 500,
                reason: "Internal Server Error"
            )
        }
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
