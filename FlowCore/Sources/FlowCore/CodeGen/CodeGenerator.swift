// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

public enum SourceLanguage: String, CaseIterable, Identifiable, Sendable {
    case pseudocodeItalian, pseudocodeEnglish, python, java, cpp, csharp, javascript, typescript, swift, kotlin

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pseudocodeItalian: "Pseudocodice"
        case .pseudocodeEnglish: "Pseudocode"
        case .python: "Python"
        case .java: "Java"
        case .cpp: "C++"
        case .csharp: "C#"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .swift: "Swift"
        case .kotlin: "Kotlin"
        }
    }

    public var fileExtension: String {
        switch self {
        case .pseudocodeItalian, .pseudocodeEnglish: "txt"
        case .python: "py"
        case .java: "java"
        case .cpp: "cpp"
        case .csharp: "cs"
        case .javascript: "js"
        case .typescript: "ts"
        case .swift: "swift"
        case .kotlin: "kt"
        }
    }
}

/// Source code produced from a flowchart, line by line, each line tagged with the shape it came from.
public struct GeneratedSource: Sendable, Hashable {
    public struct Line: Sendable, Hashable, Identifiable {
        public var id: Int
        public var text: String
        public var statementID: Statement.ID?
        public var category: ShapeCategory?
    }

    public var lines: [Line]
    public var text: String { lines.map(\.text).joined(separator: "\n") + "\n" }
}

public enum CodeGenerator {
    public static func generate(_ program: Program, language: SourceLanguage) -> GeneratedSource {
        let emitter: Emitter = switch language {
        case .pseudocodeItalian: PseudocodeEmitter(program: program, italian: true)
        case .pseudocodeEnglish: PseudocodeEmitter(program: program, italian: false)
        case .python: PythonEmitter(program: program)
        case .java: JavaEmitter(program: program)
        case .cpp: CppEmitter(program: program)
        case .csharp: CSharpEmitter(program: program)
        case .javascript: JavaScriptEmitter(program: program, typed: false)
        case .typescript: JavaScriptEmitter(program: program, typed: true)
        case .swift: SwiftEmitter(program: program)
        case .kotlin: KotlinEmitter(program: program)
        }
        emitter.emitProgram()
        return GeneratedSource(lines: emitter.lines.enumerated().map { index, line in
            GeneratedSource.Line(id: index, text: line.text, statementID: line.statementID, category: line.category)
        })
    }
}

/// The shared machinery: an indenting line writer, type inference and precedence-aware expression rendering.
/// Each language subclasses it and overrides the hooks it needs.
class Emitter {
    struct OutLine {
        var text: String
        var statementID: Statement.ID?
        var category: ShapeCategory?
    }

    struct Symbol {
        var type: DataType
        var isArray: Bool
    }

    /// A rendered expression and the precedence of its outermost operator.
    struct Rendered {
        var text: String
        var precedence: Int
    }

    static let atom = 100

    let program: Program
    var lines: [OutLine] = []
    var indentLevel = 0
    var indentUnit: String { "    " }
    var currentStatement: Statement?
    var currentFunction: Function?
    var symbols: [String: Symbol] = [:]
    /// Declared spelling of each variable of the current function, by lowercased name.
    var spellings: [String: String] = [:]
    /// Features used by the program, so imports and helpers are only emitted when needed.
    var uses: Set<String> = []

    init(program: Program) {
        self.program = program
        scan()
    }

    // MARK: Writer

    func line(_ text: String) {
        let indented = text.isEmpty ? "" : String(repeating: indentUnit, count: indentLevel) + text
        lines.append(OutLine(text: indented, statementID: currentStatement?.id, category: currentStatement?.category))
    }

    func blank() {
        if let last = lines.last, last.text.isEmpty { return }
        lines.append(OutLine(text: ""))
    }

    func indented(_ body: () -> Void) {
        indentLevel += 1
        body()
        indentLevel -= 1
    }

    func tagged(_ statement: Statement, _ body: () -> Void) {
        let previous = currentStatement
        currentStatement = statement
        body()
        currentStatement = previous
    }

    func untagged(_ body: () -> Void) {
        let previous = currentStatement
        currentStatement = nil
        body()
        currentStatement = previous
    }

    // MARK: Program structure

    func emitProgram() {}

    var mainFunction: Function? { program.main }
    var otherFunctions: [Function] { program.functions.filter { $0.id != program.main?.id } }

    func enter(_ function: Function) {
        currentFunction = function
        symbols = [:]
        spellings = [:]
        for parameter in function.parameters {
            let key = parameter.name.lowercased()
            symbols[key] = Symbol(type: parameter.type, isArray: parameter.isArray)
            if spellings[key] == nil { spellings[key] = parameter.name }
        }
        for statement in function.body.flattened {
            if case .declare(let d) = statement.kind {
                for name in d.nameList {
                    let key = name.lowercased()
                    symbols[key] = Symbol(type: d.type, isArray: d.isArray)
                    if spellings[key] == nil { spellings[key] = name }
                }
            }
        }
    }

    func emitBlock(_ block: [Statement]) {
        for statement in block {
            tagged(statement) { emit(statement) }
        }
    }

    func emit(_ statement: Statement) {
        switch statement.kind {
        case .declare(let s): emitDeclare(s)
        case .assign(let s): emitAssign(s)
        case .input(let s): emitInput(s)
        case .output(let s): emitOutput(s)
        case .if(let s): emitIf(s)
        case .while(let s): emitWhile(s)
        case .do(let s): emitDo(s)
        case .for(let s): emitFor(s)
        case .call(let s): emitCall(s)
        case .comment(let s): emitComment(s.text)
        case .breakpoint: emitComment("Breakpoint")
        case .open(let s): emitOpen(s)
        case .close: emitClose()
        case .read(let s): emitRead(s)
        case .write(let s): emitWrite(s)
        case .turn(let s): emitTurtle("Turn \(s.direction.rawValue) \(s.expression)")
        case .forward(let s): emitTurtle("Forward \(s.expression)\(s.penDown ? "" : " (pen up)")")
        case .home: emitTurtle("Home")
        case .clear: emitTurtle("Clear")
        case .pen(let s): emitTurtle("Pen \(s.color.rawValue)")
        case .unknown: emitComment("?")
        }
    }

    func emitDeclare(_ s: Statement.Declare) {}
    func emitAssign(_ s: Statement.Assign) {}
    func emitInput(_ s: Statement.Input) {}
    func emitOutput(_ s: Statement.Output) {}
    func emitIf(_ s: Statement.If) {}
    func emitWhile(_ s: Statement.While) {}
    func emitDo(_ s: Statement.DoLoop) {}
    func emitFor(_ s: Statement.ForLoop) {}
    func emitCall(_ s: Statement.Call) {}
    func emitComment(_ text: String) {}
    func emitOpen(_ s: Statement.OpenFile) { emitComment("Open \(s.expression) (\(s.mode.rawValue))") }
    func emitClose() { emitComment("Close") }
    func emitRead(_ s: Statement.ReadFile) { emitComment("Read \(s.variable)") }
    func emitWrite(_ s: Statement.WriteFile) { emitComment("Write \(s.expression)") }
    func emitTurtle(_ description: String) { emitComment("Turtle: \(description)") }

    // MARK: Expressions

    func parse(_ source: String) -> Expr? { try? ExpressionParser.parse(source) }

    func parseTarget(_ source: String) -> LValue? { try? ExpressionParser.parseLValue(source) }

    /// Renders an expression, or keeps the original text if it doesn't parse.
    func expr(_ source: String) -> String {
        guard let parsed = parse(source) else { return source }
        return render(parsed).text
    }

    func target(_ source: String) -> String {
        guard let lvalue = parseTarget(source) else { return source }
        if let index = lvalue.index { return "\(name(lvalue.name))[\(render(index).text)]" }
        return name(lvalue.name)
    }

    func targetType(_ source: String) -> DataType {
        guard let lvalue = parseTarget(source) else { return .string }
        return symbols[lvalue.name.lowercased()]?.type ?? .string
    }

    /// Words the target language reserves, and names the generated code uses itself.
    var reservedNames: Set<String> { [] }

    /// A flowchart name that is a keyword here (`class` in Java, say) gets a trailing underscore.
    /// Flowchart names can't contain underscores, so the result never collides with another name.
    func identifier(_ raw: String) -> String {
        reservedNames.contains(raw) ? raw + "_" : raw
    }

    /// The declared spelling of a variable (identifiers are case-insensitive in flowcharts, not in most languages).
    func name(_ raw: String) -> String {
        identifier(spellings[raw.lowercased()] ?? raw)
    }

    func functionName(_ raw: String) -> String {
        identifier(program.function(named: raw)?.name ?? raw)
    }

    func type(of expr: Expr) -> DataType? {
        switch expr {
        case .integer: return .integer
        case .real, .pi: return .real
        case .string: return .string
        case .boolean: return .boolean
        case .group(let inner): return type(of: inner)
        case .variable(let n), .element(let n, _): return symbols[n.lowercased()]?.type
        case .call(let n, let args):
            switch n.lowercased() {
            case "abs": return args.first.flatMap(type(of:)) ?? .real
            case "int", "len", "random", "sgn", "size", "tocode", "tointeger": return .integer
            case "char", "tochar", "tofixed", "tostring": return .string
            case "eof": return .boolean
            case "toreal", "arccos", "arcsin", "arctan", "cos", "sin", "tan", "ln", "log", "log10", "sqrt": return .real
            default: return program.function(named: n)?.returnType
            }
        case .unary(.not, _): return .boolean
        case .unary(_, let operand): return type(of: operand)
        case .binary(let op, let l, let r):
            switch op {
            case .concat: return .string
            case .divide, .power: return .real
            case .plus, .minus, .times, .modulo:
                return type(of: l) == .integer && type(of: r) == .integer ? .integer : .real
            default: return .boolean
            }
        }
    }

    func isInteger(_ e: Expr) -> Bool { type(of: e) == .integer }

    // Precedence levels; languages adjust them by overriding `precedence(of:)`.
    func precedence(of op: Operator) -> Int {
        switch op {
        case .or: 1
        case .and: 2
        case .equal, .notEqual: 3
        case .less, .lessEqual, .greater, .greaterEqual: 4
        case .concat, .plus, .minus: 5
        case .times, .divide, .modulo: 6
        case .not: 7
        case .power: 8
        }
    }

    var unaryMinusPrecedence: Int { 7 }

    func operatorText(_ op: Operator) -> String {
        switch op {
        case .plus: "+"
        case .minus: "-"
        case .times: "*"
        case .divide: "/"
        case .modulo: "%"
        case .power: "^"
        case .concat: "+"
        case .equal: "=="
        case .notEqual: "!="
        case .less: "<"
        case .lessEqual: "<="
        case .greater: ">"
        case .greaterEqual: ">="
        case .and: "&&"
        case .or: "||"
        case .not: "!"
        }
    }

    func wrap(_ r: Rendered, below minimum: Int) -> String {
        r.precedence < minimum ? "(\(r.text))" : r.text
    }

    func infix(_ op: Operator, _ l: Expr, _ r: Expr, text: String? = nil) -> Rendered {
        let p = precedence(of: op)
        let left = render(l), right = render(r)
        let rightAssociative = op == .power
        let lhs = wrap(left, below: rightAssociative ? p + 1 : p)
        let rhs = wrap(right, below: rightAssociative ? p : p + 1)
        return Rendered(text: "\(lhs) \(text ?? operatorText(op)) \(rhs)", precedence: p)
    }

    func call(_ function: String, _ args: [String]) -> Rendered {
        Rendered(text: "\(function)(\(args.joined(separator: ", ")))", precedence: Emitter.atom)
    }

    func stringLiteral(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(c)
            }
        }
        return out + "\""
    }

    func boolLiteral(_ b: Bool) -> String { b ? "true" : "false" }

    func realLiteral(_ d: Double) -> String {
        var text = Value.format(d)
        if !text.contains(".") && !text.contains("E") && !text.contains("e") { text += ".0" }
        return text
    }

    var piText: String { "Math.PI" }

    func render(_ e: Expr) -> Rendered {
        switch e {
        case .integer(let v): return Rendered(text: String(v), precedence: Emitter.atom)
        case .real(let v): return Rendered(text: realLiteral(v), precedence: Emitter.atom)
        case .string(let s): return Rendered(text: stringLiteral(s), precedence: Emitter.atom)
        case .boolean(let b): return Rendered(text: boolLiteral(b), precedence: Emitter.atom)
        case .pi: return Rendered(text: piText, precedence: Emitter.atom)
        case .group(let inner):
            let r = render(inner)
            return r.precedence == Emitter.atom ? r : Rendered(text: "(\(r.text))", precedence: Emitter.atom)
        case .variable(let n): return Rendered(text: name(n), precedence: Emitter.atom)
        case .element(let n, let index): return Rendered(text: "\(name(n))[\(render(index).text)]", precedence: Emitter.atom)
        case .call(let n, let args):
            if Identifier.intrinsicNames.contains(n.lowercased()) { return intrinsic(n.lowercased(), args) }
            return userCall(n, args)
        case .unary(.not, let operand):
            let p = precedence(of: .not)
            return Rendered(text: "\(operatorText(.not))\(wrap(render(operand), below: p))", precedence: p)
        case .unary(_, let operand):
            let p = unaryMinusPrecedence
            return Rendered(text: "-\(wrap(render(operand), below: p))", precedence: p)
        case .binary(let op, let l, let r):
            return binary(op, l, r)
        }
    }

    func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        switch op {
        case .concat: concat(flattenConcat(.binary(.concat, l, r)))
        default: infix(op, l, r)
        }
    }

    func flattenConcat(_ e: Expr) -> [Expr] {
        if case .binary(.concat, let l, let r) = e { return flattenConcat(l) + flattenConcat(r) }
        return [e]
    }

    /// Default concatenation for languages where `"" + x` converts to text (Java, C#, JavaScript, Kotlin).
    func concat(_ parts: [Expr]) -> Rendered {
        let p = precedence(of: .plus)
        var texts = parts.map { wrap(render($0), below: p + 1) }
        if parts.count >= 1, type(of: parts[0]) != .string {
            if parts.count < 2 || type(of: parts[1]) != .string { texts.insert("\"\"", at: 0) }
        }
        return Rendered(text: texts.joined(separator: " + "), precedence: p)
    }

    func userCall(_ n: String, _ args: [Expr]) -> Rendered {
        call(functionName(n), args.map { render($0).text })
    }

    func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        call(n, args.map { render($0).text })
    }

    func arg(_ args: [Expr], _ i: Int) -> String {
        i < args.count ? render(args[i]).text : ""
    }

    func argAtom(_ args: [Expr], _ i: Int) -> String {
        i < args.count ? wrap(render(args[i]), below: Emitter.atom) : ""
    }

    // MARK: Helpers for statements

    func forParts(_ s: Statement.ForLoop) -> (variable: String, start: String, end: String, step: String, stepIsOne: Bool) {
        let step = s.step.trimmingCharacters(in: .whitespaces)
        let stepText = step.isEmpty ? "1" : expr(step)
        return (target(s.variable), expr(s.start), expr(s.end), stepText, stepText == "1")
    }

    func commentLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func scan() {
        for function in program.functions {
            for statement in function.body.flattened {
                switch statement.kind {
                case .turn, .forward, .home, .clear, .pen: uses.insert("turtle")
                case .open, .close, .read, .write: uses.insert("file")
                case .input: uses.insert("input")
                default: break
                }
            }
        }
        // Imports depend on which built-in functions appear, so look through every expression once.
        let allText = program.functions.flatMap(\.body.flattened).map(\.expressionText).joined(separator: " ").lowercased()
        for name in ["random", "sqrt", "sin", "cos", "tan", "arc", "log", "ln(", "pi", "^", "tofixed", "eof", "abs", "int(", "sgn", "mod", "%"] where allText.contains(name) {
            uses.insert(name)
        }
        if allText.contains("π") { uses.insert("pi") }
    }
}

extension Statement {
    /// The expressions typed into this shape (not those of nested shapes).
    var expressionText: String {
        switch kind {
        case .declare(let s): s.size
        case .assign(let s): s.variable + " " + s.expression
        case .input(let s): s.variable
        case .output(let s): s.expression
        case .if(let s): s.expression
        case .while(let s): s.expression
        case .do(let s): s.expression
        case .for(let s): [s.variable, s.start, s.end, s.step].joined(separator: " ")
        case .call(let s): s.expression
        case .breakpoint(let s): s.expression
        case .open(let s): s.expression
        case .read(let s): s.variable
        case .write(let s): s.expression
        case .turn(let s): s.expression
        case .forward(let s): s.expression
        case .comment, .close, .home, .clear, .pen, .unknown: ""
        }
    }
}
