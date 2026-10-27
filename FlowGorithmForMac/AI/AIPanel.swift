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

    private var account: OpenRouterAccount { .shared }

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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.entries.isEmpty { suggestions }
                    ForEach(chat.entries) { entry in
                        row(entry)
                    }
                    if chat.isWorking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    // Inside the scroll view, so its wrapping text never changes the column's size.
                    fixCard
                }
                .padding(12)
                .animation(.snappy, value: errorToFix)
            }
            .defaultScrollAnchor(.bottom)
            composer
        }
        .task { await account.refreshUsage() }
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
                Button("New Conversation", systemImage: "square.and.pencil") { chat.clear() }
                Link("OpenRouter Account…", destination: OpenRouterAccount.settingsURL)
                Divider()
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    chat.clear()
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

    var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach([String(localized: "What does this program do?"),
                     String(localized: "Is there a mistake in this flowchart?"),
                     String(localized: "Add an output that says “Well done!” at the end.")], id: \.self) { suggestion in
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
                Text(Self.markdown(entry.text))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let model = entry.model {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        case .action:
            Label(entry.text, systemImage: "wand.and.stars")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            Label(entry.text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

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
                    chat.fix(error, context: context)
                } label: {
                    Label("Fix with AI", systemImage: "sparkles")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask, or describe a change…", text: $draft, axis: .vertical)
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

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
