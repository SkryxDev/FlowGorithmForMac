import Foundation

final class SwiftEmitter: BraceEmitter {
    override var statementEnd: String { "" }

    override func typeName(_ type: DataType) -> String {
        switch type {
        case .integer: "Int"
        case .real: "Double"
        case .string: "String"
        case .boolean: "Bool"
        }
    }

    func defaultValue(_ type: DataType) -> String {
        switch type {
        case .integer: "0"
        case .real: "0.0"
        case .string: "\"\""
        case .boolean: "false"
        }
    }

    override func emitProgram() {
        line("import Foundation")
        blank()
        for function in otherFunctions {
            enter(function)
            let params = function.parameters.map {
                $0.isArray ? "_ \(identifier($0.name)): inout [\(typeName($0.type))]" : "_ \(identifier($0.name)): \(typeName($0.type))"
            }.joined(separator: ", ")
            let returns = function.returnType.map { " -> \(typeName($0))" } ?? ""
            line("func \(functionName(function.name))(\(params))\(returns) {")
            indented {
                // Swift parameters are constants; shadow scalars so the flowchart can change them.
                for parameter in function.parameters where !parameter.isArray {
                    untagged { line("var \(identifier(parameter.name)) = \(identifier(parameter.name))") }
                }
                emitBlock(function.body)
                returnLine(function)
            }
            line("}")
            blank()
        }
        if let main = mainFunction {
            enter(main)
            emitBlock(main.body)
        }
    }

    static let reserved: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout",
        "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public", "rethrows",
        "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue", "default",
        "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw", "switch",
        "where", "while", "Any", "as", "await", "false", "is", "nil", "self", "Self", "super", "throws", "true", "try",
        "print", "readLine", "pow", "stride", "Double", "String", "Bool", "Character", "Array", "Foundation",
    ]

    override var reservedNames: Set<String> { Self.reserved }

    override func emitDeclare(_ s: Statement.Declare) {
        for variable in s.nameList.map({ name($0) }) {
            if s.isArray {
                line("var \(variable) = [\(typeName(s.type))](repeating: \(defaultValue(s.type)), count: \(expr(s.size)))")
            } else {
                line("var \(variable): \(typeName(s.type)) = \(defaultValue(s.type))")
            }
        }
    }

    override func emitInput(_ s: Statement.Input) {
        let read = switch targetType(s.variable) {
        case .integer: "Int(readLine()!)!"
        case .real: "Double(readLine()!)!"
        case .string: "readLine()!"
        case .boolean: "readLine()! == \"true\""
        }
        line("\(target(s.variable)) = \(read)")
    }

    override func emitOutput(_ s: Statement.Output) {
        line(s.newline ? "print(\(expr(s.expression)))" : "print(\(expr(s.expression)), terminator: \"\")")
    }

    override func emitIf(_ s: Statement.If) {
        line("if \(expr(s.expression)) {")
        indented { emitBlock(s.thenBody) }
        if s.elseBody.isEmpty {
            line("}")
        } else {
            line("} else {")
            indented { emitBlock(s.elseBody) }
            line("}")
        }
    }

    override func emitWhile(_ s: Statement.While) {
        braced("while \(expr(s.expression))", s.body)
    }

    override func emitDo(_ s: Statement.DoLoop) {
        line("repeat {")
        indented { emitBlock(s.body) }
        line("} while \(expr(s.expression))")
    }

    override func emitFor(_ s: Statement.ForLoop) {
        let f = forParts(s)
        let header = s.direction == .increasing
            ? (f.stepIsOne ? "for \(f.variable) in \(f.start)...\(f.end)" : "for \(f.variable) in stride(from: \(f.start), through: \(f.end), by: \(f.step))")
            : "for \(f.variable) in stride(from: \(f.start), through: \(f.end), by: -\(f.step))"
        braced(header, s.body)
    }

    override func truncate(_ e: Expr) -> String { "Int(\(render(e).text))" }

    override func emitComment(_ text: String) {
        commentLines(text).forEach { line("// \($0)") }
    }

    override var piText: String { "Double.pi" }

    /// Swift never mixes Int and Double implicitly, so integers meeting reals are converted.
    func promoted(_ e: Expr, when other: Expr) -> Rendered {
        if isInteger(e), !isInteger(other), type(of: other) == .real {
            return Rendered(text: "Double(\(render(e).text))", precedence: Emitter.atom)
        }
        return render(e)
    }

    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        switch op {
        case .concat:
            return concat(flattenConcat(.binary(.concat, l, r)))
        case .divide:
            let p = precedence(of: .divide)
            let lhs = isInteger(l) ? "Double(\(render(l).text))" : wrap(render(l), below: p)
            let rhs = isInteger(r) ? "Double(\(render(r).text))" : wrap(render(r), below: p + 1)
            return Rendered(text: "\(lhs) / \(rhs)", precedence: p)
        case .power:
            let lhs = isInteger(l) ? "Double(\(render(l).text))" : render(l).text
            let rhs = isInteger(r) ? "Double(\(render(r).text))" : render(r).text
            return call("pow", [lhs, rhs])
        case .modulo where !(isInteger(l) && isInteger(r)):
            return Rendered(text: "\(wrap(promoted(l, when: r), below: Emitter.atom)).truncatingRemainder(dividingBy: \(promoted(r, when: l).text))",
                            precedence: Emitter.atom)
        case .plus, .minus, .times, .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            let p = precedence(of: op)
            let lhs = wrap(promoted(l, when: r), below: p)
            let rhs = wrap(promoted(r, when: l), below: p + 1)
            return Rendered(text: "\(lhs) \(operatorText(op)) \(rhs)", precedence: p)
        default:
            return super.binary(op, l, r)
        }
    }

    /// Concatenation becomes a string interpolation: "Total: \(x)".
    override func concat(_ parts: [Expr]) -> Rendered {
        var text = "\""
        for part in parts {
            if case .string(let s) = part {
                text += String(stringLiteral(s).dropFirst().dropLast())
            } else {
                text += "\\(\(render(part).text))"
            }
        }
        return Rendered(text: text + "\"", precedence: Emitter.atom)
    }

    override func userCall(_ n: String, _ args: [Expr]) -> Rendered {
        let function = program.function(named: n)
        let rendered = args.enumerated().map { index, argument -> String in
            if let parameter = function?.parameters[safe: index], parameter.isArray { return "&\(render(argument).text)" }
            return render(argument).text
        }
        return call(functionName(n), rendered)
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        switch n {
        case "abs": call("abs", [arg(args, 0)])
        case "arccos": call("acos", [arg(args, 0)])
        case "arcsin": call("asin", [arg(args, 0)])
        case "arctan": call("atan", [arg(args, 0)])
        case "ln", "log": call("log", [arg(args, 0)])
        case "int": call("Int", [arg(args, 0)])
        case "sgn": Rendered(text: "(\(arg(args, 0)) > 0 ? 1 : (\(arg(args, 0)) < 0 ? -1 : 0))", precedence: Emitter.atom)
        case "random": call("Int.random", ["in: 0..<\(argAtom(args, 0))"])
        case "len", "size": Rendered(text: "\(argAtom(args, 0)).count", precedence: Emitter.atom)
        case "char": call("String", ["Array(\(arg(args, 0)))[\(arg(args, 1))]"])
        case "tochar": call("String", ["Character(UnicodeScalar(\(arg(args, 0)))!)"])
        case "tocode": call("Int", ["\(argAtom(args, 0)).unicodeScalars.first!.value"])
        case "tofixed": call("String", ["format: \"%.\\(\(arg(args, 1)))f\"", arg(args, 0)])
        case "tointeger": Rendered(text: "Int(\(arg(args, 0)))!", precedence: Emitter.atom)
        case "toreal": Rendered(text: "Double(\(arg(args, 0)))!", precedence: Emitter.atom)
        case "tostring": call("String", [arg(args, 0)])
        default: super.intrinsic(n, args)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
