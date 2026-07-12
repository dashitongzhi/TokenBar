import Foundation
import Network
import OSLog

@MainActor
final class LocalAPIServer {
    static let shared = LocalAPIServer(appState: .shared)

    private nonisolated static let maximumHeaderBytes = 32 * 1024
    private nonisolated static let maximumBodyBytes = 1_024 * 1_024
    private nonisolated static let readTimeout: DispatchTimeInterval = .seconds(10)

    private let appState: AppState
    private let tokenStore = LocalAPITokenStore()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "TokenBar.LocalAPIServer")
    private let logger = Logger(subsystem: "Kral.TokenBar", category: "LocalAPIServer")

    private nonisolated static var isVerifyMode: Bool {
        CommandLine.arguments.contains("--tokenbar-verify-local-api")
    }

    private nonisolated static func verifyLog(_ message: String) {
        guard isVerifyMode else { return }
        FileHandle.standardError.write(Data("TokenBar verify mode: \(message)\n".utf8))
    }

    private struct HTTPRequest {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data

        var origin: String? {
            headers["origin"]
        }
    }

    private enum HTTPRequestReadResult {
        case incomplete
        case complete(HTTPRequest)
        case malformed
        case tooLarge
    }

    private nonisolated final class ConnectionReadDeadline: @unchecked Sendable {
        private let workItem: DispatchWorkItem

        init(connection: NWConnection) {
            workItem = DispatchWorkItem { connection.cancel() }
        }

        func schedule(on queue: DispatchQueue) {
            queue.asyncAfter(deadline: .now() + LocalAPIServer.readTimeout, execute: workItem)
        }

        func cancel() {
            workItem.cancel()
        }
    }

    private struct HTTPResponse {
        var statusCode: Int
        var reason: String
        var body: Data
        var headers: [String: String]

        static func json(_ body: Data, statusCode: Int = 200, reason: String = "OK", headers: [String: String] = [:]) -> HTTPResponse {
            HTTPResponse(statusCode: statusCode, reason: reason, body: body, headers: headers)
        }

        static func empty(statusCode: Int, reason: String, headers: [String: String] = [:]) -> HTTPResponse {
            HTTPResponse(statusCode: statusCode, reason: reason, body: Data(), headers: headers)
        }

        static func error(_ code: String, statusCode: Int, reason: String, headers: [String: String] = [:]) -> HTTPResponse {
            let payload = ["error": code]
            let body = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data(#"{"error":"unknown"}"#.utf8)
            return HTTPResponse(statusCode: statusCode, reason: reason, body: body, headers: headers)
        }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func syncWithPreference(port: UInt16 = 3847) {
        if appState.localAPIEnabled {
            start(port: port)
        } else {
            stop(disabled: true)
        }
    }

    func start(port: UInt16 = 3847) {
        guard appState.localAPIEnabled else {
            stop(disabled: true)
            return
        }
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            appState.setLocalAPIStatus(.failed("Invalid port \(port)"))
            return
        }
        appState.setLocalAPIStatus(.starting(port: port))
        do {
            Self.verifyLog("local API start requested on port \(port)")
            _ = tokenStore.token()
            Self.verifyLog("local API token ready")
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: endpointPort)
            let listener = try NWListener(using: parameters)
            Self.verifyLog("local API listener created")
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Self.verifyLog("local API listener state \(state)")
                guard let self, let listener else { return }
                Task { @MainActor [self, listener] in
                    self.handle(state: state, port: port, listener: listener)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            Self.verifyLog("local API listener start submitted")
            self.listener = listener
        } catch {
            appState.setLocalAPIStatus(.failed(error.localizedDescription))
            print("TokenBar Local API failed to start: \(error)")
            Self.verifyLog("local API failed to start: \(error)")
        }
    }

    func stop(disabled: Bool = false) {
        listener?.cancel()
        listener = nil
        appState.setLocalAPIStatus(disabled ? .disabled : .stopped)
    }

    private nonisolated func handle(_ connection: NWConnection) {
        guard Self.isLoopbackEndpoint(connection.endpoint) else {
            connection.cancel()
            return
        }

        connection.start(queue: queue)
        let timeout = ConnectionReadDeadline(connection: connection)
        timeout.schedule(on: queue)
        receiveRequest(connection, buffer: Data(), timeout: timeout)
    }

    private nonisolated func receiveRequest(_ connection: NWConnection, buffer: Data, timeout: ConnectionReadDeadline) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                timeout.cancel()
                connection.cancel()
                return
            }
            guard error == nil else {
                timeout.cancel()
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            switch Self.readRequest(from: accumulated) {
            case .complete(let request):
                timeout.cancel()
                self.respond(to: connection, request: request, response: nil)
            case .malformed:
                timeout.cancel()
                self.respond(to: connection, request: nil, response: nil)
            case .tooLarge:
                timeout.cancel()
                self.respond(
                    to: connection,
                    request: nil,
                    response: .error("request_too_large", statusCode: 413, reason: "Payload Too Large")
                )
            case .incomplete where isComplete:
                timeout.cancel()
                self.respond(to: connection, request: nil, response: nil)
            case .incomplete:
                self.receiveRequest(connection, buffer: accumulated, timeout: timeout)
            }
        }
    }

    private nonisolated func respond(to connection: NWConnection, request: HTTPRequest?, response: HTTPResponse?) {
        Task { @MainActor in
            let routed = response ?? self.route(request: request)
            let data = self.httpResponse(response: routed, request: request)
            connection.send(content: data, completion: .contentProcessed { _ in
                self.queue.asyncAfter(deadline: .now() + 0.05) {
                    connection.cancel()
                }
            })
        }
    }

    private func handle(state: NWListener.State, port: UInt16, listener eventListener: NWListener?) {
        guard eventListener == nil || listener === eventListener else { return }

        switch state {
        case .ready:
            guard appState.localAPIEnabled else {
                stop(disabled: true)
                return
            }
            appState.setLocalAPIStatus(.running(port: port))
            logger.info("TokenBar Local API listening on 127.0.0.1:\(port, privacy: .public)")
        case .failed(let error):
            listener = nil
            appState.setLocalAPIStatus(.failed(error.localizedDescription))
            logger.error("TokenBar Local API listener failed: \(error.localizedDescription, privacy: .public)")
        case .cancelled:
            appState.setLocalAPIStatus(appState.localAPIEnabled ? .stopped : .disabled)
            logger.info("TokenBar Local API listener stopped")
        default:
            break
        }
    }

    private func route(request: HTTPRequest?) -> HTTPResponse {
        guard let request else {
            return .error("bad_request", statusCode: 400, reason: "Bad Request")
        }

        guard Self.isAllowedOrigin(request.origin) else {
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
            return .json(Data(#"{"status":"ok","service":"TokenBar","version":"1.0","positioning":"local_ai_agent_policy_guard"}"#.utf8))
        }

        guard isAuthorized(request) else {
            return .error(
                "unauthorized",
                statusCode: 401,
                reason: "Unauthorized",
                headers: ["WWW-Authenticate": #"Bearer realm="TokenBar Local API""#]
            )
        }

        if request.path == "/policy" {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            return .json(appState.policyJSON())
        }

        if request.path == "/policy/evaluate" {
            guard request.method == "POST" else { return methodNotAllowed(["POST"]) }
            guard let input = policyInput(from: request.body) else {
                return .error("invalid_policy_input", statusCode: 400, reason: "Bad Request")
            }
            return .json(appState.policyDecisionJSON(input: input))
        }

        if request.path == "/usage/ingest" {
            guard request.method == "POST" else { return methodNotAllowed(["POST"]) }
            guard let input = localAgentUsageInput(from: request.body) else {
                return .error("invalid_local_usage_input", statusCode: 400, reason: "Bad Request")
            }
            return .json(appState.ingestLocalAgentUsageJSON(input: input))
        }

        if request.path == "/usage/claude-statusline" {
            guard request.method == "POST" else { return methodNotAllowed(["POST"]) }
            return .json(appState.ingestClaudeStatuslineJSON(data: request.body))
        }

        if request.path == "/routing/runs" {
            guard request.method == "POST" else { return methodNotAllowed(["POST"]) }
            guard let input = smartRoutingRunInput(from: request.body) else {
                return .error("invalid_smart_routing_run_input", statusCode: 400, reason: "Bad Request")
            }
            return .json(appState.recordSmartRoutingRunJSON(input: input))
        }

        if request.path == "/routing/stats" {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            return .json(appState.smartRoutingStatsJSON())
        }

        if request.path == "/quotas" {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            return .json(appState.mcpSnapshotJSON())
        }

        if request.path.hasPrefix("/quotas/") {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            let provider = String(request.path.dropFirst("/quotas/".count))
            return .json(appState.mcpSnapshotJSON(filteredProviderID: provider))
        }

        if request.path.hasPrefix("/pace/") {
            guard request.method == "GET" else { return methodNotAllowed(["GET"]) }
            let provider = String(request.path.dropFirst("/pace/".count))
            return .json(appState.paceJSON(providerID: provider))
        }

        return .error("not_found", statusCode: 404, reason: "Not Found")
    }

    private func methodNotAllowed(_ methods: [String]) -> HTTPResponse {
        .error(
            "method_not_allowed",
            statusCode: 405,
            reason: "Method Not Allowed",
            headers: ["Allow": methods.joined(separator: ", ")]
        )
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let pieces = header.split(separator: " ", maxSplits: 1).map(String.init)
        guard pieces.count == 2, pieces[0].lowercased() == "bearer" else { return false }
        return Self.secureCompare(pieces[1], tokenStore.token())
    }

    private func policyInput(from data: Data) -> PolicyEvaluationInput? {
        try? JSONDecoder.tokenBar.decode(PolicyEvaluationInput.self, from: data)
    }

    private func localAgentUsageInput(from data: Data) -> LocalAgentUsageIngest? {
        return try? JSONDecoder.tokenBar.decode(LocalAgentUsageIngest.self, from: data)
    }

    private func smartRoutingRunInput(from data: Data) -> SmartRoutingRunInput? {
        return try? JSONDecoder.tokenBar.decode(SmartRoutingRunInput.self, from: data)
    }

    private nonisolated static func readRequest(from data: Data) -> HTTPRequestReadResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else {
            return data.count > maximumHeaderBytes ? .tooLarge : .incomplete
        }
        let headerData = data[..<range.lowerBound]
        guard headerData.count <= maximumHeaderBytes,
              let headerText = String(data: headerData, encoding: .utf8) else {
            return .malformed
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return .malformed }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              ["HTTP/1.0", "HTTP/1.1"].contains(parts[2]),
              parts[1].hasPrefix("/") else {
            return .malformed
        }

        var path = parts[1]
        if let queryStart = path.firstIndex(of: "?") {
            path = String(path[..<queryStart])
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard line.isEmpty == false, let separator = line.firstIndex(of: ":") else { return .malformed }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false, headers[name] == nil else { return .malformed }
            headers[name] = value
        }

        guard headers["transfer-encoding"] == nil else { return .malformed }
        let declaredBodyLength: Int
        if let contentLength = headers["content-length"] {
            guard contentLength.isEmpty == false,
                  contentLength.allSatisfy({ $0.isNumber }),
                  let parsedLength = Int(contentLength),
                  parsedLength <= maximumBodyBytes else {
                return .tooLarge
            }
            declaredBodyLength = parsedLength
        } else {
            declaredBodyLength = 0
        }

        let body = Data(data[range.upperBound...])
        guard body.count <= declaredBodyLength else { return .malformed }
        guard body.count == declaredBodyLength else { return .incomplete }

        return .complete(HTTPRequest(
            method: parts[0].uppercased(),
            path: path,
            headers: headers,
            body: body
        ))
    }

    private func httpResponse(response: HTTPResponse, request: HTTPRequest?) -> Data {
        var headers: [String: String] = [
            "Content-Length": "\(response.body.count)",
            "Connection": "close"
        ]
        if response.body.isEmpty == false {
            headers["Content-Type"] = "application/json; charset=utf-8"
        }
        response.headers.forEach { headers[$0.key] = $0.value }

        if let origin = request?.origin, Self.isAllowedOrigin(origin) {
            headers["Access-Control-Allow-Origin"] = origin
            headers["Vary"] = "Origin"
        }

        var headerLines = ["HTTP/1.1 \(response.statusCode) \(response.reason)"]
        headerLines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        headerLines.append("")
        headerLines.append("")

        var data = Data(headerLines.joined(separator: "\r\n").utf8)
        data.append(response.body)
        return data
    }

    private nonisolated static func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin, origin.isEmpty == false else { return true }
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return false
        }
        return (scheme == "http" || scheme == "https") && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private nonisolated static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .name(let name, _):
                return name == "localhost"
            case .ipv4(let address):
                return String(describing: address).hasPrefix("127.")
            case .ipv6(let address):
                return String(describing: address) == "::1"
            @unknown default:
                return false
            }
        case .service, .unix, .url, .opaque:
            return false
        @unknown default:
            return false
        }
    }

    private nonisolated static func secureCompare(_ lhs: String, _ rhs: String) -> Bool {
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
