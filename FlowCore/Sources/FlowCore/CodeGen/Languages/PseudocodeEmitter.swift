import Foundation

/// Structured pseudocode in Italian or English, close to what Italian schools teach.
final class PseudocodeEmitter: Emitter {
    let italian: Bool

    init(program: Program, italian: Bool) {
        self.italian = italian
        super.init(program: program)
    }

    func word(_ it: String, _ en: String) -> String { italian ? it : en }

    func typeName(_ type: DataType) -> String {
        switch type {
        case .integer: word("Intero", "Integer")
        case .real: word("Reale", "Real")
        case .string: word("Stringa", "String")
        case .boolean: word("Booleano", "Boolean")
        }
    }

    override func emitProgram() {
        let title = program.name.isEmpty ? word("Programma", "Program") : program.name
        line("\(word("PROGRAMMA", "PROGRAM")) \(title)")
        blank()
        for function in program.functions {
            enter(function)
            if function.id == mainFunction?.id {
                line(word("INIZIO", "BEGIN"))
            } else {
                let params = function.parameters.map {
                    "\($0.name) : \(typeName($0.type))\($0.isArray ? "[]" : "")"
                }.joined(separator: ", ")
                let returns = function.returnType.map { " : \(typeName($0))" } ?? ""
                line("\(word("FUNZIONE", "FUNCTION")) \(function.name)(\(params))\(returns)")
            }
            indented { emitBlock(function.body) }
            if function.id == mainFunction?.id {
                line(word("FINE", "END"))
            } else {
                if function.returnType != nil {
                    indented { line("\(word("RESTITUISCI", "RETURN")) \(name(function.returnVariable))") }
                }
                line(word("FINE FUNZIONE", "END FUNCTION"))
            }
            blank()
        }
    }

    override var piText: String { "π" }

    override func realLiteral(_ d: Double) -> String { Value.format(d) }

    override func boolLiteral(_ b: Bool) -> String { b ? word("VERO", "TRUE") : word("FALSO", "FALSE") }

    override func operatorText(_ op: Operator) -> String {
        switch op {
        case .and: word("E", "AND")
        case .or: word("O", "OR")
        case .not: word("NON ", "NOT ")
        case .equal: "="
        case .notEqual: "≠"
        case .lessEqual: "≤"
        case .greaterEqual: "≥"
        case .modulo: "mod"
        case .power: "^"
        case .concat: "&"
        default: super.operatorText(op)
        }
    }

    override func precedence(of op: Operator) -> Int {
        // Flowgorithm's own levels.
        switch op {
        case .or: 1
        case .and: 2
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual: 3
        case .concat: 4
        case .plus, .minus: 5
        case .times, .divide, .modulo: 6
        case .power: 7
        case .not: 8
        }
    }

    override var unaryMinusPrecedence: Int { 8 }

    override func concat(_ parts: [Expr]) -> Rendered {
        let p = precedence(of: .concat)
        return Rendered(text: parts.map { wrap(render($0), below: p + 1) }.joined(separator: " & "), precedence: p)
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        let canonical = Identifier.intrinsicNames.contains(n) ? n.prefix(1).uppercased() + n.dropFirst() : n
        let pretty = ["tochar": "ToChar", "tocode": "ToCode", "tofixed": "ToFixed", "tointeger": "ToInteger",
                      "toreal": "ToReal", "tostring": "ToString", "eof": "EOF", "arccos": "Arccos", "arcsin": "Arcsin",
                      "arctan": "Arctan", "log10": "Log10"][n] ?? canonical
        return call(pretty, args.map { render($0).text })
    }

    override func emitDeclare(_ s: Statement.Declare) {
        if s.isArray {
            line("\(word("DICHIARA", "DECLARE")) \(typeName(s.type)) \(s.nameList.map { "\($0)[\(expr(s.size))]" }.joined(separator: ", "))")
        } else {
            line("\(word("DICHIARA", "DECLARE")) \(typeName(s.type)) \(s.nameList.joined(separator: ", "))")
        }
    }

    override func emitAssign(_ s: Statement.Assign) { line("\(target(s.variable)) ← \(expr(s.expression))") }

    override func emitInput(_ s: Statement.Input) { line("\(word("LEGGI", "INPUT")) \(target(s.variable))") }

    override func emitOutput(_ s: Statement.Output) {
        line("\(word("SCRIVI", "OUTPUT")) \(expr(s.expression))\(s.newline ? "" : word(" (senza a capo)", " (no newline)"))")
    }

    override func emitIf(_ s: Statement.If) {
        line("\(word("SE", "IF")) \(expr(s.expression)) \(word("ALLORA", "THEN"))")
        indented { emitBlock(s.thenBody) }
        if !s.elseBody.isEmpty {
            line(word("ALTRIMENTI", "ELSE"))
            indented { emitBlock(s.elseBody) }
        }
        line(word("FINE SE", "END IF"))
    }

    override func emitWhile(_ s: Statement.While) {
        line("\(word("MENTRE", "WHILE")) \(expr(s.expression)) \(word("ESEGUI", "DO"))")
        indented { emitBlock(s.body) }
        line(word("FINE MENTRE", "END WHILE"))
    }

    override func emitDo(_ s: Statement.DoLoop) {
        line(word("FAI", "DO"))
        indented { emitBlock(s.body) }
        line("\(word("MENTRE", "LOOP WHILE")) \(expr(s.expression))")
    }

    override func emitFor(_ s: Statement.ForLoop) {
        let f = forParts(s)
        let step = f.stepIsOne && s.direction == .increasing ? "" : " \(word("PASSO", "STEP")) \(s.direction == .decreasing ? "-" : "")\(f.step)"
        line("\(word("PER", "FOR")) \(f.variable) \(word("DA", "FROM")) \(f.start) \(word("A", "TO")) \(f.end)\(step)")
        indented { emitBlock(s.body) }
        line(word("FINE PER", "END FOR"))
    }

    override func emitCall(_ s: Statement.Call) { line("\(word("CHIAMA", "CALL")) \(expr(s.expression))") }

    override func emitComment(_ text: String) { commentLines(text).forEach { line("// \($0)") } }

    override func emitOpen(_ s: Statement.OpenFile) {
        let mode = switch s.mode {
        case .read: word("in lettura", "for reading")
        case .write: word("in scrittura", "for writing")
        case .append: word("in aggiunta", "for appending")
        }
        line("\(word("APRI", "OPEN")) \(expr(s.expression)) \(mode)")
    }

    override func emitClose() { line(word("CHIUDI FILE", "CLOSE FILE")) }

    override func emitRead(_ s: Statement.ReadFile) { line("\(word("LEGGI DA FILE", "READ")) \(target(s.variable))") }

    override func emitWrite(_ s: Statement.WriteFile) { line("\(word("SCRIVI SU FILE", "WRITE")) \(expr(s.expression))") }

    override func emit(_ statement: Statement) {
        switch statement.kind {
        case .breakpoint: line(word("// punto di interruzione", "// breakpoint"))
        case .turn(let s):
            line("\(word("RUOTA", "TURN")) \(s.direction == .left ? word("A SINISTRA", "LEFT") : word("A DESTRA", "RIGHT")) \(expr(s.expression))")
        case .forward(let s):
            line("\(s.penDown ? word("AVANZA", "FORWARD") : word("SPOSTA", "MOVE")) \(expr(s.expression))")
        case .home: line(word("TORNA ALL'ORIGINE", "HOME"))
        case .clear: line(word("PULISCI", "CLEAR"))
        case .pen(let s): line("\(word("PENNA", "PEN")) \(s.color.rawValue)")
        default: super.emit(statement)
        }
    }
}
