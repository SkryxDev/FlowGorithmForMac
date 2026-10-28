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
        enum Kind { case user, assistant, action, changes, proposal, example, error }
        enum Resolution { case accepted, rejected, replaced }
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
        /// For `proposal`: the changes the user can accept or reject, and what they chose.
        var proposal: Proposal?
        var resolution: Resolution?
        /// For `example`: the shapes drawn in the chat.
        var example: [Statement]?
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

    /// The first request plus at most this many to fix failed changes.
    static let maxFixes = 2
    /// How many of the user's past messages, with their replies, go with each request.
    static let historyTurns = 8

    func send(_ text: String, context: @escaping () -> ToolContext) {
        send(display: text, prompt: text, typed: true, context: context)
    }

    #if DEBUG
    /// Adds an entry without asking the model, for the screenshot demo.
    func demo(_ entry: Entry) {
        entries.append(entry)
    }
    #endif

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
        send(display: display, prompt: prompt, typed: false, context: context)
    }

    private func send(display: String, prompt: String, typed: Bool, context: @escaping () -> ToolContext) {
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
                try await converse(context: context, asksForChange: typed && Self.asksForChange(text))
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

    func clear(context: (() -> ToolContext)? = nil) {
        if let editor = context?().editor { editor.proposal = nil }
        stop()
        entries = []
        history = []
        changes = [:]
        lastFixedError = nil
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

    /// Puts back the chart as it was before a message whose changes still have mistakes after every
    /// attempt, so a weak reply never leaves the user's chart broken. The changes stay in the chat,
    /// undone, and Redo shows them anyway.
    private func revert(to start: Program, since firstEntry: Int, context: () -> ToolContext) {
        let live = context()
        let made = live.program.wrappedValue
        let touched = entries[firstEntry...].filter { $0.kind == .action }.flatMap(\.targets)
        let kept = entries[firstEntry...].filter { $0.kind != .action && $0.kind != .changes }
        entries.replaceSubrange(firstEntry..., with: kept)
        live.program.wrappedValue = start
        var record = Entry(kind: .changes, text: "", count: Set(touched).count)
        record.undone = true
        changes[record.id] = (start, made, touched)
        entries.append(record)
        entries.append(Entry(kind: .error, text: String(localized: "The assistant's changes still had mistakes, so the chart is back as it was. Redo shows them anyway, or ask again.")))
    }

    /// Puts an example from the chat on the chart: in the function on screen, in place of its
    /// shapes when it has some. One step the user can undo.
    func useExample(_ entry: Entry, context: () -> ToolContext) {
        guard let shapes = entry.example, entry.resolution == nil,
              let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let live = context()
        guard !live.locked, live.editor.proposal == nil else { return }
        let original = live.program.wrappedValue
        var program = original
        guard let function = live.editor.currentFunction(in: program),
              let functionIndex = program.functions.firstIndex(where: { $0.id == function.id }) else { return }
        let copies = shapes.map { $0.withNewIDs() }
        program.functions[functionIndex].body = copies
        live.program.wrappedValue = program
        entries[index].resolution = .accepted
        let ids = copies.flatMap { [$0] + $0.blocks.flatMap(\.flattened) }.map(\.id)
        let record = Entry(kind: .changes, text: "", count: ids.count)
        changes[record.id] = (original, program, ids)
        entries.insert(record, at: index + 1)
        reveal(ids, context: context)
    }

    /// The proposal waiting for the user's answer, if any.
    var pendingProposal: Entry? {
        entries.last { $0.kind == .proposal && $0.resolution == nil }
    }

    /// Makes the changes the assistant proposed in study mode, as one step the user can undo.
    func accept(_ entry: Entry, context: () -> ToolContext) {
        guard let proposal = entry.proposal, entry.resolution == nil,
              let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let live = context()
        guard !live.locked else { return }
        let original = live.program.wrappedValue
        let (program, touched) = proposal.applied(to: original)
        entries[index].resolution = .accepted
        if live.editor.proposal?.id == proposal.id { live.editor.proposal = nil }
        guard program != original else {
            entries.append(Entry(kind: .error, text: String(localized: "Those shapes aren't in the flowchart anymore.")))
            return
        }
        live.program.wrappedValue = program
        let record = Entry(kind: .changes, text: "", count: touched.count)
        changes[record.id] = (original, program, touched)
        entries.insert(record, at: index + 1)
        reveal(touched, context: context)
    }

    /// Brings a proposal back on the chart, in its function.
    func showProposal(_ entry: Entry, context: () -> ToolContext) {
        guard let proposal = entry.proposal, entry.resolution == nil else { return }
        let live = context()
        live.editor.proposal = proposal
        if let function = proposal.function(in: proposal.preview(of: live.program.wrappedValue).program) {
            live.editor.functionID = function
        }
    }

    /// Drops a proposal: the chart stays as it is.
    func reject(_ entry: Entry, context: () -> ToolContext) {
        guard entry.resolution == nil, let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].resolution = .rejected
        let live = context()
        if live.editor.proposal?.id == entry.proposal?.id { live.editor.proposal = nil }
    }

    /// Shows a new proposal on the chart. An older one still waiting is set aside: only one is drawn.
    private func propose(_ changes: [Proposal.Change], context: () -> ToolContext) {
        guard !changes.isEmpty else { return }
        let live = context()
        let proposal = Proposal(changes: changes)
        let program = live.program.wrappedValue
        for index in entries.indices where entries[index].kind == .proposal && entries[index].resolution == nil {
            entries[index].resolution = .replaced
        }
        entries.append(Entry(kind: .proposal, text: Self.summary(of: proposal, in: program), proposal: proposal))
        live.editor.proposal = proposal
        if let function = proposal.function(in: proposal.preview(of: program).program) {
            live.editor.functionID = function
        }
        live.editor.selection = nil
    }

    /// One line per change: the old shape and the new one.
    static func summary(of proposal: Proposal, in program: Program) -> String {
        func old(_ id: Statement.ID) -> Statement? { program.functions.lazy.compactMap { $0.body.statement(withID: id) }.first }
        var lines: [String] = []
        for change in proposal.changes {
            switch change {
            case .replace(let shape, _):
                lines.append(old(shape.id).map { "\(ShapeText.label($0)) → \(ShapeText.label(shape))" } ?? "+ \(ShapeText.label(shape))")
            case .insert(let shapes, _):
                lines += shapes.map { "+ \(ShapeText.label($0))" }
            case .delete(let id):
                if let shape = old(id) { lines.append("− \(ShapeText.label(shape))") }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Requests

    /// `asksForChange` when the user wrote a request to change the chart: in study mode the answer
    /// should then be a proposal, and a model that only talks about it is reminded once.
    private func converse(context: () -> ToolContext, asksForChange: Bool) async throws {
        let mode = AIMode.current
        phase = .thinking
        // In study mode the changes stay on a copy until the user accepts them; every attempt builds
        // on the previous one, as the chart does in auto mode.
        var proposed: Program?
        var proposedChanges: [Proposal.Change] = []
        // Problems already in the chart before this message aren't the model's: every attempt is
        // checked against these, so a mistake it leaves in place is reported again.
        let baseline = Linter.problems(in: context().program.wrappedValue)
        // In auto mode the chart before this message, to put it back if the changes stay wrong.
        let start = context().program.wrappedValue
        let firstEntry = entries.count
        var lastFailed = false
        var nudged = false
        for attempt in 0...Self.maxFixes {
            guard let key = OpenRouterAccount.shared.key else { throw OpenRouterError.notSignedIn }
            trimHistory()
            let system: JSON = ["role": "system",
                                "content": .string(FlowchartTools.instructions(listing: tools.listing(proposed ?? context().program.wrappedValue), mode: mode))]
            let reply = try await OpenRouterClient.complete(messages: [system] + history, tools: FlowchartTools.allDefinitions, key: key)
            try Task.checkCancellation()

            let content = Self.text(of: reply.message["content"])
            let calls = Self.normalized(reply.message["tool_calls"]?.array ?? [])
            let shown = tools.readable(Self.cleaned(content), in: proposed ?? context().program.wrappedValue)
            // A reply that's empty, or only tool calls written out as text, says nothing to the user.
            if shown.isEmpty && calls.isEmpty && !Self.writesShapes(content) {
                // Free models sometimes come back empty-handed; asking again usually works.
                if attempt < Self.maxFixes { continue }
                throw OpenRouterError.emptyReply
            }
            var kept: [String: JSON] = ["role": "assistant", "content": .string(content)]
            if !calls.isEmpty { kept["tool_calls"] = .array(calls) }
            history.append(.object(kept))
            if !shown.isEmpty {
                entries.append(Entry(kind: .assistant, text: shown, model: OpenRouterClient.displayName(reply.model)))
            }
            if calls.isEmpty {
                // Weaker models describe the proposal instead of making it, so the user would read
                // about changes that aren't on the chart; reminding them once usually gets the calls.
                if proposedChanges.isEmpty, attempt < Self.maxFixes, !nudged,
                   lastFailed || asksForChange || Self.describesProposal(content) || Self.writesShapes(content) {
                    nudged = true
                    history.append(["role": "user", "content": .string(Self.missingProposal)])
                    continue
                }
                propose(proposedChanges, context: context)
                return
            }

            // The whole reply is applied to a copy and written back once, so a single Undo takes
            // back everything the assistant did in it.
            let live = context()
            let original = proposed ?? live.program.wrappedValue
            let working = WorkingCopy(original)
            let copy = Binding(get: { working.program }, set: { working.program = $0 })
            // A proposal mustn't move the user's selection or function: it isn't on the chart yet.
            let local = mode == .study ? ToolContext(program: copy, editor: EditorModel(), locked: false)
                                       : ToolContext(program: copy, editor: live.editor, locked: live.locked)
            let pointing = ToolContext(program: copy, editor: live.editor, locked: false)
            let before = baseline
            var failed = false
            var results: [JSON] = []
            var touched: [Statement.ID] = []
            var drew = false
            var changesNow: [Proposal.Change] = []
            for call in calls {
                let function = call["function"]
                let name = function?["name"]?.string ?? ""
                let outcome = tools.run(name: name, arguments: function?["arguments"]?.string ?? "{}",
                                        context: name == "select_shape" ? pointing : local, mode: mode)
                if let summary = outcome.summary {
                    entries.append(Entry(kind: .action, text: summary, targets: outcome.changed))
                }
                touched += outcome.changed
                changesNow += outcome.proposed
                if let example = outcome.example {
                    entries.append(Entry(kind: .example, text: "", example: example))
                    drew = true
                }
                if outcome.output.hasPrefix("Error") || outcome.output.contains("Fix these problems") { failed = true }
                results.append(["role": "tool", "tool_call_id": call["id"] ?? "", "content": .string(outcome.output)])
            }
            if mode == .study {
                proposed = working.program
                proposedChanges += changesNow
            } else if working.program != original {
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
            lastFailed = failed

            // A reply that only pointed at a shape, as models in study mode often do, still owes the
            // user its explanation: the next request gets it, now that the model has seen the result.
            if !failed && content.isEmpty && !drew && changesNow.isEmpty && working.program == original {
                if attempt < Self.maxFixes { continue }
                throw OpenRouterError.emptyReply
            }
            // Everything worked: no second request, the reply already says what changed.
            if !failed {
                // A reply that only pointed at a shape when a change was asked for.
                if proposedChanges.isEmpty, changesNow.isEmpty, !drew, working.program == original,
                   attempt < Self.maxFixes, !nudged, asksForChange || Self.describesProposal(content) {
                    nudged = true
                    history.append(["role": "user", "content": .string(Self.missingProposal)])
                    continue
                }
                propose(proposedChanges, context: context)
                return
            }
            phase = .fixing
            if mode == .auto && live.locked {
                entries.append(Entry(kind: .error, text: String(localized: "The program is running. Stop it to let the assistant change the flowchart.")))
                return
            }
            if attempt == Self.maxFixes {
                if mode == .auto, live.program.wrappedValue != start {
                    revert(to: start, since: firstEntry, context: context)
                    return
                }
                propose(proposedChanges, context: context)
                entries.append(Entry(kind: .error, text: String(localized: "Some changes didn't come out right. Check the flowchart, or ask the assistant again.")))
            }
        }
    }

    /// Whether the user's message asks to change the chart, in Italian or English.
    static func asksForChange(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["rinomin", "cambi", "aggiung", "modific", "elimin", "togli", "cancell", "sostitu", "spost",
                "inseris", "metti", "correggi", "implement", "crea ", "costruisc", "rename", "change", "add ",
                "remove", "delete", "replace", "insert", "move", "fix", "build", "create"].contains { lowered.contains($0) }
    }

    /// Whether a reply writes shapes out as XML instead of calling the tools.
    static func writesShapes(_ text: String) -> Bool {
        text.contains(/<(declare|assign|input|output|if|while|for|do|call|comment)\b/)
    }

    /// Whether a reply talks about a proposal, in Italian or English.
    static func describesProposal(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["propong", "propost", "propos", "accett", "accept"].contains { lowered.contains($0) }
    }

    static let missingProposal = """
        (Message from the app, not the user.) Nothing reached the chart: shapes written in a reply are \
        just text the user can't use. If a change is needed, call insert_shapes, update_shape or \
        delete_shapes now, with valid XML, for every shape it touches. Don't repeat your explanation.
        """

    /// A reply without the tool calls weaker models write out as text instead of making them, such
    /// as `<!-- SELECT_SHAPE for s1 -->`, which mean nothing to the user.
    static func cleaned(_ text: String) -> String {
        var result = text
        for pattern in [#"(?s)<!-+.*?-+>"#, #"(?s)<tool_call>.*?</tool_call>"#, #"(?s)<function=.*?</function>"#,
                        #"(?im)^\s*\[?\s*(select_shape|insert_shapes|update_shape|delete_shapes|move_shape|show_example|suggest_changes|add_function|delete_function)\b.*$"#,
                        // Shapes written out as XML: the user can't do anything with them.
                        #"(?s)```xml.*?```"#,
                        #"</?(declare|assign|input|output|if|then|else|while|for|do|call|comment|breakpoint|open|close|read|write|body|function)\b[^>]*>"#,
                        #"\(I changed the flowchart\.\)"#] {
            if let regex = try? Regex(pattern) { result = result.replacing(regex, with: "") }
        }
        if let blank = try? Regex(#"\n{3,}"#) { result = result.replacing(blank, with: "\n\n") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
