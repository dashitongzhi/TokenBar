import Foundation
import Network
import OSLog

@MainActor
final class LocalAPIServer {
    static let shared = LocalAPIServer(appState: .shared)

    private let appState: AppState
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "TokenBar.LocalAPIServer")
    private let logger = Logger(subsystem: "Kral.TokenBar", category: "LocalAPIServer")

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
            let listener = try NWListener(using: .tcp, on: endpointPort)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                Task { @MainActor [self, listener] in
                    self.handle(state: state, port: port, listener: listener)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            appState.setLocalAPIStatus(.failed(error.localizedDescription))
            print("TokenBar Local API failed to start: \(error)")
        }
    }

    func stop(disabled: Bool = false) {
        listener?.cancel()
        listener = nil
        appState.setLocalAPIStatus(disabled ? .disabled : .stopped)
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Task { @MainActor in
                let body = self.route(request: request)
                let response = self.httpResponse(body: body)
                connection.send(content: response, completion: .contentProcessed { _ in
                    self.queue.asyncAfter(deadline: .now() + 0.05) {
                        connection.cancel()
                    }
                })
            }
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

    private func route(request: String) -> Data {
        let firstLine = request.split(separator: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let path = parts.count >= 2 ? String(parts[1]) : "/health"

        if path == "/health" {
            return Data(#"{"status":"ok","service":"TokenBar","version":"1.0","positioning":"local_ai_agent_policy_guard"}"#.utf8)
        }

        if path == "/policy" {
            return appState.policyJSON()
        }

        if path == "/policy/evaluate" {
            guard let input = policyInput(from: request) else {
                return Data(#"{"error":"invalid_policy_input"}"#.utf8)
            }
            return appState.policyDecisionJSON(input: input)
        }

        if path == "/usage/ingest" {
            guard let input = localAgentUsageInput(from: request) else {
                return Data(#"{"error":"invalid_local_usage_input"}"#.utf8)
            }
            return appState.ingestLocalAgentUsageJSON(input: input)
        }

        if path == "/usage/claude-statusline" {
            guard let data = bodyData(from: request) else {
                return Data(#"{"error":"invalid_claude_statusline_input"}"#.utf8)
            }
            return appState.ingestClaudeStatuslineJSON(data: data)
        }

        if path == "/quotas" {
            return appState.mcpSnapshotJSON()
        }

        if path.hasPrefix("/quotas/") {
            let provider = String(path.dropFirst("/quotas/".count))
            return appState.mcpSnapshotJSON(filteredProviderID: provider)
        }

        if path.hasPrefix("/pace/") {
            let provider = String(path.dropFirst("/pace/".count))
            return appState.paceJSON(providerID: provider)
        }

        return Data(#"{"error":"not_found"}"#.utf8)
    }

    private func policyInput(from request: String) -> PolicyEvaluationInput? {
        guard let data = bodyData(from: request) else { return nil }
        return try? JSONDecoder.tokenBar.decode(PolicyEvaluationInput.self, from: data)
    }

    private func localAgentUsageInput(from request: String) -> LocalAgentUsageIngest? {
        guard let data = bodyData(from: request) else { return nil }
        return try? JSONDecoder.tokenBar.decode(LocalAgentUsageIngest.self, from: data)
    }

    private func bodyData(from request: String) -> Data? {
        let marker = "\r\n\r\n"
        guard let range = request.range(of: marker) else { return nil }
        let body = String(request[range.upperBound...])
        return body.data(using: .utf8)
    }

    private nonisolated func httpResponse(body: Data) -> Data {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(headers.utf8)
        data.append(body)
        return data
    }
}
