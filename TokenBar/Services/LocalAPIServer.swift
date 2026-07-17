import Foundation
import Network
import OSLog

@MainActor
final class LocalAPIServer {
    static let shared = LocalAPIServer(appState: .shared)

    private nonisolated static let readTimeout: DispatchTimeInterval = .seconds(10)

    private let appState: AppState
    private let tokenStore: LocalAPITokenStore
    private let application: LocalAPIApplication
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

    init(appState: AppState) {
        self.appState = appState
        let tokenStore = LocalAPITokenStore()
        self.tokenStore = tokenStore
        application = LocalAPIApplication(
            state: appState,
            authorizationToken: { tokenStore.token() }
        )
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

            switch LocalAPIHTTPCodec.readRequest(from: accumulated) {
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

    private nonisolated func respond(
        to connection: NWConnection,
        request: LocalAPIRequest?,
        response: LocalAPIResponse?
    ) {
        Task { @MainActor in
            let routed = response ?? self.application.handle(request)
            let data = LocalAPIHTTPCodec.responseData(response: routed, request: request)
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

}
