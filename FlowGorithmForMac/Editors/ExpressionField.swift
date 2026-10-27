// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// What a text field holds, which decides how it's checked.
enum FieldKind {
    case expression, variable, names, call, optionalExpression, text
}

/// A labeled text field that checks its content as you type and offers declared variables.
struct ExpressionField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var kind: FieldKind = .expression
    var prompt: LocalizedStringKey?
    var variables: [VariablesSnapshot.Variable] = []

    @FocusState private var focused: Bool
    @AppStorage(SettingsKey.aiMode) private var aiMode = AIMode.auto.rawValue
    @State private var helping = false
    /// A hint from the assistant in study mode, or why it couldn't help.
    @State private var aiNote: (text: String, failed: Bool)?

    var problem: String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .text:
            return nil
        case .optionalExpression where trimmed.isEmpty:
            return nil
        case .expression, .optionalExpression:
            if trimmed.isEmpty { return nil }
            do { _ = try ExpressionParser.parse(text) } catch { return ErrorText.syntax(error, source: text) }
        case .variable:
            if trimmed.isEmpty { return nil }
            do { _ = try ExpressionParser.parseLValue(text) } catch { return ErrorText.syntax(error, source: text) }
        case .call:
            if trimmed.isEmpty { return nil }
            do { _ = try ExpressionParser.parseCall(text) } catch { return ErrorText.syntax(error, source: text) }
        case .names:
            for name in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if let problem = Identifier.validate(name) {
                    return ErrorText.message(RuntimeError(.invalidName(name, problem)))
                }
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(title, text: $text, prompt: prompt.map { Text($0) }, axis: kind == .text ? .vertical : .horizontal)
                    .textFieldStyle(.plain)
                    .font(kind == .text ? .body : .system(.body, design: .monospaced))
                    .lineLimit(kind == .text ? 3...8 : 1...1)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(problem != nil ? Color.red.opacity(0.7) : (focused ? Color.accentColor : Color.secondary.opacity(0.25)),
                                lineWidth: focused || problem != nil ? 1.5 : 1))
                if !variables.isEmpty && kind != .names && kind != .text {
                    Menu {
                        ForEach(variables) { variable in
                            Button {
                                insert(variable.name)
                            } label: {
                                Text("\(variable.name)  ·  \(ShapeText.typeName(variable.type))\(variable.elements != nil ? "[]" : "")")
                            }
                        }
                    } label: {
                        Image(systemName: "x.squareroot")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Insert a variable")
                }
            }
            if let problem {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if OpenRouterAccount.shared.status == .signedIn {
                        aiButton(problem)
                    }
                }
                .transition(.opacity)
            }
            if let aiNote {
                Label {
                    Text(MarkdownText.inline(aiNote.text))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: aiNote.failed ? "exclamationmark.bubble" : "graduationcap.fill")
                }
                .font(.caption)
                .foregroundStyle(aiNote.failed ? AnyShapeStyle(.secondary) : AnyShapeStyle(AIMode.study.color))
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: problem)
        .animation(.snappy(duration: 0.2), value: aiNote?.text)
        .onChange(of: text) { if !helping { aiNote = nil } }
    }

    var mode: AIMode { AIMode(rawValue: aiMode) ?? .auto }

    @ViewBuilder
    func aiButton(_ problem: String) -> some View {
        if helping {
            ProgressView().controlSize(.mini)
        } else {
            Button {
                askAssistant(problem)
            } label: {
                Label(mode == .study ? "Hint" : "Fix with AI", systemImage: mode == .study ? "graduationcap" : "sparkles")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
            .help(mode == .study ? "Ask the assistant for a hint about this mistake" : "Let the assistant correct this field")
        }
    }

    func askAssistant(_ problem: String) {
        helping = true
        aiNote = nil
        let request = (text, kind, variables, mode)
        Task {
            defer { helping = false }
            do {
                let answer = try await ExpressionHelper.help(text: request.0, kind: request.1, problem: problem,
                                                             variables: request.2, mode: request.3)
                if request.3 == .study {
                    aiNote = (answer, false)
                } else {
                    text = answer
                }
            } catch {
                aiNote = (error.localizedDescription, true)
            }
        }
    }

    func insert(_ name: String) {
        if kind == .variable || text.trimmingCharacters(in: .whitespaces).isEmpty {
            text = name
        } else {
            text += (text.hasSuffix(" ") ? "" : " ") + name
        }
    }
}
