// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import Foundation
import SwiftUI

/// One conversation about the open flowchart with a free model on OpenRouter. The model sees the
/// whole chart in every request and changes it through `FlowchartTools`, so edits appear live and
/// can be undone. Free models allow a few dozen requests a day, so each message costs one request:
/// the model makes every change and explains it in the same reply, and it's asked again only to
/// fix a change that failed.
@Observable
final class AIChat {
    struct Entry: Identifiable {
        enum Kind { case user, assistant, action, error }
        let id = UUID()
        var kind: Kind
        var text: String
        /// The model that wrote an assistant reply.
        var model: String?
    }

    private(set) var entries: [Entry] = []
    private(set) var isWorking = false
    /// The last run error sent to the model, so the panel stops offering to fix it.
    private(set) var lastFixedError: RuntimeError?

    @ObservationIgnored private var history: [JSON] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let tools = FlowchartTools()

    /// The first request plus at most this many to fix failed changes.
    static let maxFixes = 2
    /// How many of the user's past messages, with their replies, go with each request.
    static let historyTurns = 8

    func send(_ text: String, context: @escaping () -> ToolContext) {
        send(display: text, prompt: text, context: context)
    }

    /// Asks the model to fix the error the last run stopped with. The chat shows a short request;
    /// the model also gets the function and the shape where it happened.
    func fix(_ error: RuntimeError, context: @escaping () -> ToolContext) {
        let message = ErrorText.message(error)
        var prompt = "The program stopped with this error"
        if let function = error.functionName { prompt += " in the function \(function)" }
        if let id = error.statementID { prompt += ", at the shape \(tools.shortID(id))" }
        prompt += ": \(message)\nFix the flowchart so the program runs, and tell me in one or two sentences what was wrong."
        lastFixedError = error
        send(display: String(localized: "Fix the error: “\(message)”"), prompt: prompt, context: context)
    }

    private func send(display: String, prompt: String, context: @escaping () -> ToolContext) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        entries.append(Entry(kind: .user, text: display))
        history.append(["role": "user", "content": .string(text)])
        isWorking = true
        task = Task {
            defer { isWorking = false }
            do {
                try await converse(context: context)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                if case OpenRouterError.keyRevoked = error { OpenRouterAccount.shared.keyRevoked() }
                entries.append(Entry(kind: .error, text: error.localizedDescription))
            }
            await OpenRouterAccount.shared.refreshUsage()
        }
    }

    func stop() {
        task?.cancel()
    }

    /// A new run can stop with the same error again, which is then worth offering to fix again.
    func runStarted() {
        lastFixedError = nil
    }

    func clear() {
        stop()
        entries = []
        history = []
        lastFixedError = nil
        tools.reset()
    }

    private func converse(context: () -> ToolContext) async throws {
        for attempt in 0...Self.maxFixes {
            guard let key = OpenRouterAccount.shared.key else { throw OpenRouterError.notSignedIn }
            trimHistory()
            let system: JSON = ["role": "system",
                                "content": .string(FlowchartTools.instructions(listing: tools.listing(context().program.wrappedValue)))]
            let reply = try await OpenRouterClient.complete(messages: [system] + history, tools: FlowchartTools.definitions, key: key)
            try Task.checkCancellation()

            let content = Self.text(of: reply.message["content"])
            let calls = Self.normalized(reply.message["tool_calls"]?.array ?? [])
            if content.isEmpty && calls.isEmpty {
                // Free models sometimes come back empty-handed; asking again usually works.
                if attempt < Self.maxFixes { continue }
                throw OpenRouterError.emptyReply
            }
            var kept: [String: JSON] = ["role": "assistant", "content": .string(content)]
            if !calls.isEmpty { kept["tool_calls"] = .array(calls) }
            history.append(.object(kept))
            if !content.isEmpty {
                entries.append(Entry(kind: .assistant, text: content, model: OpenRouterClient.displayName(reply.model)))
            }
            if calls.isEmpty { return }

            // The whole reply is applied to a copy and written back once, so a single Undo takes
            // back everything the assistant did in it.
            let live = context()
            let working = WorkingCopy(live.program.wrappedValue)
            let local = ToolContext(program: Binding(get: { working.program }, set: { working.program = $0 }),
                                    editor: live.editor, locked: live.locked)
            let before = Linter.problems(in: working.program)
            var failed = false
            var results: [JSON] = []
            for call in calls {
                let function = call["function"]
                let outcome = tools.run(name: function?["name"]?.string ?? "",
                                        arguments: function?["arguments"]?.string ?? "{}", context: local)
                if let summary = outcome.summary { entries.append(Entry(kind: .action, text: summary)) }
                if outcome.output.hasPrefix("Error") || outcome.output.contains("Fix these problems") { failed = true }
                results.append(["role": "tool", "tool_call_id": call["id"] ?? "", "content": .string(outcome.output)])
            }
            if working.program != live.program.wrappedValue { live.program.wrappedValue = working.program }
            if let check = tools.newProblems(since: before, in: working.program), case .object(var last) = results.removeLast() {
                last["content"] = .string((last["content"]?.string ?? "") + "\n" + check)
                results.append(.object(last))
                failed = true
            }
            history += results

            // Everything worked: no second request, the reply already says what changed.
            if !failed { return }
            if live.locked {
                entries.append(Entry(kind: .error, text: String(localized: "The program is running. Stop it to let the assistant change the flowchart.")))
                return
            }
            if attempt == Self.maxFixes {
                entries.append(Entry(kind: .error, text: String(localized: "Some changes didn't come out right. Check the flowchart, or ask the assistant again.")))
            }
        }
    }

    /// Keeps the last few exchanges. It cuts only before a message of the user's, so every tool
    /// call stays together with its result.
    private func trimHistory() {
        let starts = history.indices.filter { history[$0]["role"]?.string == "user" }
        guard starts.count > Self.historyTurns else { return }
        history.removeFirst(starts[starts.count - Self.historyTurns])
    }

    /// The text of a reply, which some providers send as a list of parts.
    static func text(of content: JSON?) -> String {
        let text: String
        switch content {
        case .string(let value)?: text = value
        case .array(let parts)?: text = parts.compactMap { $0["text"]?.string ?? $0.string }.joined()
        default: text = ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tool calls as the API expects them back: every call with an id, and its arguments as a JSON
    /// string, which some models send as an object instead.
    static func normalized(_ calls: [JSON]) -> [JSON] {
        calls.compactMap { call in
            guard case .object(var object) = call, case .object(var function)? = object["function"] else { return nil }
            if object["id"]?.string?.isEmpty ?? true { object["id"] = .string("call_" + UUID().uuidString.prefix(12)) }
            if let arguments = function["arguments"], arguments.string == nil {
                function["arguments"] = .string(String(decoding: arguments.data, as: UTF8.self))
            }
            object["function"] = .object(function)
            object["type"] = "function"
            return .object(object)
        }
    }
}

/// The chart while a reply is applied, before it's written back to the document in one go.
private final class WorkingCopy {
    var program: Program
    init(_ program: Program) { self.program = program }
}
