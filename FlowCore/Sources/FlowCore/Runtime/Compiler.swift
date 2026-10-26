import Foundation

/// A name as the user typed it (for messages) with its case-insensitive lookup key,
/// computed once instead of on every access.
struct Name {
    let key: String
    let display: String

    init(_ display: String) {
        self.display = display
        key = display.lowercased()
    }
}

/// The built-in functions, recognized once at compile time.
enum Intrinsic: String {
    case abs, arccos, arcsin, arctan, char, cos, eof, int, len, ln, log, log10, random, sgn, sin, size, sqrt, tan
    case tochar, tocode, tofixed, tointeger, toreal, tostring
}

/// An expression lowered for evaluation: parentheses dropped, literals turned into values,
/// names normalized and built-in functions resolved.
indirect enum Node {
    case constant(Value)
    case variable(Name)
    case element(Name, index: Node)
    /// `array` is the argument's name when it is a bare variable, for Size().
    case intrinsic(Intrinsic, display: String, arguments: [Node], array: Name?)
    case call(Name, arguments: [Argument])
    case negate(Node)
    case not(Node)
    case and(Node, Node)
    case or(Node, Node)
    case binary(Operator, Node, Node)

    /// True when no user function is called, so the expression can be evaluated without suspending.
    var isPure: Bool {
        switch self {
        case .constant, .variable: true
        case .call: false
        case .element(_, let index): index.isPure
        case .intrinsic(_, _, let arguments, _): arguments.allSatisfy(\.isPure)
        case .negate(let x), .not(let x): x.isPure
        case .and(let l, let r), .or(let l, let r), .binary(_, let l, let r): l.isPure && r.isPure
        }
    }

    init(_ expr: Expr) {
        switch expr {
        case .integer(let v): self = .constant(.integer(v))
        case .real(let v): self = .constant(.real(v))
        case .string(let v): self = .constant(.string(v))
        case .boolean(let v): self = .constant(.boolean(v))
        case .pi: self = .constant(.real(.pi))
        case .group(let inner): self = Node(inner)
        case .variable(let name): self = .variable(Name(name))
        case .element(let name, let index): self = .element(Name(name), index: Node(index))
        case .call(let name, let arguments):
            if let intrinsic = Intrinsic(rawValue: name.lowercased()) {
                self = .intrinsic(intrinsic, display: name, arguments: arguments.map(Node.init),
                                  array: arguments.first.flatMap(Argument.bareVariable))
            } else {
                self = .call(Name(name), arguments: arguments.map(Argument.init))
            }
        case .unary(.not, let operand): self = .not(Node(operand))
        case .unary(_, let operand): self = .negate(Node(operand))
        case .binary(.and, let l, let r): self = .and(Node(l), Node(r))
        case .binary(.or, let l, let r): self = .or(Node(l), Node(r))
        case .binary(let op, let l, let r): self = .binary(op, Node(l), Node(r))
        }
    }
}

struct Argument {
    let value: CompiledExpr
    /// Set when the argument is a bare variable name, which array parameters need.
    let variable: Name?

    init(_ expr: Expr) {
        value = CompiledExpr(expr)
        variable = Argument.bareVariable(expr)
    }

    static func bareVariable(_ expr: Expr) -> Name? {
        if case .variable(let name) = expr.unwrapped { return Name(name) }
        return nil
    }
}

struct CompiledExpr {
    let node: Node
    let isPure: Bool

    init(_ expr: Expr) {
        node = Node(expr)
        isPure = node.isPure
    }
}

/// Where a value is stored: `x` or `a[i]`.
struct Target {
    let name: Name
    let index: CompiledExpr?

    init(_ lvalue: LValue) {
        name = Name(lvalue.name)
        index = lvalue.index.map(CompiledExpr.init)
    }
}

/// A statement with its expressions already parsed, ready to run.
struct CompiledStatement {
    indirect enum Operation {
        case declare(names: [Name], type: DataType, size: CompiledExpr?)
        case assign(Target, CompiledExpr)
        case input(Target)
        case output(CompiledExpr, newline: Bool)
        case ifElse(CompiledExpr, then: [CompiledStatement], else: [CompiledStatement])
        case whileLoop(CompiledExpr, body: [CompiledStatement])
        case doLoop(CompiledExpr, body: [CompiledStatement])
        case forLoop(variable: Name, start: CompiledExpr, end: CompiledExpr, step: CompiledExpr, decreasing: Bool, body: [CompiledStatement])
        /// A function called for its effect: a `.call` or `.intrinsic` node.
        case call(Node)
        case breakpoint(condition: CompiledExpr?)
        case open(CompiledExpr, FileMode)
        case close
        case read(Target)
        case write(CompiledExpr)
        case turn(CompiledExpr, TurnDirection)
        case forward(CompiledExpr, penDown: Bool)
        case home
        case clear
        case pen(PenColor)
        case nothing
    }

    var id: Statement.ID
    var operation: Operation
}

struct CompiledFunction {
    var function: Function
    var parameters: [Name]
    var returnVariable: Name
    var body: [CompiledStatement]
}

/// Parses every expression of a program up front, so syntax errors show before anything runs.
enum Compiler {
    static func compile(_ program: Program) throws(RuntimeError) -> [String: CompiledFunction] {
        var result: [String: CompiledFunction] = [:]
        for function in program.functions {
            if let problem = Identifier.validate(function.name), !function.isMain {
                throw RuntimeError(.invalidName(function.name, problem), functionName: function.name)
            }
            for parameter in function.parameters {
                if let problem = Identifier.validate(parameter.name) {
                    throw RuntimeError(.invalidName(parameter.name, problem), functionName: function.name)
                }
            }
            let body = try compile(function.body, function: function.name)
            result[function.name.lowercased()] = CompiledFunction(
                function: function,
                parameters: function.parameters.map { Name($0.name) },
                returnVariable: Name(function.returnVariable.trimmingCharacters(in: .whitespaces)),
                body: body)
        }
        return result
    }

    /// Checks one shape on its own, for live validation in the editor.
    static func check(_ statement: Statement) -> RuntimeError? {
        do {
            _ = try compile(statement, function: "", recursive: false)
            return nil
        } catch {
            return error
        }
    }

    static func compile(_ block: [Statement], function: String) throws(RuntimeError) -> [CompiledStatement] {
        var result: [CompiledStatement] = []
        result.reserveCapacity(block.count)
        for statement in block {
            result.append(try compile(statement, function: function, recursive: true))
        }
        return result
    }

    static func compile(_ statement: Statement, function: String, recursive: Bool) throws(RuntimeError) -> CompiledStatement {
        let id = statement.id

        func expr(_ source: String) throws(RuntimeError) -> CompiledExpr {
            do {
                return CompiledExpr(try ExpressionParser.parse(source))
            } catch {
                throw RuntimeError(.syntax(error, source: source), statementID: id, functionName: function)
            }
        }

        func target(_ source: String) throws(RuntimeError) -> Target {
            do {
                return Target(try ExpressionParser.parseLValue(source))
            } catch {
                throw RuntimeError(.syntax(error, source: source), statementID: id, functionName: function)
            }
        }

        func body(_ block: [Statement]) throws(RuntimeError) -> [CompiledStatement] {
            recursive ? try compile(block, function: function) : []
        }

        let operation: CompiledStatement.Operation
        switch statement.kind {
        case .declare(let s):
            let names = s.nameList
            if names.isEmpty { throw RuntimeError(.incompleteShape, statementID: id, functionName: function) }
            for name in names {
                if let problem = Identifier.validate(name) {
                    throw RuntimeError(.invalidName(name, problem), statementID: id, functionName: function)
                }
            }
            operation = .declare(names: names.map(Name.init), type: s.type, size: s.isArray ? try expr(s.size) : nil)
        case .assign(let s):
            operation = .assign(try target(s.variable), try expr(s.expression))
        case .input(let s):
            operation = .input(try target(s.variable))
        case .output(let s):
            operation = .output(try expr(s.expression), newline: s.newline)
        case .if(let s):
            operation = .ifElse(try expr(s.expression), then: try body(s.thenBody), else: try body(s.elseBody))
        case .while(let s):
            operation = .whileLoop(try expr(s.expression), body: try body(s.body))
        case .do(let s):
            operation = .doLoop(try expr(s.expression), body: try body(s.body))
        case .for(let s):
            let variable = try target(s.variable)
            if variable.index != nil {
                throw RuntimeError(.syntax(ExpressionError(.notAVariable(s.variable), offset: 0), source: s.variable),
                                   statementID: id, functionName: function)
            }
            let step = s.step.trimmingCharacters(in: .whitespaces).isEmpty ? "1" : s.step
            operation = .forLoop(variable: variable.name, start: try expr(s.start), end: try expr(s.end),
                                 step: try expr(step), decreasing: s.direction == .decreasing, body: try body(s.body))
        case .call(let s):
            do {
                let call = try ExpressionParser.parseCall(s.expression)
                operation = .call(Node(.call(call.name, arguments: call.arguments)))
            } catch {
                throw RuntimeError(.syntax(error, source: s.expression), statementID: id, functionName: function)
            }
        case .comment, .unknown:
            operation = .nothing
        case .breakpoint(let s):
            let condition = s.expression.trimmingCharacters(in: .whitespaces)
            operation = .breakpoint(condition: s.always || condition.isEmpty ? nil : try expr(condition))
        case .open(let s):
            operation = .open(try expr(s.expression), s.mode)
        case .close:
            operation = .close
        case .read(let s):
            operation = .read(try target(s.variable))
        case .write(let s):
            operation = .write(try expr(s.expression))
        case .turn(let s):
            operation = .turn(try expr(s.expression), s.direction)
        case .forward(let s):
            operation = .forward(try expr(s.expression), penDown: s.penDown)
        case .home:
            operation = .home
        case .clear:
            operation = .clear
        case .pen(let s):
            operation = .pen(s.color)
        }
        return CompiledStatement(id: id, operation: operation)
    }
}

extension Statement {
    /// Parses this shape's expressions; returns the first problem, if any.
    public var validationError: RuntimeError? { Compiler.check(self) }
}
