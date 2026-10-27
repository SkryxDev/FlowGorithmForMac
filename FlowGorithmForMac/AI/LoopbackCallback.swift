// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation
import Network

/// A one-shot HTTP listener on the loopback interface that receives the browser's redirect at
/// the end of an OAuth sign-in. It listens on every loopback address, since a browser may
/// resolve `localhost` to IPv4 or IPv6. Everything runs on the main queue.
final class LoopbackCallback {
    static let path = "/callback"

    /// The browser didn't come back in time.
    struct TimedOut: Error {}

    private let listener: NWListener
    private var ready: CheckedContinuation<UInt16, Error>?
    private var callback: CheckedContinuation<[URLQueryItem], Error>?
    private var outcome: Result<[URLQueryItem], Error>?

    private(set) var port: UInt16 = 0
    var redirectURI: String { "http://localhost:\(port)\(Self.path)" }

    private init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
    }

    /// Listens on `preferredPort`, or on any free port when it's taken.
    static func start(preferredPort: UInt16) async throws -> LoopbackCallback {
        if let server = try? await LoopbackCallback(port: preferredPort).open() { return server }
        return try await LoopbackCallback(port: 0).open()
    }

    private func open() async throws -> LoopbackCallback {
        port = try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
        return self
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            ready?.resume(returning: listener.port?.rawValue ?? 0)
            ready = nil
        case .failed(let error):
            ready?.resume(throwing: error)
            ready = nil
            finish(.failure(error))
        default:
            break
        }
    }

    /// Waits for the browser to come back with the query of the callback URL, giving up after
    /// `timeout`, so a sign-in abandoned in the browser doesn't keep the app waiting.
    func waitForCallback(timeout: Duration) async throws -> [URLQueryItem] {
        if let outcome { return try outcome.get() }
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.finish(.failure(TimedOut()))
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                callback = continuation
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    func stop() {
        listener.cancel()
    }

    private func finish(_ result: Result<[URLQueryItem], Error>) {
        if outcome == nil { outcome = result }
        callback?.resume(with: result)
        callback = nil
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated { self?.handle(data ?? Data(), on: connection) }
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        // "GET /auth/callback?code=…&state=… HTTP/1.1"
        let requestLine = String(decoding: data, as: UTF8.self).split(separator: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://localhost\(parts[1])"),
              components.path == Self.path else {
            // Browsers also ask for /favicon.ico and the like.
            respond(on: connection, status: "404 Not Found", body: "")
            return
        }
        let items = components.queryItems ?? []
        let failed = items.contains { $0.name == "error" }
        respond(on: connection, status: "200 OK", body: Self.page(success: !failed))
        finish(.success(items))
    }

    private func respond(on connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func page(success: Bool) -> String {
        let title = success ? String(localized: "You're signed in") : String(localized: "Sign-in was not completed")
        let message = success ? String(localized: "You can close this tab and go back to FlowGorithmForMac.")
                              : String(localized: "Go back to FlowGorithmForMac to try again.")
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>FlowGorithmForMac</title>
        <style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:90vh;margin:0;
        color:#1d1d1f;background:#f5f5f7}@media(prefers-color-scheme:dark){body{color:#f5f5f7;background:#1d1d1f}}
        div{text-align:center}h1{font-size:22px}</style></head>
        <body><div><h1>\(title)</h1><p>\(message)</p></div></body></html>
        """
    }
}
