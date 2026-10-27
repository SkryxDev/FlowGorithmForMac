// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

/// OpenRouter's Chat Completions endpoint, used with free models only.
enum OpenRouterClient {
    static let chatURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

    /// The free models to try, in order: OpenRouter moves on to the next one when a model is busy
    /// or gone. `openrouter/free` picks any free model that's up, so something always answers.
    static let preferred = ["google/gemma-4-31b-it:free", "nvidia/nemotron-3-ultra-550b-a55b:free", "openrouter/free"]

    /// Display names for the models that answered, shown under each reply.
    static func displayName(_ id: String) -> String {
        if id.hasPrefix("google/gemma-4-31b") { return "Gemma 4 31B" }
        if id.hasPrefix("nvidia/nemotron-3-ultra") { return "Nemotron 3 Ultra" }
        return id.split(separator: "/").last.map { String($0).replacingOccurrences(of: ":free", with: "") } ?? id
    }

    /// The preferred models still listed as free and able to use tools. The free roster changes
    /// often, so the list is checked once per launch; the router stays as the last resort.
    static func availableModels() async -> [String] {
        if let cached { return cached }
        var models = ["openrouter/free"]
        if let (data, _) = try? await URLSession.shared.data(from: modelsURL),
           let list = JSON.parse(data)?["data"]?.array {
            let usable = Set(list.compactMap { model -> String? in
                guard let id = model["id"]?.string,
                      Self.isFree(model["pricing"]?["prompt"]), Self.isFree(model["pricing"]?["completion"]),
                      model["supported_parameters"]?.array?.contains(.string("tools")) == true else { return nil }
                return id
            })
            models = preferred.filter { usable.contains($0) || $0 == "openrouter/free" }
        }
        cached = models
        return models
    }

    private static var cached: [String]?

    /// Prices come as strings ("0") or numbers depending on the field.
    private static func isFree(_ price: JSON?) -> Bool {
        switch price {
        case .string(let text)?: Double(text) == 0
        case .number(let value)?: value == 0
        default: false
        }
    }

    struct Reply {
        var message: JSON
        var model: String
    }

    /// One request. Errors carry what the user can do about them.
    static func complete(messages: [JSON], tools: [JSON], key: String) async throws -> Reply {
        let models = await availableModels()
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional attribution headers that OpenRouter shows in the user's activity.
        request.setValue("https://github.com/SkryxDev/FlowGorithmForMac", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("FlowGorithmForMac", forHTTPHeaderField: "X-Title")
        request.httpBody = JSON.object([
            "models": .array(models.map(JSON.string)),
            "messages": .array(messages),
            "tools": .array(tools),
            // Free models that think at length can spend the whole reply on reasoning and answer
            // nothing; a light effort is plenty for flowcharts and answers much sooner.
            "reasoning": ["effort": "low"],
            "max_tokens": 8192,
        ]).data

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = JSON.parse(data)
        let message = body?["error"]?["message"]?.string ?? String(decoding: data.prefix(300), as: UTF8.self)
        switch status {
        case 200:
            // Errors can also arrive inside a 200, from the provider behind the model.
            if body?["error"] != nil { throw OpenRouterError.refused(status: 200, message: message) }
            let choice = body?["choices"]?.array?.first
            if let error = choice?["error"] {
                throw OpenRouterError.refused(status: 200, message: error["message"]?.string ?? message)
            }
            guard let reply = choice?["message"] else { throw OpenRouterError.emptyReply }
            return Reply(message: reply, model: body?["model"]?.string ?? models.first ?? "")
        case 401:
            throw OpenRouterError.keyRevoked
        case 429:
            let lowered = message.lowercased()
            if lowered.contains("per-day") || lowered.contains("per day") || lowered.contains("daily") {
                throw OpenRouterError.dailyLimit(reset: OpenRouterAccount.nextReset)
            }
            throw OpenRouterError.busy
        case 408, 502, 503, 504:
            throw OpenRouterError.busy
        default:
            throw OpenRouterError.refused(status: status, message: message)
        }
    }
}
