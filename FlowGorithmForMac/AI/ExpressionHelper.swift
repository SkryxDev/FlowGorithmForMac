// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// What the chart and the shape editor can ask the assistant, provided by the document window.
struct AIActions {
    /// False until the user signs in.
    var isAvailable: Bool
    var ask: (AIRequest) -> Void
}

extension EnvironmentValues {
    @Entry var aiActions: AIActions? = nil
}

/// Fixes the one field the user is typing in the shape editor, without going through the chat:
/// the corrected text goes straight into the field, or, in study mode, a hint goes under it.
/// One request each time.
enum ExpressionHelper {
    struct Failure: LocalizedError {
        var errorDescription: String? { String(localized: "The assistant's version has a mistake too. Try changing it yourself.") }
    }

    static func help(text: String, kind: FieldKind, problem: String,
                     variables: [VariablesSnapshot.Variable], mode: AIMode) async throws -> String {
        guard let key = OpenRouterAccount.shared.key else { throw OpenRouterError.notSignedIn }
        let declared = variables.map { "\($0.name) (\($0.type.rawValue)\($0.elements != nil ? " array" : ""))" }
        let task = mode == .study
            ? "Reply in \(FlowchartTools.replyLanguage) with one short hint, one sentence, about what's wrong, without writing the corrected text. Write names and symbols in `backticks`."
            : "Reply with only the corrected text of the field: no explanation, no quotes around it, no backticks. Keep what the user meant and change as little as possible."
        let system = """
            You fix one field of a shape in Flowgorithm, a flowchart language for students. Expressions: text \
            in double quotes, joined with &; numbers; + - * / mod ^; = <> < <= > >=; and, or, not; \
            parentheses; arrays as name[index], starting at 0; function calls as Name(arguments). Built-in \
            functions: Abs, ArcCos, ArcSin, ArcTan, Char, Cos, Int, Len, Log, Log10, Random, Sgn, Sin, Size, \
            Sqrt, Tan, ToChar, ToCode, ToFixed, ToInteger, ToReal, ToString. Names are letters and digits \
            only. \(task)
            """
        let user = """
            Field: \(description(of: kind))
            Declared variables: \(declared.isEmpty ? "none" : declared.joined(separator: ", "))
            Text: \(text)
            The app says: \(problem)
            """
        let reply = try await OpenRouterClient.complete(messages: [["role": "system", "content": .string(system)],
                                                                   ["role": "user", "content": .string(user)]],
                                                        tools: [], key: key)
        await OpenRouterAccount.shared.refreshUsage()
        let answer = AIChat.text(of: reply.message["content"])
        guard !answer.isEmpty else { throw OpenRouterError.emptyReply }
        if mode == .study { return answer }
        let fixed = cleaned(answer)
        guard isValid(fixed, kind: kind) else { throw Failure() }
        return fixed
    }

    private static func description(of kind: FieldKind) -> String {
        switch kind {
        case .variable: "a variable name, or an array element such as list[i]"
        case .names: "variable names separated by commas"
        case .call: "a call to a function, such as Greet(name)"
        default: "an expression"
        }
    }

    /// The answer without the wrapping models add anyway: a code fence, backticks, a label.
    static func cleaned(_ answer: String) -> String {
        var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = String(text.drop { $0 != "\n" }.dropFirst())
            if let fence = text.range(of: "```", options: .backwards) { text = String(text[..<fence.lowerBound]) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 1, text.hasPrefix("`"), text.hasSuffix("`") { text = String(text.dropFirst().dropLast()) }
        // A one-line answer is the field; a longer one keeps only its first line.
        return text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    static func isValid(_ text: String, kind: FieldKind) -> Bool {
        guard !text.isEmpty else { return false }
        switch kind {
        case .variable: return (try? ExpressionParser.parseLValue(text)) != nil
        case .call: return (try? ExpressionParser.parseCall(text)) != nil
        case .names: return text.split(separator: ",").allSatisfy { Identifier.validate($0.trimmingCharacters(in: .whitespaces)) == nil }
        case .text: return true
        case .expression, .optionalExpression: return (try? ExpressionParser.parse(text)) != nil
        }
    }
}
