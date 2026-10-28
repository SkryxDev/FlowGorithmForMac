// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

/// OpenRouter's Chat Completions endpoint, used with free models only.
enum OpenRouterClient {
    static let chatURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

    /// The free models to try, in order: OpenRouter moves on to the next one when a model is busy
    /// or gone. Only models good enough to edit a chart: OpenRouter's router of any free model
    /// also picks tiny ones, which scatter shapes around, so it isn't used.
    static let preferred = ["google/gemma-4-31b-it:free", "nvidia/nemotron-3-ultra-550b-a55b:free",
                            "nvidia/nemotron-3.5-super-vl:free"]
    /// Asked when all the preferred models are busy.
    static let backup = ["google/gemma-4-26b-a4b-it:free", "thinkingmachines/inkling:free"]

    /// Display names for the models that answered, shown under each reply.
    static func displayName(_ id: String) -> String {
        if id.hasPrefix("google/gemma-4-31b") { return "Gemma 4 31B" }
        if id.hasPrefix("nvidia/nemotron-3-ultra") { return "Nemotron 3 Ultra" }
        if id.hasPrefix("nvidia/nemotron-3.5-super") { return "Nemotron 3.5 Super" }
        if id.hasPrefix("google/gemma-4-26b") { return "Gemma 4 26B" }
        if id.hasPrefix("thinkingmachines/inkling") { return "Inkling" }
        return id.split(separator: "/").last.map { String($0).replacingOccurrences(of: ":free", with: "") } ?? id
    }

    /// The preferred and backup models still listed as free and able to use tools. The free roster
    /// changes often, so the list is checked once per launch; without the catalog, all are tried.
    static func availableModels() async -> (preferred: [String], backup: [String]) {
        if let cached { return (cached.filter(preferred.contains), cached.filter(backup.contains)) }
        var models = preferred + backup
        if let (data, _) = try? await URLSession.shared.data(from: modelsURL),
           let list = JSON.parse(data)?["data"]?.array {
            let usable = Set(list.compactMap { model -> String? in
                guard let id = model["id"]?.string,
                      Self.isFree(model["pricing"]?["prompt"]), Self.isFree(model["pricing"]?["completion"]),
                      model["supported_parameters"]?.array?.contains(.string("tools")) == true else { return nil }
                return id
            })
            let listed = models.filter(usable.contains)
            // If none of them is listed anymore, they're still tried rather than nothing.
            if !listed.isEmpty { models = listed }
        }
        cached = models
        return (models.filter(preferred.contains), models.filter(backup.contains))
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

    /// One request, to the preferred models and, when they're all busy, to the backups. Errors
    /// carry what the user can do about them.
    static func complete(messages: [JSON], tools: [JSON], key: String) async throws -> Reply {
        let (first, second) = await availableModels()
        do {
            return try await complete(messages: messages, tools: tools, key: key, models: first.isEmpty ? second : first)
        } catch OpenRouterError.busy where !first.isEmpty && !second.isEmpty {
            return try await complete(messages: messages, tools: tools, key: key, models: second)
        }
    }

    private static func complete(messages: [JSON], tools: [JSON], key: String, models: [String]) async throws -> Reply {
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional attribution headers that OpenRouter shows in the user's activity.
        request.setValue("https://github.com/SkryxDev/FlowGorithmForMac", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("FlowGorithmForMac", forHTTPHeaderField: "X-Title")
        var body: [String: JSON] = [
            "models": .array(models.map(JSON.string)),
            "messages": .array(messages),
            // Free models that think at length can spend the whole reply on reasoning and answer
            // nothing; a light effort is plenty for flowcharts and answers much sooner.
            "reasoning": ["effort": "low"],
            "max_tokens": 8192,
        ]
        // Some providers refuse an empty list of tools, so a request without tools leaves it out.
        if !tools.isEmpty { body["tools"] = .array(tools) }
        request.httpBody = JSON.object(body).data

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = JSON.parse(data)
        let message = reply?["error"]?["message"]?.string ?? String(decoding: data.prefix(300), as: UTF8.self)
        switch status {
        case 200:
            // Errors can also arrive inside a 200, from the provider behind the model.
            if reply?["error"] != nil { throw OpenRouterError.refused(status: 200, message: message) }
            let choice = reply?["choices"]?.array?.first
            if let error = choice?["error"] {
                throw OpenRouterError.refused(status: 200, message: error["message"]?.string ?? message)
            }
            guard let answer = choice?["message"] else { throw OpenRouterError.emptyReply }
            return Reply(message: answer, model: reply?["model"]?.string ?? models.first ?? "")
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
