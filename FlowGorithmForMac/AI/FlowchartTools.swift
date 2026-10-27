// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// What a tool needs to read and change the open flowchart.
struct ToolContext {
    var program: Binding<Program>
    var editor: EditorModel
    /// True while the program runs: the chart can't change then.
    var locked: Bool
}

struct ToolOutcome {
    /// What the model reads back.
    var output: String
    /// What the chat shows, when the chart changed.
    var summary: String?
}

/// The flowchart as the model sees it, and the functions it calls to change it.
/// Shapes travel as `.fprg` XML, the same format as files and the clipboard, and are
/// named with short ids (s1, s2…) that stay the same for the whole conversation.
final class FlowchartTools {
    private var shortIDs: [Statement.ID: String] = [:]
    private var statementIDs: [String: Statement.ID] = [:]
    private var counter = 0

    private struct ToolError: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }

    func reset() {
        shortIDs = [:]
        statementIDs = [:]
        counter = 0
    }

    func shortID(_ id: Statement.ID) -> String {
        if let existing = shortIDs[id] { return existing }
        counter += 1
        let name = "s\(counter)"
        shortIDs[id] = name
        statementIDs[name] = id
        return name
    }

    // MARK: Listing

    func listing(_ program: Program) -> String {
        var out = ""
        if !program.name.isEmpty { out += "Program name: \(program.name)\n" }
        if !program.about.isEmpty { out += "Description: \(program.about)\n" }
        for function in program.functions {
            out += "<function name=\"\(Self.escape(function.name))\" type=\"\(function.returnType?.rawValue ?? "None")\" variable=\"\(Self.escape(function.returnVariable))\">\n"
            for parameter in function.parameters {
                out += "    <parameter name=\"\(Self.escape(parameter.name))\" type=\"\(parameter.type.rawValue)\" array=\"\(parameter.isArray ? "True" : "False")\"/>\n"
            }
            let body = FPRGWriter.fragment(function.body) { [unowned self] in shortID($0.id) }
            out += body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "    " + $0 }.joined(separator: "\n")
            out += "</function>\n"
        }
        return out
    }

    /// The app's language, in English ("Italian"), which every reply uses whatever language the
    /// user writes in: the one chosen in Settings, or the system's.
    static var replyLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    static func instructions(listing: String) -> String {
        """
        You are the assistant inside FlowGorithmForMac, a Mac app where students write and run programs as \
        flowcharts, compatible with Flowgorithm. The flowchart open in the app is shown below and is always up \
        to date.

        Answer questions about it (what it does, why it fails, how to improve it) and change it when the user \
        asks, using the flowchart tools: never paste XML in your reply for the user to copy. Make the smallest \
        change that does what was asked and keep the user's shapes. Always reply in \(replyLanguage), even when \
        the user writes in another language, briefly and \
        in plain words.

        Each reply costs the user one of a few daily requests, so do the whole job in this one reply: call \
        every tool you need at once, and in the same reply tell the user in one or two sentences what you \
        changed. You only hear back if a change fails. An if or a loop can be inserted together with the \
        shapes inside it.

        Shapes are .fprg XML elements, one per shape:
        <declare name="x, y" type="Integer" array="False" size=""/>  types: Integer, Real, String, Boolean; arrays: array="True" size="10"
        <assign variable="x" expression="x + 1"/>
        <input variable="x"/>
        <output expression="&quot;Total: &quot; &amp; x" newline="True"/>
        <if expression="x &gt; 0"><then>shapes</then><else>shapes</else></if>
        <while expression="i &lt; 10">shapes</while>
        <do expression="again = &quot;yes&quot;">shapes</do>  (runs once, then repeats while the condition is true)
        <for variable="i" start="1" end="10" direction="inc" step="1">shapes</for>  direction: inc or dec
        <call expression="DrawBox(3)"/>
        <comment text="Explains the next shapes"/>
        <breakpoint expression="" always="True"/>
        Files: <open expression="&quot;data.txt&quot;" mode="read"/> (read, write, append) <read variable="line"/> \
        <write expression="line"/> <close mode="read"/>
        Turtle: <forward expression="50" pen="down"/> <turn expression="90" rotate="right"/> <home/> <clear/> <pen color="red"/>
        Attribute values are XML: write " as &quot;, & as &amp;, < as &lt;, > as &gt;.

        Pick the type that fits each variable: Integer or Real for numbers, String for text, Boolean for yes/no \
        answers (the user types true or false). Expressions follow Flowgorithm: declare every variable before \
        using it; text in double quotes, joined \
        with &; + - * / (real division), mod, ^ (power); = <> < <= > >=; and, or, not. Built-in functions: Abs, \
        ArcCos, ArcSin, ArcTan, Char(text, index), Cos, Int, Len, Log, Log10, Random(n), Sgn, Sin, Size(array), \
        Sqrt, Tan, ToChar, ToCode, ToFixed(real, digits), ToInteger, ToReal, ToString, Eof. Arrays and \
        Char start at 0. Names are letters and digits only (no _ or spaces) and ignore case. Each variable is \
        declared once: before adding a Declare, look for one that already has the name and change it instead. Conditions are \
        expressions, never plain words: combine them with and / or in one if. A function that returns a value \
        declares its return variable in its own body and assigns it. Main is where the program starts.

        Every shape below has an id (s1, s2…): use them with the tools and never invent one. The ids are not \
        part of the program; don't mention them to the user.

        Current flowchart:
        \(listing)
        """
    }

    // MARK: Definitions

    static var definitions: [JSON] {
        let position: JSON = ["type": "string", "enum": ["after", "before", "start_of_function", "end_of_function",
                                                        "start_of_branch", "end_of_branch"],
                              "description": "Where the shapes go. after/before: next to target_id. start_of_branch/end_of_branch: inside the if or loop target_id, in branch. start/end_of_function: in the body of function."]
        let target: JSON = ["type": "string", "description": "A shape id such as s4. Needed for after, before and the branch positions."]
        let branch: JSON = ["type": "string", "enum": ["then", "else", "body"],
                            "description": "then or else for an if, body for a loop. Defaults to then/body."]
        let function: JSON = ["type": "string", "description": "Function name, for the start_of_function and end_of_function positions. Defaults to Main."]
        let types: JSON = ["type": "string", "enum": ["Integer", "Real", "String", "Boolean"]]

        return [
            tool("insert_shapes", "Insert one or more shapes, written as .fprg XML elements in order. Ifs and loops can contain their shapes.",
                 ["xml": ["type": "string", "description": "The shapes, e.g. <output expression=\"&quot;Well done!&quot;\" newline=\"True\"/>"],
                  "position": position, "target_id": target, "branch": branch, "function": function],
                 required: ["xml", "position"]),
            tool("update_shape", "Replace one shape with a new .fprg XML element. For an if or a loop, leave its children out to keep the shapes already inside it.",
                 ["id": ["type": "string"], "xml": ["type": "string"]],
                 required: ["id", "xml"]),
            tool("delete_shapes", "Delete shapes, with everything inside them.",
                 ["ids": ["type": "array", "items": ["type": "string"]]],
                 required: ["ids"]),
            tool("move_shape", "Move a shape, with everything inside it, to another place in the same function.",
                 ["id": ["type": "string"], "position": position, "target_id": target, "branch": branch],
                 required: ["id", "position"]),
            tool("add_function", "Add a new empty function; fill it in the same reply with insert_shapes at end_of_function.",
                 ["name": ["type": "string"],
                  "return_type": ["type": "string", "enum": ["None", "Integer", "Real", "String", "Boolean"]],
                  "return_variable": ["type": "string", "description": "Empty when return_type is None."],
                  "parameters": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["name": ["type": "string"], "type": types, "array": ["type": "boolean"]],
                    "required": ["name", "type", "array"],
                    "additionalProperties": false]]],
                 required: ["name", "return_type", "return_variable", "parameters"]),
            tool("delete_function", "Delete a function other than Main.",
                 ["name": ["type": "string"]], required: ["name"]),
            tool("select_shape", "Select and scroll to a shape in the app, to show the user which shape you mean.",
                 ["id": ["type": "string"]], required: ["id"]),
        ]
    }

    /// A tool in the Chat Completions format OpenRouter uses.
    private static func tool(_ name: String, _ description: String, _ properties: [String: JSON], required: [String]) -> JSON {
        ["type": "function",
         "function": ["name": .string(name), "description": .string(description),
                      "parameters": ["type": "object", "properties": .object(properties),
                                     "required": .array(required.map(JSON.string)), "additionalProperties": false]]]
    }

    // MARK: Running

    func run(name: String, arguments: String, context: ToolContext) -> ToolOutcome {
        var args = JSON.parse(Data(arguments.utf8)) ?? [:]
        // Some models encode the arguments twice, as a string holding the JSON object.
        if let inner = args.string, let decoded = JSON.parse(Data(inner.utf8)) { args = decoded }
        do {
            if context.locked && !["select_shape", "check_program"].contains(name) {
                throw ToolError("The program is running, so the chart can't change. Ask the user to stop it first.")
            }
            switch name {
            case "insert_shapes": return try insert(args, context)
            case "update_shape": return try update(args, context)
            case "delete_shapes": return try delete(args, context)
            case "move_shape": return try move(args, context)
            case "add_function": return try addFunction(args, context)
            case "delete_function": return try deleteFunction(args, context)
            case "select_shape": return try select(args, context)
            case "check_program": return check(context)
            default: throw ToolError("Unknown tool \(name).")
            }
        } catch let error as ToolError {
            return ToolOutcome(output: "Error: \(error.message)")
        } catch {
            return ToolOutcome(output: "Error: \(error.localizedDescription)")
        }
    }

    private func insert(_ args: JSON, _ context: ToolContext) throws -> ToolOutcome {
        let shapes = try parse(args["xml"]?.string)
        var program = context.program.wrappedValue
        let (index, point) = try insertionPoint(args, in: program)
        for (offset, shape) in shapes.enumerated() {
            program.functions[index].body.insert(shape, at: InsertionPoint(block: point.block, index: point.index + offset))
        }
        context.program.wrappedValue = program
        show(shapes.last?.id, in: program.functions[index], context)
        let names = shapes.flatMap { [$0] + $0.blocks.flatMap(\.flattened) }.map { shortID($0.id) }
        let count = shapes.flatMap { [$0] + $0.blocks.flatMap(\.flattened) }.count
        return ToolOutcome(output: "Inserted \(names.joined(separator: ", ")) in \(program.functions[index].name)." + problems(in: shapes),
                           summary: count == 1 ? String(localized: "Added a shape") : String(localized: "Added \(count) shapes"))
    }

    private func update(_ args: JSON, _ context: ToolContext) throws -> ToolOutcome {
        let (id, functionIndex) = try find(args["id"]?.string, in: context.program.wrappedValue)
        let shapes = try parse(args["xml"]?.string)
        guard shapes.count == 1 else { throw ToolError("update_shape takes exactly one element.") }
        var program = context.program.wrappedValue
        guard let original = program.functions[functionIndex].body.statement(withID: id) else { throw ToolError("Shape not found.") }
        var updated = shapes[0]
        updated.id = original.id
        // Without children in the XML, the shapes already inside an if or loop stay.
        if updated.blocks.count == original.blocks.count, updated.blocks.allSatisfy(\.isEmpty) {
            updated.blocks = original.blocks
        }
        program.functions[functionIndex].body.replaceStatement(updated)
        context.program.wrappedValue = program
        show(id, in: program.functions[functionIndex], context)
        return ToolOutcome(output: "Updated \(shortID(id))." + problems(in: [updated]), summary: String(localized: "Changed a shape"))
    }

    private func delete(_ args: JSON, _ context: ToolContext) throws -> ToolOutcome {
        let names = args["ids"]?.array?.compactMap(\.string) ?? []
        guard !names.isEmpty else { throw ToolError("No ids given.") }
        var program = context.program.wrappedValue
        var removed = 0
        for name in names {
            let (id, functionIndex) = try find(name, in: program)
            if let shape = program.functions[functionIndex].body.removeStatement(withID: id) {
                removed += 1 + shape.blocks.flatMap(\.flattened).count
            }
        }
        context.program.wrappedValue = program
        if let selection = context.editor.selection, program.functions.allSatisfy({ $0.body.statement(withID: selection) == nil }) {
            context.editor.selection = nil
        }
        return ToolOutcome(output: "Deleted \(names.joined(separator: ", ")).",
                           summary: removed == 1 ? String(localized: "Deleted a shape") : String(localized: "Deleted \(removed) shapes"))
    }

    private func move(_ args: JSON, _ context: ToolContext) throws -> ToolOutcome {
        let (id, functionIndex) = try find(args["id"]?.string, in: context.program.wrappedValue)
        var program = context.program.wrappedValue
        var target = args
        if case .object(var object) = target, object["function"] == nil {
            object["function"] = .string(program.functions[functionIndex].name)
            target = .object(object)
        }
        let (targetFunction, point) = try insertionPoint(target, in: program)
        guard targetFunction == functionIndex else { throw ToolError("Shapes can only move inside their own function.") }
        guard program.functions[functionIndex].body.moveStatement(withID: id, to: point) else {
            throw ToolError("A shape can't move inside itself.")
        }
        context.program.wrappedValue = program
        show(id, in: program.functions[functionIndex], context)
        return ToolOutcome(output: "Moved \(shortID(id)).", summary: String(localized: "Moved a shape"))
    }

    private func addFunction(_ args: JSON, _ context: ToolContext) throws -> ToolOutcome {
        let name = (args["name"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        if Identifier.validate(name) != nil { throw ToolError("“\(name)” isn't a valid function name: use letters and digits, starting with a letter, and not a built-in name.") }
        var program = context.program.wrappedValue
        if program.function(named: name) != nil { throw ToolError("A function named \(name) already exists.") }
        let returnType = DataType(rawValue: args["return_type"]?.string ?? "None")
        var parameters: [Parameter] = []
        for item in args["parameters"]?.array ?? [] {
            let parameterName = item["name"]?.string ?? ""
            guard Identifier.validate(parameterName) == nil, let type = DataType(rawValue: item["type"]?.string ?? "") else {
                throw ToolError("Invalid parameter “\(parameterName)”.")
            }
            parameters.append(Parameter(name: parameterName, type: type, isArray: item["array"]?.bool ?? false))
        }
        let function = Function(name: name, returnType: returnType,
                                returnVariable: returnType == nil ? "" : (args["return_variable"]?.string ?? ""),
                                parameters: parameters)
        program.functions.append(function)
        context.program.wrappedValue = program
        context.editor.functionID = function.id
        context.editor.selection = nil
        return ToolOutcome(output: "Added the function \(name). Its body is empty: fill it with insert_shapes at end_of_function.",
                           summary: String(localized: "Added the function \(name)"))
    }

    private func deleteFunction(_ args: JSON, _ context: ToolContext) throws -> ToolOutcome {
        let name = args["name"]?.string ?? ""
        var program = context.program.wrappedValue
        guard let function = program.function(named: name) else { throw ToolError("There's no function named \(name).") }
        guard !function.isMain else { throw ToolError("Main can't be deleted.") }
        program.functions.removeAll { $0.id == function.id }
        context.program.wrappedValue = program
        if context.editor.functionID == function.id { context.editor.functionID = program.main?.id }
        return ToolOutcome(output: "Deleted the function \(function.name).", summary: String(localized: "Deleted the function \(function.name)"))
    }

    private func select(_ args: JSON, _ context: ToolContext) throws -> ToolOutcome {
        let program = context.program.wrappedValue
        let (id, functionIndex) = try find(args["id"]?.string, in: program)
        show(id, in: program.functions[functionIndex], context)
        return ToolOutcome(output: "Selected \(shortID(id)).")
    }

    private func check(_ context: ToolContext) -> ToolOutcome {
        guard let error = Interpreter.check(context.program.wrappedValue) else {
            return ToolOutcome(output: "No problems found.")
        }
        var place = error.functionName.map { " in \($0)" } ?? ""
        if let id = error.statementID { place += ", shape \(shortID(id))" }
        return ToolOutcome(output: "Problem\(place): \(ErrorText.message(error))")
    }

    // MARK: Helpers

    private func parse(_ xml: String?) throws -> [Statement] {
        var text = Self.repair(xml ?? "")
        guard !text.isEmpty else { throw ToolError("The xml is empty.") }
        if !text.hasPrefix("<body") { text = "<body>\(text)</body>" }
        guard let shapes = FPRGWriter.statements(fromFragment: text), !shapes.isEmpty else {
            throw ToolError("The XML couldn't be read. Check that it's well formed and that attribute values escape \" as &quot;, & as &amp;, < as &lt; and > as &gt;.")
        }
        if let unknown = shapes.flatMap({ [$0] + $0.blocks.flatMap(\.flattened) }).first(where: { $0.template == nil }),
           case .unknown(let xml) = unknown.kind {
            throw ToolError("Unknown element: \(xml.prefix(80)). Use only the shape elements listed in the instructions.")
        }
        return shapes
    }

    /// Fixes the slips models make most often in the XML they write, which would otherwise cost a
    /// request to correct: a Markdown code fence, an XML declaration, a whole function or file
    /// around the shapes, and <, >, & or quotes left unescaped inside attribute values, as in
    /// `expression="x < 5"` or `expression=""Well done!""`.
    static func repair(_ xml: String) -> String {
        var text = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = String(text.drop { $0 != "\n" }.dropFirst())
            if let fence = text.range(of: "```", options: .backwards) { text = String(text[..<fence.lowerBound]) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("<?xml"), let end = text.range(of: "?>") {
            text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !text.hasPrefix("<body"), let start = text.range(of: "<body"), let end = text.range(of: "</body>", options: .backwards),
           start.lowerBound < end.lowerBound {
            text = String(text[start.lowerBound..<end.upperBound])
        }

        var out = ""
        out.reserveCapacity(text.count)
        var inTag = false
        var quote: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                switch character {
                case open where Self.closesValue(text, after: index): quote = nil; out.append(character)
                case open: out += open == "\"" ? "&quot;" : "&apos;"
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                case "&": out += Self.startsEntity(text[index...]) ? "&" : "&amp;"
                default: out.append(character)
                }
            } else if inTag {
                if character == "\"" || character == "'" { quote = character }
                if character == ">" { inTag = false }
                out.append(character)
            } else {
                if character == "<" { inTag = true }
                out.append(character)
            }
            index = text.index(after: index)
        }
        return out
    }

    /// A quote ends an attribute value only when another attribute, `>` or `/>` follows;
    /// otherwise it's part of the text, as in `""Well done!""`.
    private static func closesValue(_ text: String, after index: String.Index) -> Bool {
        var next = text.index(after: index)
        while next < text.endIndex, text[next].isWhitespace { next = text.index(after: next) }
        guard next < text.endIndex else { return true }
        if text[next] == ">" || text[next...].hasPrefix("/>") { return true }
        var end = next
        while end < text.endIndex, text[end].isLetter || text[end].isNumber || "_:-.".contains(text[end]) {
            end = text.index(after: end)
        }
        guard end > next else { return false }
        while end < text.endIndex, text[end].isWhitespace { end = text.index(after: end) }
        return end < text.endIndex && text[end] == "="
    }

    private static func startsEntity(_ text: Substring) -> Bool {
        guard let semicolon = text.prefix(10).firstIndex(of: ";") else { return false }
        let name = text[text.index(after: text.startIndex)..<semicolon]
        if ["amp", "lt", "gt", "quot", "apos"].contains(name) { return true }
        if name.hasPrefix("#x") { return name.count > 2 && name.dropFirst(2).allSatisfy(\.isHexDigit) }
        if name.hasPrefix("#") { return name.count > 1 && name.dropFirst().allSatisfy(\.isNumber) }
        return false
    }

    /// Mistakes the model's changes introduced that only show when the program runs, such as a
    /// variable declared twice. Problems already in the chart before are left alone.
    func newProblems(since before: [LintProblem], in program: Program) -> String? {
        let old = Set(before)
        let found = Linter.problems(in: program).filter { !old.contains($0) }.map { problem -> String in
            let place = problem.statementID.map { "\(shortID($0)) in \(problem.function)" } ?? problem.function
            switch problem.kind {
            case .duplicateDeclaration(let name): return "\(place): \(name) is declared again; declare each variable once"
            case .declaredInLoop(let name): return "\(place): \(name) is declared inside a loop, so the second pass fails; declare it before the loop"
            case .undeclared(let name): return "\(place): \(name) is used but not declared before"
            case .unknownFunction(let name): return "\(place): there's no function named \(name)"
            case .returnVariableNotDeclared(let name): return "\(place): the return variable \(name) is never declared"
            case .typeMismatch(let detail): return "\(place): \(detail)"
            }
        }
        guard !found.isEmpty else { return nil }
        return "The app checked the flowchart after your changes and found mistakes that would stop it when it runs: "
            + found.joined(separator: "; ") + ". Fix them now."
    }

    private func find(_ name: String?, in program: Program) throws -> (Statement.ID, Int) {
        guard let name, let id = statementIDs[name.trimmingCharacters(in: .whitespaces)] else {
            throw ToolError("There's no shape with id \(name ?? "(missing)"). Use the ids in the current flowchart.")
        }
        guard let index = program.functions.firstIndex(where: { $0.body.statement(withID: id) != nil }) else {
            throw ToolError("The shape \(name) isn't in the flowchart anymore.")
        }
        return (id, index)
    }

    private func insertionPoint(_ args: JSON, in program: Program) throws -> (Int, InsertionPoint) {
        let position = args["position"]?.string ?? "end_of_function"
        switch position {
        case "start_of_function", "end_of_function":
            let name = args["function"]?.string ?? "Main"
            guard let index = program.functions.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw ToolError("There's no function named \(name).")
            }
            let count = program.functions[index].body.count
            return (index, InsertionPoint(block: .functionBody, index: position == "start_of_function" ? 0 : count))
        case "after", "before":
            let (id, index) = try find(args["target_id"]?.string, in: program)
            guard let location = program.functions[index].body.location(of: id) else { throw ToolError("Shape not found.") }
            return (index, InsertionPoint(block: location.block, index: location.index + (position == "after" ? 1 : 0)))
        case "start_of_branch", "end_of_branch":
            let (id, index) = try find(args["target_id"]?.string, in: program)
            guard let owner = program.functions[index].body.statement(withID: id), !owner.blocks.isEmpty else {
                throw ToolError("\(args["target_id"]?.string ?? "") isn't an if or a loop.")
            }
            let branch = args["branch"]?.string == "else" ? 1 : 0
            guard branch < owner.blocks.count else { throw ToolError("Only an if has an else branch.") }
            let block = BlockReference(owner: id, branch: branch)
            let count = owner.blocks[branch].count
            return (index, InsertionPoint(block: block, index: position == "start_of_branch" ? 0 : count))
        default:
            throw ToolError("Unknown position \(position).")
        }
    }

    /// Problems the editor would show on the new shapes, so the model can fix them right away.
    private func problems(in shapes: [Statement]) -> String {
        var found: [String] = []
        for shape in shapes.flatMap({ [$0] + $0.blocks.flatMap(\.flattened) }) {
            if let error = shape.validationError {
                found.append("\(shortID(shape.id)): \(ErrorText.message(error))")
            } else if shape.isIncomplete {
                found.append("\(shortID(shape.id)): a required field is empty.")
            }
        }
        return found.isEmpty ? "" : " Fix these problems with update_shape: " + found.joined(separator: "; ")
    }

    /// Shows the changed function and selects the shape, so the user sees what happened.
    private func show(_ id: Statement.ID?, in function: Function, _ context: ToolContext) {
        context.editor.functionID = function.id
        context.editor.selection = id
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
