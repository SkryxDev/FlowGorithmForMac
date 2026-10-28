// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import AppKit
import FlowCore
import SwiftUI

/// The AI tab: sign in with OpenRouter, then talk about the open flowchart or ask for changes,
/// answered by free models.
struct AIPanel: View {
    var chat: AIChat
    var session: RunSession
    var context: () -> ToolContext

    @State private var draft = ""
    @FocusState private var composing: Bool
    @AppStorage(SettingsKey.aiMode) private var aiMode = AIMode.auto.rawValue
    /// The "result isn't right" card: open while the user writes what they expected.
    @State private var describingResult = false
    @State private var expected = ""
    /// Hidden after the user answers or closes it, until the next run.
    @State private var resultCardDone = false
    @FocusState private var writingExpected: Bool

    private var account: OpenRouterAccount { .shared }
    var mode: AIMode { AIMode(rawValue: aiMode) ?? .auto }

    var body: some View {
        Group {
            switch account.status {
            case .signedOut: signIn
            case .signingIn: waiting
            case .signedIn: conversation
            }
        }
        // The panel is a column of the window's split view, which follows its minimum size. Text
        // that wraps would make that size depend on the width, and AppKit would recompute the
        // layout in a loop until it stops the app; with no minimum of its own it can't happen.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    // MARK: Signing in

    var signIn: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                Text("AI assistant")
                    .font(.title3.weight(.semibold))
                Text("Ask what your flowchart does or why it fails, or say what to change: the assistant adds, edits and moves shapes for you, live.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                Text("It uses free AI models through OpenRouter. Sign in with your Google account or email: it's free, with about 50 requests a day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    account.signIn()
                } label: {
                    Label("Sign In with OpenRouter", systemImage: "person.crop.circle.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.top, 4)
                if let error = account.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                privacyNote
                    .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity)
        }
    }

    var privacyNote: some View {
        Text("Your flowchart and your messages are sent to OpenRouter and to the model's provider. Free models may use them to improve.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    var waiting: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finish signing in in your browser.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Cancel") { account.cancelSignIn() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Conversation

    var conversation: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AIModeSwitch()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.entries.isEmpty { suggestions }
                    ForEach(chat.entries) { entry in
                        row(entry)
                    }
                    if chat.isWorking { status }
                    // Inside the scroll view, so its wrapping text never changes the column's size.
                    fixCard
                    resultCard
                }
                .padding(12)
                .animation(.snappy, value: errorToFix)
                .animation(.snappy, value: showsResultCard)
            }
            .defaultScrollAnchor(.bottom)
            composer
        }
        .task { await account.refreshUsage() }
        .onChange(of: chat.focusRequest) { composing = true }
        .onChange(of: session.state) { _, state in
            if state.isActive {
                resultCardDone = false
                describingResult = false
                expected = ""
            }
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            Label("AI assistant", systemImage: "sparkles")
                .font(.callout.weight(.medium))
            Text("free models")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            UsageIndicator(account: account)
            Menu {
                Button("New Conversation", systemImage: "square.and.pencil") { chat.clear(context: context) }
                Link("OpenRouter Account…", destination: OpenRouterAccount.settingsURL)
                Divider()
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    chat.clear(context: context)
                    account.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Assistant options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Suggestions

    var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(suggestionList, id: \.self) { suggestion in
                Button { send(suggestion) } label: {
                    Text(suggestion)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.bottom, 4)
    }

    /// Suggestions that fit the chart and the mode: ideas to start from when it's empty, questions
    /// about its functions when it has some.
    var suggestionList: [String] {
        let program = context().program.wrappedValue
        let empty = program.functions.allSatisfy { $0.body.isEmpty }
        let function = program.functions.first { !$0.isMain }?.name
        switch (mode, empty) {
        case (.study, true):
            return [String(localized: "How do I start a program that asks for two numbers and adds them?"),
                    String(localized: "What's the difference between a While and a For loop?"),
                    String(localized: "Give me a simple exercise to practice with.")]
        case (.study, false):
            return [String(localized: "Is there a mistake in this flowchart? Give me a hint, not the answer."),
                    function.map { String(localized: "Help me understand the function \($0).") }
                        ?? String(localized: "What does this program do, step by step?"),
                    String(localized: "What should I try next?")]
        case (.auto, true):
            return [String(localized: "Create a program that asks for two numbers and shows the larger one."),
                    String(localized: "Create a program that counts from 1 to 10."),
                    String(localized: "Create a program that asks for a password until it's right.")]
        case (.auto, false):
            return [String(localized: "What does this program do?"),
                    function.map { String(localized: "Explain the function \($0).") }
                        ?? String(localized: "Is there a mistake in this flowchart?"),
                    String(localized: "Add an output that says “Well done!” at the end.")]
        }
    }

    // MARK: Rows

    @ViewBuilder
    func row(_ entry: AIChat.Entry) -> some View {
        switch entry.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(entry.text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 3) {
                MarkdownText(text: entry.text)
                if let model = entry.model {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        case .action:
            Button {
                chat.reveal(entry.targets, context: context)
            } label: {
                Label(entry.text, systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.targets.isEmpty)
            .help(entry.targets.isEmpty ? "" : String(localized: "Show on the chart"))
        case .changes:
            changesRow(entry)
        case .proposal:
            ProposalCard(entry: entry, canAccept: !context().locked,
                         accept: { chat.accept(entry, context: context) },
                         reject: { chat.reject(entry, context: context) },
                         show: { chat.showProposal(entry, context: context) })
        case .example:
            if let shapes = entry.example {
                ExampleCard(shapes: shapes)
            }
        case .error:
            Label(entry.text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// What a reply changed, with a button that takes it all back or puts it back.
    func changesRow(_ entry: AIChat.Entry) -> some View {
        let live = context()
        let canToggle = !live.locked && chat.canToggle(entry, in: live.program.wrappedValue)
        return HStack(spacing: 8) {
            Image(systemName: entry.undone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                .foregroundStyle(entry.undone ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.purple))
            Text(entry.undone ? String(localized: "Changes undone")
                 : entry.count == 0 ? String(localized: "The chart changed")
                 : entry.count == 1 ? String(localized: "1 shape changed") : String(localized: "\(entry.count) shapes changed"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if canToggle {
                Button(entry.undone ? "Redo" : "Undo", systemImage: entry.undone ? "arrow.uturn.forward" : "arrow.uturn.backward") {
                    withAnimation(.snappy) { chat.toggle(entry, context: context) }
                }
                .font(.caption)
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(entry.undone ? "Put the assistant's changes back" : "Take back everything this reply changed")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(entry.undone ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// What the assistant is doing, with the time it's taking: free models can need half a minute.
    var status: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = chat.workStarted.map { timeline.date.timeIntervalSince($0) } ?? 0
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(statusText(elapsed: elapsed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                if elapsed >= 5 {
                    Text(verbatim: "\(Int(elapsed)) s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .animation(.snappy, value: statusText(elapsed: elapsed))
        }
    }

    func statusText(elapsed: TimeInterval) -> String {
        if chat.phase == .fixing { return String(localized: "Fixing a mistake in the changes…") }
        if elapsed < 3 { return String(localized: "Reading the flowchart…") }
        if elapsed < 20 { return mode == .study ? String(localized: "Thinking of a hint…") : String(localized: "Thinking…") }
        return String(localized: "Still working: free models can be slow…")
    }

    // MARK: Cards

    /// The error the last run stopped with, until the user asks the assistant to fix it.
    var errorToFix: RuntimeError? {
        guard session.state == .failed, let error = session.error, error != chat.lastFixedError, !chat.isWorking else { return nil }
        return error
    }

    @ViewBuilder
    var fixCard: some View {
        if let error = errorToFix {
            VStack(alignment: .leading, spacing: 8) {
                Label("The program stopped with an error", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                Text(ErrorText.message(error))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    chat.ask(.fixError(error), context: context)
                } label: {
                    Label(mode == .study ? "Get a Hint" : "Fix with AI", systemImage: mode == .study ? "graduationcap.fill" : "sparkles")
                }
                .buttonStyle(.glassProminent)
                .tint(mode.color)
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    var showsResultCard: Bool {
        session.state == .finished && !resultCardDone && !chat.isWorking
    }

    /// After a run that ended without errors: a way to say the output isn't what it should be.
    @ViewBuilder
    var resultCard: some View {
        if showsResultCard {
            VStack(alignment: .leading, spacing: 8) {
                if describingResult {
                    Text("What did you expect the program to show?")
                        .font(.callout.weight(.medium))
                    TextField("For example: the average should be 8.25", text: $expected, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($writingExpected)
                        .onSubmit(sendResult)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    HStack {
                        Button("Cancel") {
                            withAnimation(.snappy) { describingResult = false }
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Button(mode == .study ? "Get a Hint" : "Find the Mistake", systemImage: mode == .study ? "graduationcap.fill" : "sparkles",
                               action: sendResult)
                            .buttonStyle(.glassProminent)
                            .tint(mode.color)
                            .controlSize(.small)
                            .disabled(expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.snappy) { describingResult = true }
                            writingExpected = true
                        } label: {
                            Label("The result isn't what you expected?", systemImage: "questionmark.bubble")
                                .font(.callout)
                        }
                        .buttonStyle(.borderless)
                        Spacer(minLength: 4)
                        Button {
                            withAnimation(.snappy) { resultCardDone = true }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Hide")
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    func sendResult() {
        let text = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isWorking else { return }
        chat.ask(.wrongResult(expected: text, output: consoleTranscript), context: context)
        withAnimation(.snappy) {
            resultCardDone = true
            describingResult = false
        }
        expected = ""
    }

    /// The end of what the run printed, with the user's inputs marked, short enough for a request.
    var consoleTranscript: String {
        let lines = session.console.suffix(60).map { entry -> String in
            switch entry.kind {
            case .input: "> \(entry.text) (typed by the user)"
            default: entry.text
            }
        }
        let text = lines.joined(separator: "\n")
        return text.count > 4000 ? "…" + String(text.suffix(4000)) : text
    }

    // MARK: Composer

    var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(mode == .study ? "Ask for an explanation or a hint…" : "Ask, or describe a change…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($composing)
                    .onSubmit { send(draft) }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if chat.isWorking {
                    Button(action: chat.stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Stop")
                } else {
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(mode.color)
                    .buttonBorderShape(.circle)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send")
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    func send(_ text: String) {
        guard !chat.isWorking else { return }
        chat.send(text, context: context)
        draft = ""
        composing = true
    }

}
