import FlowCore
import SwiftUI

/// The program's console: chat bubbles (or plain text) and an input bar when the program asks for a value.
struct ConsoleView: View {
    var session: RunSession
    @AppStorage(SettingsKey.chatConsole) private var chatStyle = true
    @AppStorage(SettingsKey.theme) private var themeID = Theme.classic.id
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var theme: Theme { Theme.named(themeID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: chatStyle ? 8 : 2) {
                        if session.console.isEmpty {
                            empty
                        }
                        ForEach(session.console) { entry in
                            if chatStyle {
                                Bubble(entry: entry, theme: theme)
                            } else {
                                PlainLine(entry: entry)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                    .textSelection(.enabled)
                }
                .onChange(of: session.consoleRevision) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            if session.inputRequest != nil {
                inputBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.inputRequest != nil)
        .onChange(of: session.inputRequest != nil) { _, waiting in
            if waiting { inputFocused = true }
        }
    }

    var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Run the program to see its output here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    var inputBar: some View {
        let request = session.inputRequest
        return VStack(alignment: .leading, spacing: 6) {
            if let request {
                Text("Enter a value for \(request.variable) (\(ShapeText.typeName(request.type)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("Value", text: $input)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.bar)
    }

    func submit() {
        session.submitInput(input)
        input = ""
    }
}

private struct Bubble: View {
    let entry: ConsoleEntry
    let theme: Theme

    var body: some View {
        switch entry.kind {
        case .output:
            HStack {
                text(Theme.modern.palette(for: .output).fill)
                Spacer(minLength: 40)
            }
        case .input:
            HStack {
                Spacer(minLength: 40)
                text(Theme.modern.palette(for: .input).fill)
            }
        case .error:
            notice(entry.text, systemImage: "exclamationmark.octagon.fill", color: .red)
        case .warning:
            notice(entry.text, systemImage: "exclamationmark.triangle.fill", color: .orange)
        case .info:
            HStack {
                Spacer()
                Text(entry.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    func text(_ color: Color) -> some View {
        Text(entry.text.isEmpty ? " " : entry.text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func notice(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PlainLine: View {
    let entry: ConsoleEntry

    var body: some View {
        Text(entry.text)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var color: Color {
        switch entry.kind {
        case .output: .primary
        case .input: DataType.integer.color
        case .error: .red
        case .warning: .orange
        case .info: .secondary
        }
    }
}
