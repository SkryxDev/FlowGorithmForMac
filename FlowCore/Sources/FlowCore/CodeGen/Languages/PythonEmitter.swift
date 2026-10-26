import Foundation

final class PythonEmitter: Emitter {
    override func emitProgram() {
        var imports: [String] = []
        if uses.contains("turtle") { imports.append("import turtle") }
        if ["sqrt", "sin", "cos", "tan", "arc", "log", "ln(", "pi", "mod", "%"].contains(where: uses.contains) { imports.append("import math") }
        if uses.contains("random") { imports.append("import random") }
        imports.forEach(line)
        if !imports.isEmpty { blank() }

        if uses.contains("eof") {
            line("def eof(f):")
            indented {
                line("position = f.tell()")
                line("at_end = f.readline() == \"\"")
                line("f.seek(position)")
                line("return at_end")
            }
            blank()
        }

        for function in otherFunctions {
            enter(function)
            let params = function.parameters.map { identifier($0.name) }.joined(separator: ", ")
            line("def \(functionName(function.name))(\(params)):")
            indented {
                if function.body.isEmpty && function.returnType == nil { line("pass") }
                emitBlock(function.body)
                if function.returnType != nil { line("return \(name(function.returnVariable))") }
            }
            blank()
        }

        if let main = mainFunction {
            enter(main)
            line("# Main")
            if uses.contains("turtle") { line("turtle.setheading(90)") }
            emitBlock(main.body)
            if uses.contains("turtle") { line("turtle.done()") }
        }
    }

    static let reserved: Set<String> = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal",
        "not", "or", "pass", "raise", "return", "try", "while", "with", "yield",
        "print", "input", "int", "float", "str", "range", "format", "chr", "ord", "math", "random", "turtle", "file",
    ]

    override var reservedNames: Set<String> { Self.reserved }

    override var piText: String { "math.pi" }

    override func boolLiteral(_ b: Bool) -> String { b ? "True" : "False" }

    override func realLiteral(_ d: Double) -> String { super.realLiteral(d) }

    override func precedence(of op: Operator) -> Int {
        switch op {
        case .or: 1
        case .and: 2
        case .not: 3
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual: 4
        case .concat, .plus, .minus: 5
        case .times, .divide, .modulo: 6
        case .power: 8
        }
    }

    override func operatorText(_ op: Operator) -> String {
        switch op {
        case .and: "and"
        case .or: "or"
        case .not: "not "
        case .power: "**"
        default: super.operatorText(op)
        }
    }

    /// Python's `%` takes the divisor's sign; the flowchart's remainder takes the dividend's, like `math.fmod`.
    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        guard op == .modulo else { return super.binary(op, l, r) }
        let remainder = call("math.fmod", [render(l).text, render(r).text])
        return isInteger(l) && isInteger(r) ? call("int", [remainder.text]) : remainder
    }

    override func concat(_ parts: [Expr]) -> Rendered {
        let p = precedence(of: .plus)
        let texts = parts.map { part -> String in
            type(of: part) == .string ? wrap(render(part), below: p + 1) : "str(\(render(part).text))"
        }
        return Rendered(text: texts.joined(separator: " + "), precedence: p)
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        switch n {
        case "abs": call("abs", [arg(args, 0)])
        case "arccos": call("math.acos", [arg(args, 0)])
        case "arcsin": call("math.asin", [arg(args, 0)])
        case "arctan": call("math.atan", [arg(args, 0)])
        case "cos": call("math.cos", [arg(args, 0)])
        case "sin": call("math.sin", [arg(args, 0)])
        case "tan": call("math.tan", [arg(args, 0)])
        case "sqrt": call("math.sqrt", [arg(args, 0)])
        case "ln", "log": call("math.log", [arg(args, 0)])
        case "log10": call("math.log10", [arg(args, 0)])
        case "int", "tointeger": call("int", [arg(args, 0)])
        case "toreal": call("float", [arg(args, 0)])
        case "tostring": call("str", [arg(args, 0)])
        case "len", "size": call("len", [arg(args, 0)])
        case "char": Rendered(text: "\(argAtom(args, 0))[\(arg(args, 1))]", precedence: Emitter.atom)
        case "tochar": call("chr", [arg(args, 0)])
        case "tocode": call("ord", [arg(args, 0)])
        case "random": call("random.randrange", [arg(args, 0)])
        case "sgn": Rendered(text: "((\(arg(args, 0)) > 0) - (\(arg(args, 0)) < 0))", precedence: Emitter.atom)
        case "tofixed": call("format", [arg(args, 0), "\".\" + str(\(arg(args, 1))) + \"f\""])
        case "eof": call("eof", ["file"])
        default: super.intrinsic(n, args)
        }
    }

    func defaultValue(_ type: DataType) -> String {
        switch type {
        case .integer: "0"
        case .real: "0.0"
        case .string: "\"\""
        case .boolean: "False"
        }
    }

    func conversion(_ type: DataType, _ text: String) -> String {
        switch type {
        case .integer: "int(\(text))"
        case .real: "float(\(text))"
        case .string: text
        case .boolean: "\(text).lower() == \"true\""
        }
    }

    override func emitDeclare(_ s: Statement.Declare) {
        for variable in s.nameList {
            if s.isArray {
                line("\(name(variable)) = [\(defaultValue(s.type))] * (\(expr(s.size)))")
            } else {
                line("\(name(variable)) = \(defaultValue(s.type))")
            }
        }
    }

    override func emitAssign(_ s: Statement.Assign) {
        line("\(target(s.variable)) = \(expr(s.expression))")
    }

    override func emitInput(_ s: Statement.Input) {
        line("\(target(s.variable)) = \(conversion(targetType(s.variable), "input()"))")
    }

    override func emitOutput(_ s: Statement.Output) {
        line(s.newline ? "print(\(expr(s.expression)))" : "print(\(expr(s.expression)), end=\"\")")
    }

    func body(_ block: [Statement]) {
        indented {
            if block.isEmpty { untagged { line("pass") } }
            emitBlock(block)
        }
    }

    override func emitIf(_ s: Statement.If) {
        line("if \(expr(s.expression)):")
        body(s.thenBody)
        if !s.elseBody.isEmpty {
            line("else:")
            body(s.elseBody)
        }
    }

    override func emitWhile(_ s: Statement.While) {
        line("while \(expr(s.expression)):")
        body(s.body)
    }

    override func emitDo(_ s: Statement.DoLoop) {
        line("while True:")
        indented {
            emitBlock(s.body)
            line("if not (\(expr(s.expression))):")
            indented { line("break") }
        }
    }

    override func emitFor(_ s: Statement.ForLoop) {
        let f = forParts(s)
        let range: String
        if s.direction == .increasing {
            range = f.stepIsOne ? "range(\(f.start), \(f.end) + 1)" : "range(\(f.start), \(f.end) + 1, \(f.step))"
        } else {
            range = "range(\(f.start), \(f.end) - 1, -\(f.step))"
        }
        line("for \(f.variable) in \(range):")
        body(s.body)
    }

    override func emitCall(_ s: Statement.Call) {
        line(expr(s.expression).hasSuffix(")") ? expr(s.expression) : "\(expr(s.expression))()")
    }

    override func emitComment(_ text: String) {
        commentLines(text).forEach { line("# \($0)") }
    }

    override func emitOpen(_ s: Statement.OpenFile) {
        let mode = s.mode == .read ? "r" : s.mode == .write ? "w" : "a"
        line("file = open(\(expr(s.expression)), \"\(mode)\")")
    }

    override func emitClose() { line("file.close()") }

    override func emitRead(_ s: Statement.ReadFile) {
        line("\(target(s.variable)) = \(conversion(targetType(s.variable), "file.readline().rstrip(\"\\n\")"))")
    }

    override func emitWrite(_ s: Statement.WriteFile) {
        line("file.write(str(\(expr(s.expression))) + \"\\n\")")
    }

    override func emit(_ statement: Statement) {
        switch statement.kind {
        case .turn(let s): line("turtle.\(s.direction.rawValue)(\(expr(s.expression)))")
        case .forward(let s):
            if s.penDown {
                line("turtle.forward(\(expr(s.expression)))")
            } else {
                line("turtle.penup()")
                line("turtle.forward(\(expr(s.expression)))")
                line("turtle.pendown()")
            }
        case .home: line("turtle.home()")
        case .clear:
            line("turtle.clear()")
            line("turtle.home()")
        case .pen(let s): line("turtle.pencolor(\"\(s.color.rawValue)\")")
        default: super.emit(statement)
        }
    }
}
