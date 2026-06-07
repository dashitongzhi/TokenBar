import Foundation
import Network

@MainActor
final class LocalAPIServer {
    private let appState: AppState
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "TokenBar.LocalAPIServer")

    init(appState: AppState) {
        self.appState = appState
    }

    func start(port: UInt16 = 3847) {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        do {
            let listener = try NWListener(using: .tcp, on: endpointPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("TokenBar Local API failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
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
        let marker = "\r\n\r\n"
        guard let range = request.range(of: marker) else { return nil }
        let body = String(request[range.upperBound...])
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONDecoder.tokenBar.decode(PolicyEvaluationInput.self, from: data)
    }

    private nonisolated func httpResponse(body: Data) -> Data {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(headers.utf8)
        data.append(body)
        return data
    }
}
