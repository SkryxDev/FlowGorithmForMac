// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

/// A mistake that only shows when the program runs, found by reading it: a variable declared
/// twice or never, a function that doesn't exist, values of the wrong type. The AI assistant
/// uses these to check its own changes before the user runs them.
public struct LintProblem: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Declared again in the same function, or with the name of a parameter.
        case duplicateDeclaration(String)
        /// Declared inside a loop, so the second pass declares it again.
        case declaredInLoop(String)
        case undeclared(String)
        case unknownFunction(String)
        /// The function returns a variable its body never declares.
        case returnVariableNotDeclared(String)
        /// A value of a type the operation can't take, described in plain English.
        case typeMismatch(String)
    }

    public var kind: Kind
    public var function: String
    /// The shape where it happens; `nil` for problems of the whole function.
    public var statementID: Statement.ID?
}

/// Reads a program in the order its shapes run and reports what would stop it with an error,
/// following the interpreter's rules. Branches are followed separately, so a variable declared in
/// both the then and the else of an if isn't a duplicate; a variable declared in either is known
/// after it. Types are checked only where they're known for sure, so it never guesses.
public enum Linter {
    public static func problems(in program: Program) -> [LintProblem] {
        let functions = Dictionary(program.functions.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return program.functions.flatMap { function in
            var walker = Walker(function: function.name, functions: functions)
            var scope = Scope(uniqueKeysWithValues: function.parameters.map { ($0.name.lowercased(), Variable(type: $0.type, isArray: $0.isArray)) })
            walker.walk(function.body, scope: &scope, inLoop: false)
            let returned = function.returnVariable.trimmingCharacters(in: .whitespaces)
            if function.returnType != nil, !returned.isEmpty, scope[returned.lowercased()] == nil {
                walker.problems.append(LintProblem(kind: .returnVariableNotDeclared(returned), function: function.name, statementID: nil))
            }
            return walker.problems
        }
    }

    struct Variable {
        var type: DataType
        var isArray: Bool
    }

    typealias Scope = [String: Variable]

    private struct Walker {
        let function: String
        let functions: [String: Function]
        var problems: [LintProblem] = []
        /// The shape being read, which every problem is reported on.
        var current = Statement.ID()

        init(function: String, functions: [String: Function]) {
            self.function = function
            self.functions = functions
        }

        mutating func report(_ kind: LintProblem.Kind) {
            let problem = LintProblem(kind: kind, function: function, statementID: current)
            if !problems.contains(problem) { problems.append(problem) }
        }

        mutating func walk(_ shapes: [Statement], scope: inout Scope, inLoop: Bool) {
            for shape in shapes {
                current = shape.id
                switch shape.kind {
                case .declare(let s):
                    if s.isArray { number(s.size, scope, "an array size") }
                    for name in s.nameList {
                        let key = name.lowercased()
                        if scope[key] != nil {
                            report(.duplicateDeclaration(name))
                        } else if inLoop {
                            report(.declaredInLoop(name))
                        }
                        scope[key] = Variable(type: s.type, isArray: s.isArray)
                    }
                case .assign(let s):
                    let target = target(s.variable, scope)
                    let value = type(of: s.expression, scope)
                    if let target, let value, !Linter.canStore(value, in: target) {
                        report(.typeMismatch("\(s.variable) is \(Linter.name(target)) but gets \(Linter.article(value))"))
                    }
                case .input(let s):
                    _ = target(s.variable, scope)
                case .read(let s):
                    _ = target(s.variable, scope)
                case .output(let s): _ = type(of: s.expression, scope)
                case .write(let s): _ = type(of: s.expression, scope)
                case .open(let s): _ = type(of: s.expression, scope)
                case .turn(let s): number(s.expression, scope, "a turn")
                case .forward(let s): number(s.expression, scope, "a forward move")
                case .call(let s): _ = type(of: s.expression, scope)
                case .breakpoint(let s):
                    if !s.always { condition(s.expression, scope) }
                case .if(let s):
                    condition(s.expression, scope)
                    var thenScope = scope
                    var elseScope = scope
                    walk(s.thenBody, scope: &thenScope, inLoop: inLoop)
                    walk(s.elseBody, scope: &elseScope, inLoop: inLoop)
                    scope.merge(thenScope) { old, _ in old }
                    scope.merge(elseScope) { old, _ in old }
                case .while(let s):
                    condition(s.expression, scope)
                    walk(s.body, scope: &scope, inLoop: true)
                case .do(let s):
                    let id = shape.id
                    walk(s.body, scope: &scope, inLoop: true)
                    current = id
                    condition(s.expression, scope)
                case .for(let s):
                    if let counter = target(s.variable, scope), !counter.isNumeric {
                        report(.typeMismatch("the For counter \(s.variable) must be a number, but it's \(Linter.name(counter))"))
                    }
                    number(s.start, scope, "the start of a For")
                    number(s.end, scope, "the end of a For")
                    number(s.step, scope, "the step of a For")
                    walk(s.body, scope: &scope, inLoop: true)
                case .comment, .close, .home, .clear, .pen, .unknown:
                    break
                }
            }
        }

        // MARK: Expressions

        /// The type of an expression, or nil when it isn't known. Expressions that don't parse are
        /// left to the editor's syntax check.
        mutating func type(of source: String, _ scope: Scope) -> DataType? {
            guard !source.trimmingCharacters(in: .whitespaces).isEmpty,
                  let expr = try? ExpressionParser.parse(source) else { return nil }
            return type(of: expr, scope)
        }

        mutating func condition(_ source: String, _ scope: Scope) {
            if let found = type(of: source, scope), found != .boolean {
                report(.typeMismatch("a condition must be true or false, but \"\(source)\" is \(Linter.name(found))"))
            }
        }

        mutating func number(_ source: String, _ scope: Scope, _ what: String) {
            if let found = type(of: source, scope), !found.isNumeric {
                report(.typeMismatch("\(what) must be a number, but \"\(source)\" is \(Linter.name(found))"))
            }
        }

        /// The type of the variable an assignment, input or read stores into.
        mutating func target(_ source: String, _ scope: Scope) -> DataType? {
            guard let lvalue = try? ExpressionParser.parseLValue(source) else { return nil }
            if let index = lvalue.index { indexValue(index, scope) }
            guard let variable = scope[lvalue.name.lowercased()] else {
                report(.undeclared(lvalue.name))
                return nil
            }
            return variable.type
        }

        mutating func indexValue(_ index: Expr, _ scope: Scope) {
            if let found = type(of: index, scope), !found.isNumeric {
                report(.typeMismatch("an array index must be a number, but it's \(Linter.name(found))"))
            }
        }

        mutating func type(of expr: Expr, _ scope: Scope) -> DataType? {
            switch expr {
            case .integer: return .integer
            case .real, .pi: return .real
            case .string: return .string
            case .boolean: return .boolean
            case .group(let inner): return type(of: inner, scope)
            case .variable(let name):
                guard let variable = scope[name.lowercased()] else {
                    report(.undeclared(name))
                    return nil
                }
                return variable.isArray ? nil : variable.type
            case .element(let name, let index):
                indexValue(index, scope)
                guard let variable = scope[name.lowercased()] else {
                    report(.undeclared(name))
                    return nil
                }
                return variable.type
            case .unary(let op, let operand):
                let found = type(of: operand, scope)
                if op == .not {
                    if let found, found != .boolean {
                        report(.typeMismatch("not needs a true or false value, but \(Linter.describe(operand)) is \(Linter.name(found))"))
                    }
                    return .boolean
                }
                if let found, !found.isNumeric {
                    report(.typeMismatch("a minus sign needs a number, but \(Linter.describe(operand)) is \(Linter.name(found))"))
                    return nil
                }
                return found
            case .binary(let op, let left, let right):
                return binary(op, left, right, scope)
            case .call(let name, let arguments):
                return call(name, arguments, scope)
            }
        }

        mutating func binary(_ op: Operator, _ left: Expr, _ right: Expr, _ scope: Scope) -> DataType? {
            let l = type(of: left, scope)
            let r = type(of: right, scope)
            switch op {
            case .and, .or:
                for (side, found) in [(left, l), (right, r)] {
                    if let found, found != .boolean {
                        report(.typeMismatch("\(op.rawValue) joins true or false values, but \(Linter.describe(side)) is \(Linter.name(found))"))
                    }
                }
                return .boolean
            case .concat:
                return .string
            case .plus, .minus, .times, .divide, .modulo, .power:
                for (side, found) in [(left, l), (right, r)] {
                    if let found, !found.isNumeric {
                        let hint = found == .string && op == .plus ? "; use & to join text" : ""
                        report(.typeMismatch("\(Linter.symbol(op)) works on numbers, but \(Linter.describe(side)) is \(Linter.name(found))\(hint)"))
                        return nil
                    }
                }
                guard let l, let r else { return nil }
                switch op {
                case .divide, .power: return .real
                default: return l == .integer && r == .integer ? .integer : .real
                }
            case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
                if let l, let r {
                    if l.isNumeric != r.isNumeric || (!l.isNumeric && l != r) {
                        report(.typeMismatch("\(Linter.describe(left)) (\(Linter.name(l))) can't be compared with \(Linter.describe(right)) (\(Linter.name(r)))"))
                    } else if l == .boolean && op != .equal && op != .notEqual {
                        report(.typeMismatch("true or false values can only be compared with = or <>"))
                    }
                }
                return .boolean
            case .not:
                return .boolean
            }
        }

        mutating func call(_ name: String, _ arguments: [Expr], _ scope: Scope) -> DataType? {
            let key = name.lowercased()
            if Identifier.intrinsicNames.contains(key) {
                // Size takes an array, which has no type of its own as a value.
                if key == "size", case .variable(let array)? = arguments.first, scope[array.lowercased()] == nil {
                    report(.undeclared(array))
                }
                let types = key == "size" ? [] : arguments.map { type(of: $0, scope) }
                func expect(_ index: Int, _ wanted: String, _ ok: (DataType) -> Bool) {
                    guard index < types.count, let found = types[index], !ok(found) else { return }
                    report(.typeMismatch("\(name) needs \(wanted), but \(Linter.describe(arguments[index])) is \(Linter.name(found))"))
                }
                switch key {
                case "len", "tocode", "tointeger", "toreal":
                    expect(0, "text", { $0 == .string })
                case "char":
                    expect(0, "text", { $0 == .string })
                    expect(1, "a number", \.isNumeric)
                case "tostring", "size", "eof":
                    break
                case "tofixed":
                    expect(0, "a number", \.isNumeric)
                    expect(1, "a number", \.isNumeric)
                default:
                    expect(0, "a number", \.isNumeric)
                }
                switch key {
                case "abs": return types.first ?? nil
                case "int", "sgn", "random", "len", "size", "tocode", "tointeger": return .integer
                case "char", "tochar", "tofixed", "tostring": return .string
                case "eof": return .boolean
                default: return .real
                }
            }
            for argument in arguments { _ = type(of: argument, scope) }
            guard let function = functions[key] else {
                report(.unknownFunction(name))
                return nil
            }
            return function.returnType
        }
    }

    // MARK: Words

    static func canStore(_ value: DataType, in variable: DataType) -> Bool {
        value == variable || (value.isNumeric && variable.isNumeric)
    }

    static func name(_ type: DataType) -> String {
        switch type {
        case .integer: "an Integer"
        case .real: "a Real"
        case .string: "a String"
        case .boolean: "a Boolean (true or false)"
        }
    }

    static func article(_ type: DataType) -> String {
        name(type) + " value"
    }

    static func symbol(_ op: Operator) -> String {
        switch op {
        case .plus: "+"
        case .minus: "-"
        case .times: "*"
        case .divide: "/"
        case .modulo: "mod"
        case .power: "^"
        default: op.rawValue
        }
    }

    /// A variable by name, a literal as written, anything else generically.
    static func describe(_ expr: Expr) -> String {
        switch expr {
        case .variable(let name), .element(let name, _): name
        case .integer(let value): String(value)
        case .real(let value): String(value)
        case .string(let value): "\"\(value)\""
        case .boolean(let value): value ? "true" : "false"
        case .group(let inner): describe(inner)
        default: "the value"
        }
    }
}
