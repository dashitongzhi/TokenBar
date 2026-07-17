import Foundation

enum AgentProvider: String, Codable {
    case codex
}

struct PolicyEvaluationInput: Codable, Equatable {
    var agent: AgentProvider
    var workspaceID: String
    var providerID: String
    var model: String
    var estimatedCost: Double
    var estimatedTokens: Int
    var intent: String
}

struct LocalAgentUsageIngest: Codable {}
struct SmartRoutingRunInput: Codable {}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class FakeLocalAPIState: LocalAPIApplicationState {
    private(set) var lastQuotaProviderID: String?
    private(set) var lastPaceProviderID: String?
    private(set) var evaluatedPolicyInput: PolicyEvaluationInput?

    func policyJSON() -> Data {
        Data(#"{"kind":"policy"}"#.utf8)
    }

    func policyDecisionJSON(input: PolicyEvaluationInput) -> Data {
        evaluatedPolicyInput = input
        return Data(#"{"kind":"decision"}"#.utf8)
    }

    func ingestLocalAgentUsageJSON(input: LocalAgentUsageIngest) -> Data {
        Data(#"{"kind":"usage"}"#.utf8)
    }

    func ingestClaudeStatuslineJSON(data: Data) -> Data {
        Data(#"{"kind":"claude"}"#.utf8)
    }

    func recordSmartRoutingRunJSON(input: SmartRoutingRunInput) -> Data {
        Data(#"{"kind":"routing-run"}"#.utf8)
    }

    func smartRoutingStatsJSON() -> Data {
        Data(#"{"kind":"routing-stats"}"#.utf8)
    }

    func mcpSnapshotJSON(filteredProviderID: String?) -> Data {
        lastQuotaProviderID = filteredProviderID
        return Data(#"{"kind":"quotas"}"#.utf8)
    }

    func paceJSON(providerID: String) -> Data {
        lastPaceProviderID = providerID
        return Data(#"{"kind":"pace"}"#.utf8)
    }
}

@main
@MainActor
struct VerifyLocalAPIApplication {
    static func main() throws {
        let token = "verification-token"
        let state = FakeLocalAPIState()
        let application = LocalAPIApplication(
            state: state,
            authorizationToken: { token }
        )

        try expect(application.handle(nil).statusCode == 400, "nil request must be rejected")

        let health = application.handle(request(method: "GET", path: "/health"))
        try expect(health.statusCode == 200, "health must remain unauthenticated")
        try expect(
            application.handle(request(method: "POST", path: "/health")).statusCode == 405,
            "health must reject unsupported methods"
        )

        let preflight = application.handle(request(
            method: "OPTIONS",
            path: "/quotas",
            origin: "http://localhost:4321"
        ))
        try expect(preflight.statusCode == 204, "local preflight must be accepted")

        let remoteOrigin = application.handle(request(
            method: "GET",
            path: "/health",
            origin: "https://example.com"
        ))
        try expect(remoteOrigin.statusCode == 403, "remote origins must be rejected")

        try expect(
            application.handle(request(method: "GET", path: "/quotas")).statusCode == 401,
            "protected routes must require a bearer token"
        )

        let quotas = application.handle(authorizedRequest(method: "GET", path: "/quotas", token: token))
        try expect(quotas.statusCode == 200, "authorized quota request must succeed")
        try expect(state.lastQuotaProviderID == nil, "all quotas must not set a provider filter")

        let providerQuotas = application.handle(
            authorizedRequest(method: "GET", path: "/quotas/openai", token: token)
        )
        try expect(providerQuotas.statusCode == 200, "provider quota request must succeed")
        try expect(state.lastQuotaProviderID == "openai", "provider quota route must preserve provider id")

        let pace = application.handle(
            authorizedRequest(method: "GET", path: "/pace/minimax", token: token)
        )
        try expect(pace.statusCode == 200, "provider pace request must succeed")
        try expect(state.lastPaceProviderID == "minimax", "pace route must preserve provider id")

        let policyInput = PolicyEvaluationInput(
            agent: .codex,
            workspaceID: "verification-workspace",
            providerID: "openai",
            model: "gpt-verification",
            estimatedCost: 0.25,
            estimatedTokens: 4_000,
            intent: "verification"
        )
        let policyBody = try JSONEncoder().encode(policyInput)
        let decision = application.handle(authorizedRequest(
            method: "POST",
            path: "/policy/evaluate",
            token: token,
            body: policyBody
        ))
        try expect(decision.statusCode == 200, "valid policy input must be routed")
        try expect(
            state.evaluatedPolicyInput == policyInput,
            "policy application seam must receive the decoded input"
        )

        let invalidDecision = application.handle(authorizedRequest(
            method: "POST",
            path: "/policy/evaluate",
            token: token,
            body: Data("{}".utf8)
        ))
        try expect(invalidDecision.statusCode == 400, "invalid policy input must be rejected")

        try verifyHTTPCodec()
        print("Verified Local API application routing, authorization, origin policy, and HTTP framing.")
    }

    private static func verifyHTTPCodec() throws {
        let raw = Data(
            "GET /quotas/openai?detail=1 HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer token\r\n\r\n".utf8
        )
        switch LocalAPIHTTPCodec.readRequest(from: raw) {
        case .complete(let parsed):
            try expect(parsed.method == "GET", "codec must normalize the method")
            try expect(parsed.path == "/quotas/openai", "codec must strip the query string")
            try expect(parsed.headers["authorization"] == "Bearer token", "codec must normalize header names")
        default:
            throw VerificationFailure(description: "complete HTTP request did not parse")
        }

        switch LocalAPIHTTPCodec.readRequest(from: Data("POST /policy HTTP/1.1\r\nContent-Length: 4\r\n\r\n{}".utf8)) {
        case .incomplete:
            break
        default:
            throw VerificationFailure(description: "partial HTTP body must remain incomplete")
        }

        switch LocalAPIHTTPCodec.readRequest(from: Data(
            "GET /health HTTP/1.1\r\nX-Test: one\r\nX-Test: two\r\n\r\n".utf8
        )) {
        case .malformed:
            break
        default:
            throw VerificationFailure(description: "duplicate headers must be rejected")
        }

        let response = LocalAPIHTTPCodec.responseData(
            response: .json(Data("{}".utf8)),
            request: request(method: "GET", path: "/health", origin: "http://127.0.0.1:3000")
        )
        let responseText = String(decoding: response, as: UTF8.self)
        try expect(
            responseText.contains("Access-Control-Allow-Origin: http://127.0.0.1:3000"),
            "allowed origin must be reflected in the response"
        )
    }

    private static func authorizedRequest(
        method: String,
        path: String,
        token: String,
        body: Data = Data()
    ) -> LocalAPIRequest {
        request(
            method: method,
            path: path,
            headers: ["authorization": "Bearer \(token)"],
            body: body
        )
    }

    private static func request(
        method: String,
        path: String,
        origin: String? = nil,
        headers: [String: String] = [:],
        body: Data = Data()
    ) -> LocalAPIRequest {
        var resolvedHeaders = headers
        if let origin {
            resolvedHeaders["origin"] = origin
        }
        return LocalAPIRequest(
            method: method,
            path: path,
            headers: resolvedHeaders,
            body: body
        )
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) throws {
        guard try condition() else {
            throw VerificationFailure(description: message)
        }
    }
}
