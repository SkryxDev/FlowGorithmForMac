// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import Foundation
import SwiftUI

/// Something the app asks the assistant on the user's behalf, from the chart, the error banner or
/// the console. The chat shows a short version; the model gets the details.
enum AIRequest {
    case fixError(RuntimeError)
    case explainShape(Statement.ID, label: String)
    case shapeProblem(Statement.ID, label: String, problem: String)
    case wrongResult(expected: String, output: String)
    case endlessLoop(Statement.ID?, function: String?)
}

/// One conversation about the open flowchart with a free model on OpenRouter. The model sees the
/// whole chart in every request and changes it through `FlowchartTools`, so edits appear live and
/// can be undone. Free models allow a few dozen requests a day, so each message costs one request:
/// the model makes every change and explains it in the same reply, and it's asked again only to
/// fix a change that failed. In study mode it can't change the chart and gives hints instead.
@Observable
final class AIChat {
    struct Entry: Identifiable {
        enum Kind { case user, assistant, action, changes, error }
        let id = UUID()
        var kind: Kind
        var text: String
        /// The model that wrote an assistant reply.
        var model: String?
        /// The shapes an action touched, which clicking it shows on the chart.
        var targets: [Statement.ID] = []
        /// For `changes`: how many shapes a reply touched, and whether the user took it back.
        var count = 0
        var undone = false
    }

    enum Phase {
        /// Waiting for the reply.
        case thinking
        /// Asking again because a change didn't come out right.
        case fixing
    }

    private(set) var entries: [Entry] = []
    private(set) var isWorking = false
    private(set) var phase = Phase.thinking
    /// When the current request was sent, so the panel can say how long it's taking.
    private(set) var workStarted: Date?
    /// The last run error sent to the model, so the panel stops offering to fix it.
    private(set) var lastFixedError: RuntimeError?
    /// Bumped to move the keyboard focus to the message field.
    private(set) var focusRequest = 0

    @ObservationIgnored private var history: [JSON] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let tools = FlowchartTools()
    /// The chart before and after each reply that changed it, for its Undo button.
    @ObservationIgnored private var changes: [Entry.ID: (before: Program, after: Program, shapes: [Statement.ID])] = [:]
    /// The mode of the last request: the history is rewritten when it changes.
    @ObservationIgnored private var lastMode: AIMode?

    /// The first request plus at most this many to fix failed changes.
    static let maxFixes = 2
    /// How many of the user's past messages, with their replies, go with each request.
    static let historyTurns = 8

    func send(_ text: String, context: @escaping () -> ToolContext) {
        send(display: text, prompt: text, context: context)
    }

    func requestFocus() {
        focusRequest += 1
    }

    /// Sends a request the app wrote for the user, worded for the current mode.
    func ask(_ request: AIRequest, context: @escaping () -> ToolContext) {
        let study = AIMode.current == .study
        let display: String
        var prompt: String
        switch request {
        case .fixError(let error):
            let message = ErrorText.message(error)
            prompt = "The program stopped with this error"
            if let function = error.functionName { prompt += " in the function \(function)" }
            if let id = error.statementID { prompt += ", at the shape \(tools.shortID(id))" }
            prompt += ": \(message)\n"
            prompt += study
                ? "Help me understand what's wrong, with a hint so I can fix it myself."
                : "Fix the flowchart so the program runs, and tell me in one or two sentences what was wrong."
            lastFixedError = error
            display = study ? String(localized: "Help me with the error: “\(message)”") : String(localized: "Fix the error: “\(message)”")
        case .explainShape(let id, let label):
            prompt = "Explain what the shape \(tools.shortID(id)) (“\(label)”) does in this program and why it's there. Call it by what it does, not by its id."
            display = String(localized: "Explain this shape: “\(label)”")
        case .shapeProblem(let id, let label, let problem):
            prompt = "The app marks the shape \(tools.shortID(id)) (“\(label)”) with this problem: \(problem)\n"
            prompt += study
                ? "Explain what's wrong and give me a hint, without fixing it."
                : "Fix it, and tell me in one sentence what was wrong."
            display = String(localized: "What's wrong with this shape? “\(label)”")
        case .wrongResult(let expected, let output):
            prompt = "I ran the program and it finished, but the result isn't what I expected.\n"
            prompt += output.isEmpty ? "The console showed nothing.\n" : "The console showed:\n\(output)\n"
            prompt += "I expected: \(expected)\n"
            prompt += study
                ? "Help me find the mistake with a hint, without fixing it."
                : "Find the mistake and fix the flowchart, then tell me in one or two sentences what was wrong."
            display = String(localized: "The result isn't right. I expected: “\(expected)”")
        case .endlessLoop(let id, let function):
            prompt = "I ran the program and it kept running without stopping, so I stopped it."
            if let id { prompt += " It was at the shape \(tools.shortID(id))\(function.map { " in \($0)" } ?? "") when I stopped it." }
            prompt += study
                ? " Is there an endless loop? Help me see why with a hint, without fixing it."
                : " Is there an endless loop? If so, fix it and tell me in one or two sentences what was wrong."
            display = String(localized: "The program doesn't stop: is there an endless loop?")
        }
        send(display: display, prompt: prompt, context: context)
    }

    private func send(display: String, prompt: String, context: @escaping () -> ToolContext) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        entries.append(Entry(kind: .user, text: display))
        history.append(["role": "user", "content": .string(text)])
        isWorking = true
        phase = .thinking
        workStarted = Date()
        task = Task {
            defer {
                isWorking = false
                workStarted = nil
            }
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
        changes = [:]
        lastFixedError = nil
        lastMode = nil
        tools.reset()
    }

    // MARK: Changes

    /// Shows the shapes an action or a reply touched: their function, selected, briefly highlighted.
    func reveal(_ shapes: [Statement.ID], context: () -> ToolContext) {
        let live = context()
        let program = live.program.wrappedValue
        let present = shapes.filter { id in program.functions.contains { $0.body.statement(withID: id) != nil } }
        guard let first = present.first,
              let function = program.functions.first(where: { $0.body.statement(withID: first) != nil }) else { return }
        live.editor.functionID = function.id
        live.editor.selection = present.count == 1 ? first : nil
        live.editor.flash(present)
    }

    /// Whether a reply's changes can be taken back, or put back, right now: only while the chart
    /// is exactly as that reply left it, or as it was before, so no later edit is lost.
    func canToggle(_ entry: Entry, in program: Program) -> Bool {
        guard let record = changes[entry.id] else { return false }
        return program == (entry.undone ? record.before : record.after)
    }

    /// Takes back everything a reply changed, or puts it back.
    func toggle(_ entry: Entry, context: () -> ToolContext) {
        let live = context()
        guard !live.locked, canToggle(entry, in: live.program.wrappedValue),
              let record = changes[entry.id], let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        live.program.wrappedValue = entry.undone ? record.after : record.before
        entries[index].undone.toggle()
        if !entries[index].undone { reveal(record.shapes, context: context) }
    }

    // MARK: Requests

    private func converse(context: () -> ToolContext) async throws {
        let mode = AIMode.current
        if let lastMode, lastMode != mode { forgetToolCalls() }
        lastMode = mode
        phase = .thinking
        for attempt in 0...Self.maxFixes {
            guard let key = OpenRouterAccount.shared.key else { throw OpenRouterError.notSignedIn }
            trimHistory()
            let system: JSON = ["role": "system",
                                "content": .string(FlowchartTools.instructions(listing: tools.listing(context().program.wrappedValue), mode: mode))]
            let reply = try await OpenRouterClient.complete(messages: [system] + history, tools: FlowchartTools.definitions(for: mode), key: key)
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
            let original = live.program.wrappedValue
            let working = WorkingCopy(original)
            let local = ToolContext(program: Binding(get: { working.program }, set: { working.program = $0 }),
                                    editor: live.editor, locked: live.locked)
            let before = Linter.problems(in: working.program)
            var failed = false
            var results: [JSON] = []
            var touched: [Statement.ID] = []
            for call in calls {
                let function = call["function"]
                let outcome = tools.run(name: function?["name"]?.string ?? "",
                                        arguments: function?["arguments"]?.string ?? "{}", context: local, mode: mode)
                if let summary = outcome.summary {
                    entries.append(Entry(kind: .action, text: summary, targets: outcome.changed))
                }
                touched += outcome.changed
                if outcome.output.hasPrefix("Error") || outcome.output.contains("Fix these problems") { failed = true }
                results.append(["role": "tool", "tool_call_id": call["id"] ?? "", "content": .string(outcome.output)])
            }
            if working.program != original {
                live.program.wrappedValue = working.program
                var seen = Set<Statement.ID>()
                let shapes = touched.filter { seen.insert($0).inserted }
                let entry = Entry(kind: .changes, text: "", count: shapes.count)
                changes[entry.id] = (original, working.program, shapes)
                entries.append(entry)
                live.editor.flash(shapes)
            }
            if let check = tools.newProblems(since: before, in: working.program), case .object(var last) = results.removeLast() {
                last["content"] = .string((last["content"]?.string ?? "") + "\n" + check)
                results.append(.object(last))
                failed = true
            }
            history += results

            // A reply that only pointed at a shape, as models in study mode often do, still owes the
            // user its explanation: the next request gets it, now that the model has seen the result.
            if !failed && content.isEmpty && working.program == original {
                if attempt < Self.maxFixes { continue }
                throw OpenRouterError.emptyReply
            }
            // Everything worked: no second request, the reply already says what changed.
            if !failed { return }
            phase = .fixing
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

    /// Turns past tool calls into plain replies. The two modes offer different tools, and some
    /// providers refuse a conversation that calls a tool the request doesn't define.
    private func forgetToolCalls() {
        history = history.compactMap { message in
            switch message["role"]?.string {
            case "tool":
                return nil
            case "assistant":
                guard message["tool_calls"] != nil else { return message }
                let content = message["content"]?.string ?? ""
                return ["role": "assistant", "content": .string(content.isEmpty ? "(I changed the flowchart.)" : content)]
            default:
                return message
            }
        }
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
