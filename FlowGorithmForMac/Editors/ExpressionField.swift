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
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: problem)
    }

    func insert(_ name: String) {
        if kind == .variable || text.trimmingCharacters(in: .whitespaces).isEmpty {
            text = name
        } else {
            text += (text.hasSuffix(" ") ? "" : " ") + name
        }
    }
}
