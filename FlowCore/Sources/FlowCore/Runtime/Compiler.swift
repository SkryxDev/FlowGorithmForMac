import Foundation

/// A statement with its expressions already parsed, ready to run.
struct CompiledStatement {
    indirect enum Operation {
        case declare(names: [String], type: DataType, size: Expr?)
        case assign(LValue, Expr)
        case input(LValue)
        case output(Expr, newline: Bool)
        case ifElse(Expr, then: [CompiledStatement], else: [CompiledStatement])
        case whileLoop(Expr, body: [CompiledStatement])
        case doLoop(Expr, body: [CompiledStatement])
        case forLoop(variable: String, start: Expr, end: Expr, step: Expr, decreasing: Bool, body: [CompiledStatement])
        case call(String, arguments: [Expr])
        case breakpoint(condition: Expr?)
        case open(Expr, FileMode)
        case close
        case read(LValue)
        case write(Expr)
        case turn(Expr, TurnDirection)
        case forward(Expr, penDown: Bool)
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
            result[function.name.lowercased()] = CompiledFunction(function: function, body: body)
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

        func expr(_ source: String) throws(RuntimeError) -> Expr {
            do {
                return try ExpressionParser.parse(source)
            } catch {
                throw RuntimeError(.syntax(error, source: source), statementID: id, functionName: function)
            }
        }

        func lvalue(_ source: String) throws(RuntimeError) -> LValue {
            do {
                return try ExpressionParser.parseLValue(source)
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
            operation = .declare(names: names, type: s.type, size: s.isArray ? try expr(s.size) : nil)
        case .assign(let s):
            operation = .assign(try lvalue(s.variable), try expr(s.expression))
        case .input(let s):
            operation = .input(try lvalue(s.variable))
        case .output(let s):
            operation = .output(try expr(s.expression), newline: s.newline)
        case .if(let s):
            operation = .ifElse(try expr(s.expression), then: try body(s.thenBody), else: try body(s.elseBody))
        case .while(let s):
            operation = .whileLoop(try expr(s.expression), body: try body(s.body))
        case .do(let s):
            operation = .doLoop(try expr(s.expression), body: try body(s.body))
        case .for(let s):
            let variable = try lvalue(s.variable)
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
                operation = .call(call.name, arguments: call.arguments)
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
            operation = .read(try lvalue(s.variable))
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
