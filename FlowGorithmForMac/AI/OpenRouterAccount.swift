// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import AppKit
import CryptoKit
import Foundation
import Security

enum OpenRouterError: LocalizedError {
    case incompleteCallback
    case timedOut
    case exchangeFailed(String)
    case notSignedIn
    case keyRevoked
    /// The free-model requests for today are used up; they come back at `reset`.
    case dailyLimit(reset: Date)
    case busy
    case refused(status: Int, message: String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .incompleteCallback:
            String(localized: "The browser came back without completing the sign-in. Try again.")
        case .timedOut:
            String(localized: "The sign-in took too long. Try again.")
        case .exchangeFailed(let message):
            String(localized: "OpenRouter sign-in failed: \(message)")
        case .notSignedIn:
            String(localized: "Sign in with OpenRouter first.")
        case .keyRevoked:
            String(localized: "OpenRouter no longer accepts this app's key. Sign in again.")
        case .dailyLimit(let reset):
            String(localized: "You've used today's free requests. They come back at \(reset.formatted(date: .omitted, time: .shortened)).")
        case .busy:
            String(localized: "The free models are busy right now. Try again in a minute.")
        case .refused(let status, let message):
            String(localized: "OpenRouter refused the request (\(status)): \(message)")
        case .emptyReply:
            String(localized: "The model didn't answer. Try again or rephrase the request.")
        }
    }
}

/// Sign in with OpenRouter: an OAuth flow with PKCE through the browser and a callback on
/// localhost, which gives the app a key that belongs to the user. Requests to free models then
/// count against the user's own daily allowance.
/// https://openrouter.ai/docs/guides/overview/auth/oauth
@Observable
final class OpenRouterAccount {
    static let shared = OpenRouterAccount()

    enum Status { case signedOut, signingIn, signedIn }

    private(set) var status = Status.signedOut
    var lastError: String?
    /// Free-model requests left today and the daily ceiling, from `GET /api/v1/key`.
    private(set) var remainingToday: Int?
    private(set) var dailyLimit: Int?

    /// The share of today's free-model requests already used, from 0 to 1.
    var dailyUsage: Double? {
        guard let remainingToday, let dailyLimit, dailyLimit > 0 else { return nil }
        return Double(max(0, dailyLimit - remainingToday)) / Double(dailyLimit)
    }

    @ObservationIgnored private(set) var key: String?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    static let authURL = URL(string: "https://openrouter.ai/auth")!
    static let keysURL = URL(string: "https://openrouter.ai/api/v1/auth/keys")!
    static let keyInfoURL = URL(string: "https://openrouter.ai/api/v1/key")!
    static let settingsURL = URL(string: "https://openrouter.ai/settings/keys")!
    static let creditsURL = URL(string: "https://openrouter.ai/settings/credits")!

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let saved = JSON.parse(data), let key = saved["key"]?.string {
            self.key = key
            status = .signedIn
        }
    }

    /// When the free requests come back: OpenRouter counts them per UTC day.
    static var nextReset: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? Date()
    }

    // MARK: Signing in and out

    func signIn() {
        guard status != .signingIn else { return }
        lastError = nil
        status = .signingIn
        signInTask = Task {
            do {
                try await performSignIn()
            } catch is CancellationError {
            } catch {
                lastError = error.localizedDescription
            }
            status = key == nil ? .signedOut : .signedIn
            if key != nil { await refreshUsage() }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    /// Forgets the key on this Mac. It stays listed in the user's OpenRouter keys, where it can be deleted.
    func signOut() {
        key = nil
        remainingToday = nil
        dailyLimit = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
        status = .signedOut
    }

    private func performSignIn() async throws {
        let server = try await LoopbackCallback.start(preferredPort: 3000)
        defer { server.stop() }

        let state = Self.randomString()
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString

        var components = URLComponents(url: Self.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: server.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "key_label", value: "FlowGorithmForMac"),
        ]
        NSWorkspace.shared.open(components.url!)

        // OpenRouter's codes expire after 10 minutes, so there's no point waiting longer.
        let callback: [URLQueryItem]
        do {
            callback = try await server.waitForCallback(timeout: .seconds(600))
        } catch is LoopbackCallback.TimedOut {
            throw OpenRouterError.timedOut
        }
        NSApp.activate()
        func value(_ name: String) -> String? { callback.first { $0.name == name }?.value }
        guard value("state") == state, let code = value("code") else { throw OpenRouterError.incompleteCallback }

        var request = URLRequest(url: Self.keysURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = JSON.object(["code": .string(code), "code_verifier": .string(verifier),
                                        "code_challenge_method": "S256"]).data
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = JSON.parse(data)
        guard status == 200, let key = body?["key"]?.string else {
            throw OpenRouterError.exchangeFailed(body?["error"]?["message"]?.string ?? "HTTP \(status)")
        }
        self.key = key
        save()
    }

    // MARK: Usage

    /// Reads how many free-model requests are left today.
    func refreshUsage() async {
        guard let key else { return }
        var request = URLRequest(url: Self.keyInfoURL)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return }
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            keyRevoked()
            return
        }
        let daily = JSON.parse(data)?["data"]?["free_model_daily_requests"]
        remainingToday = daily?["remaining"]?.number.map { Int($0) }
        dailyLimit = daily?["limit"]?.number.map { Int($0) }
    }

    /// OpenRouter refused the key: it was deleted or disabled in the user's settings.
    func keyRevoked() {
        signOut()
        lastError = OpenRouterError.keyRevoked.localizedDescription
    }

    // MARK: Storage

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "FlowGorithmForMac/OpenRouter.json")
    }

    /// Owner-only folder and file, written atomically.
    private func save() {
        let folder = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        guard let key else { return }
        try? JSON.object(["key": .string(key)]).data.write(to: Self.fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLString
    }
}

extension Data {
    nonisolated var base64URLString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
