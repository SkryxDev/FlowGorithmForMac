import Foundation

/// Runs a program shape by shape, reporting everything through its `ExecutionController`.
///
/// The interpreter keeps its own call stack (`frames`), so runaway recursion becomes a
/// friendly "stack overflow" error instead of crashing the app.
public final class Interpreter: @unchecked Sendable {
    // Only touched from inside `run()`, which runs as a single task.

    final class Scalar {
        let type: DataType
        var value: Value?
        init(type: DataType, value: Value? = nil) {
            self.type = type
            self.value = value
        }
    }

    /// Arrays are reference types: passing one to a function shares it, as in Flowgorithm.
    final class ArrayStorage {
        let type: DataType
        var elements: [Value?]
        init(type: DataType, count: Int) {
            self.type = type
            self.elements = Array(repeating: nil, count: count)
        }
    }

    enum Slot {
        case scalar(Scalar)
        case array(ArrayStorage)
    }

    final class Frame {
        let function: String
        var slots: [String: Slot] = [:]
        var order: [String] = []
        init(function: String) { self.function = function }

        func declare(_ name: String, _ slot: Slot) throws(RuntimeError) {
            let key = name.lowercased()
            if slots[key] != nil { throw RuntimeError(.alreadyDeclared(name)) }
            slots[key] = slot
            order.append(name)
        }

        func slot(_ name: String) throws(RuntimeError) -> Slot {
            guard let slot = slots[name.lowercased()] else { throw RuntimeError(.undeclaredVariable(name)) }
            return slot
        }
    }

    struct OpenFile {
        var url: URL
        var mode: FileMode
        var lines: [String] = []
        var nextLine = 0
        var buffer = ""
    }

    public let program: Program
    public let controller: ExecutionController
    public let baseDirectory: URL?
    public let maxDepth: Int

    var functions: [String: CompiledFunction] = [:]
    var frames: [Frame] = []
    var mainFrame: Frame?
    var file: OpenFile?
    var turtleX = 0.0, turtleY = 0.0, turtleHeading = 90.0
    var penColor = PenColor.black
    var lastSnapshot = ContinuousClock.now
    var currentFunction = "Main"

    public init(program: Program, controller: ExecutionController, baseDirectory: URL? = nil, maxDepth: Int = 5000) {
        self.program = program
        self.controller = controller
        self.baseDirectory = baseDirectory
        self.maxDepth = maxDepth
    }

    /// Checks a program for syntax errors without running it.
    public static func check(_ program: Program) -> RuntimeError? {
        do {
            _ = try Compiler.compile(program)
            return nil
        } catch {
            return error
        }
    }

    @concurrent
    public func run() async {
        defer { controller.finish() }
        do {
            functions = try Compiler.compile(program)
            guard let main = program.main, let compiled = functions[main.name.lowercased()] else {
                throw RuntimeError(.noMainFunction)
            }
            controller.emit(.turtle(.turtle(position: TurtlePoint(x: 0, y: 0), heading: 90)))
            _ = try await invoke(compiled, arguments: [])
            try flushFile()
            controller.emit(.finished(snapshot()))
        } catch let error as RuntimeError {
            try? flushFile()
            controller.emit(.failed(error, snapshot()))
        } catch {
            try? flushFile()
            controller.emit(.stopped(snapshot()))
        }
    }

    // MARK: Snapshots

    func snapshot() -> VariablesSnapshot {
        let visible = frames.isEmpty ? (mainFrame.map { [$0] } ?? []) : frames
        return VariablesSnapshot(frames: visible.enumerated().map { index, frame in
            VariablesSnapshot.Frame(id: index, function: frame.function, variables: frame.order.compactMap { name in
                switch frame.slots[name.lowercased()] {
                case .scalar(let scalar):
                    VariablesSnapshot.Variable(name: name, type: scalar.type, value: scalar.value, elements: nil)
                case .array(let array):
                    VariablesSnapshot.Variable(name: name, type: array.type, value: nil, elements: array.elements)
                case nil:
                    nil
                }
            })
        })
    }

    // MARK: Functions

    func invoke(_ compiled: CompiledFunction, arguments: [Expr], caller: Frame? = nil) async throws -> Value? {
        let function = compiled.function
        guard arguments.count == function.parameters.count else {
            throw RuntimeError(.wrongArgumentCount(function: function.name, expected: function.parameters.count, found: arguments.count))
        }
        if frames.count >= maxDepth { throw RuntimeError(.stackOverflow(limit: maxDepth)) }

        let frame = Frame(function: function.name)
        for (parameter, argument) in zip(function.parameters, arguments) {
            if parameter.isArray {
                guard case .variable(let name) = argument.unwrapped, let caller,
                      case .array(let storage) = try caller.slot(name) else {
                    throw RuntimeError(.argumentMustBeArray(function: function.name, parameter: parameter.name))
                }
                guard storage.type == parameter.type else {
                    throw RuntimeError(.argumentType(function: function.name, parameter: parameter.name,
                                                     expected: parameter.type, found: storage.type))
                }
                try frame.declare(parameter.name, .array(storage))
            } else {
                guard let caller else { throw RuntimeError(.noMainFunction) }
                let value = try await evaluate(argument, in: caller)
                let converted: Value
                do {
                    converted = try convert(value, to: parameter.type, name: parameter.name)
                } catch {
                    throw RuntimeError(.argumentType(function: function.name, parameter: parameter.name,
                                                     expected: parameter.type, found: value.type))
                }
                try frame.declare(parameter.name, .scalar(Scalar(type: parameter.type, value: converted)))
            }
        }

        let previousFunction = currentFunction
        frames.append(frame)
        if frames.count == 1 { mainFrame = frame }
        currentFunction = function.name
        defer {
            if frames.count > 1 || mainFrame !== frame { frames.removeLast() }
            currentFunction = previousFunction
        }

        try await execute(compiled.body, in: frame)

        guard let returnType = function.returnType else { return nil }
        let variable = function.returnVariable.trimmingCharacters(in: .whitespaces)
        guard !variable.isEmpty, let slot = frame.slots[variable.lowercased()], case .scalar(let scalar) = slot else {
            throw RuntimeError(.returnVariableMissing(function: function.name, variable: variable), functionName: function.name)
        }
        guard let value = scalar.value else {
            throw RuntimeError(.unassignedVariable(variable), functionName: function.name)
        }
        return try convert(value, to: returnType, name: variable)
    }

    func callUser(_ name: String, arguments: [Expr], in frame: Frame, needsValue: Bool) async throws -> Value? {
        guard let compiled = functions[name.lowercased()] else { throw RuntimeError(.unknownFunction(name)) }
        if needsValue && compiled.function.returnType == nil { throw RuntimeError(.noReturnValue(compiled.function.name)) }
        return try await invoke(compiled, arguments: arguments, caller: frame)
    }

    // MARK: Statements

    func execute(_ block: [CompiledStatement], in frame: Frame) async throws {
        for statement in block {
            do {
                try await execute(statement, in: frame)
            } catch var error as RuntimeError {
                if error.statementID == nil {
                    error.statementID = statement.id
                    error.functionName = frame.function
                }
                throw error
            }
        }
    }

    func checkpoint(_ statement: CompiledStatement, in frame: Frame, breakpoint: Bool = false) async throws {
        try await controller.checkpoint(statement.id, function: frame.function, breakpoint: breakpoint) { snapshot() }
        let now = ContinuousClock.now
        if now - lastSnapshot > .milliseconds(120) {
            lastSnapshot = now
            controller.emit(.variables(snapshot()))
        }
    }

    func execute(_ statement: CompiledStatement, in frame: Frame) async throws {
        switch statement.operation {
        case .nothing:
            return
        case .breakpoint(let condition):
            var hit = true
            if let condition { hit = try await self.condition(condition, in: frame) }
            try await checkpoint(statement, in: frame, breakpoint: hit)
            return
        default:
            try await checkpoint(statement, in: frame)
        }

        switch statement.operation {
        case .nothing, .breakpoint:
            break

        case .declare(let names, let type, let sizeExpr):
            if let sizeExpr {
                let size = try integer(try await evaluate(sizeExpr, in: frame), context: "Size")
                guard size >= 0, size <= 10_000_000 else { throw RuntimeError(.invalidArraySize(size)) }
                for name in names { try frame.declare(name, .array(ArrayStorage(type: type, count: Int(size)))) }
            } else {
                for name in names { try frame.declare(name, .scalar(Scalar(type: type))) }
            }

        case .assign(let target, let expr):
            let value = try await evaluate(expr, in: frame)
            try await store(value, into: target, in: frame)

        case .input(let target):
            let type = try targetType(target, in: frame)
            while true {
                let text = try await controller.readInput(variable: target.display, type: type)
                if let value = Interpreter.parseInput(text, as: type) {
                    try await store(value, into: target, in: frame)
                    break
                }
                controller.emit(.inputRejected(text: text, type: type))
            }

        case .output(let expr, let newline):
            let value = try await evaluate(expr, in: frame)
            controller.emit(.output(value.displayString, newline: newline))

        case .ifElse(let condition, let thenBlock, let elseBlock):
            if try await self.condition(condition, in: frame) {
                try await execute(thenBlock, in: frame)
            } else {
                try await execute(elseBlock, in: frame)
            }

        case .whileLoop(let condition, let body):
            while try await self.condition(condition, in: frame) {
                try await execute(body, in: frame)
                try await checkpoint(statement, in: frame)
            }

        case .doLoop(let condition, let body):
            repeat {
                try await execute(body, in: frame)
                try await checkpoint(statement, in: frame)
            } while try await self.condition(condition, in: frame)

        case .forLoop(let name, let startExpr, let endExpr, let stepExpr, let decreasing, let body):
            let target = LValue(name: name, index: nil)
            let type = try targetType(target, in: frame)
            guard type.isNumeric else {
                throw RuntimeError(.cannotAssign(value: .integer, variable: name, variableType: type))
            }
            let start = try await evaluate(startExpr, in: frame)
            let end = try await evaluate(endExpr, in: frame)
            let step = try await evaluate(stepExpr, in: frame)
            guard let startNumber = start.numeric, let endNumber = end.numeric, let stepNumber = step.numeric else {
                throw RuntimeError(.typeMismatch(operation: "For", left: start.type, right: end.type))
            }
            let increment = decreasing ? -abs(stepNumber) : abs(stepNumber)
            if increment == 0 { throw RuntimeError(.invalidArgument(function: "For")) }
            var current = startNumber
            while decreasing ? current >= endNumber : current <= endNumber {
                let value: Value = type == .integer ? .integer(Int64(current)) : .real(current)
                try await store(value, into: target, in: frame)
                try await execute(body, in: frame)
                try await checkpoint(statement, in: frame)
                // Re-read the loop variable, so changes made in the body count, like in Flowgorithm.
                guard case .scalar(let scalar) = try frame.slot(name), let now = scalar.value?.numeric else { break }
                current = now + increment
            }

        case .call(let name, let arguments):
            if Identifier.intrinsicNames.contains(name.lowercased()) {
                _ = try await intrinsic(name, arguments, in: frame)
            } else {
                _ = try await callUser(name, arguments: arguments, in: frame, needsValue: false)
            }

        case .open(let expr, let mode):
            if file != nil { throw RuntimeError(.fileAlreadyOpen) }
            let path = try await evaluate(expr, in: frame).displayString
            let url = resolve(path)
            var open = OpenFile(url: url, mode: mode)
            switch mode {
            case .read:
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    var lines = text.components(separatedBy: .newlines)
                    if lines.last == "" { lines.removeLast() }
                    open.lines = lines
                } catch {
                    throw RuntimeError(.fileError(url.lastPathComponent))
                }
            case .append:
                open.buffer = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            case .write:
                break
            }
            file = open

        case .close:
            guard file != nil else { throw RuntimeError(.fileNotOpen) }
            try flushFile()
            file = nil

        case .read(let target):
            guard var open = file else { throw RuntimeError(.fileNotOpen) }
            guard open.mode == .read else { throw RuntimeError(.fileWrongMode) }
            guard open.nextLine < open.lines.count else { throw RuntimeError(.endOfFile) }
            let line = open.lines[open.nextLine]
            open.nextLine += 1
            file = open
            let type = try targetType(target, in: frame)
            guard let value = Interpreter.parseInput(line, as: type) else {
                throw RuntimeError(.invalidConversion(value: line, to: type))
            }
            try await store(value, into: target, in: frame)

        case .write(let expr):
            guard file != nil else { throw RuntimeError(.fileNotOpen) }
            guard file?.mode != .read else { throw RuntimeError(.fileWrongMode) }
            let value = try await evaluate(expr, in: frame)
            file?.buffer += value.displayString + "\n"

        case .turn(let expr, let direction):
            let degrees = try number(try await evaluate(expr, in: frame), context: "Turn")
            turtleHeading += direction == .left ? degrees : -degrees
            turtleHeading = turtleHeading.truncatingRemainder(dividingBy: 360)
            emitTurtle()

        case .forward(let expr, let penDown):
            let distance = try number(try await evaluate(expr, in: frame), context: "Forward")
            let radians = turtleHeading * .pi / 180
            let from = TurtlePoint(x: turtleX, y: turtleY)
            turtleX += distance * cos(radians)
            turtleY += distance * sin(radians)
            let to = TurtlePoint(x: turtleX, y: turtleY)
            controller.emit(.turtle(.line(from: from, to: to, color: penColor, drawn: penDown)))
            emitTurtle()

        case .home:
            turtleX = 0
            turtleY = 0
            turtleHeading = 90
            emitTurtle()

        case .clear:
            controller.emit(.turtle(.clear))
            turtleX = 0
            turtleY = 0
            turtleHeading = 90
            emitTurtle()

        case .pen(let color):
            penColor = color
        }
    }

    func emitTurtle() {
        controller.emit(.turtle(.turtle(position: TurtlePoint(x: turtleX, y: turtleY), heading: turtleHeading)))
    }

    func resolve(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(expanded)
    }

    func flushFile() throws {
        guard let open = file, open.mode != .read else { return }
        do {
            try open.buffer.write(to: open.url, atomically: true, encoding: .utf8)
        } catch {
            throw RuntimeError(.fileError(open.url.lastPathComponent))
        }
    }

    // MARK: Variables

    func targetType(_ target: LValue, in frame: Frame) throws(RuntimeError) -> DataType {
        switch try frame.slot(target.name) {
        case .scalar(let scalar):
            if target.index != nil { throw RuntimeError(.notAnArray(target.name)) }
            return scalar.type
        case .array(let array):
            if target.index == nil { throw RuntimeError(.isAnArray(target.name)) }
            return array.type
        }
    }

    func store(_ value: Value, into target: LValue, in frame: Frame) async throws {
        switch try frame.slot(target.name) {
        case .scalar(let scalar):
            if target.index != nil { throw RuntimeError(.notAnArray(target.name)) }
            scalar.value = try convert(value, to: scalar.type, name: target.name)
        case .array(let array):
            guard let indexExpr = target.index else { throw RuntimeError(.isAnArray(target.name)) }
            let index = try await arrayIndex(indexExpr, name: target.name, count: array.elements.count, in: frame)
            array.elements[index] = try convert(value, to: array.type, name: target.name)
        }
    }

    func arrayIndex(_ expr: Expr, name: String, count: Int, in frame: Frame) async throws -> Int {
        let index = try integer(try await evaluate(expr, in: frame), context: "[ ]")
        guard index >= 0, index < count else { throw RuntimeError(.indexOutOfBounds(name: name, index: index, size: count)) }
        return Int(index)
    }

    /// Converts a value for storage in a variable of `type`. Reals stored in integers lose their fraction.
    func convert(_ value: Value, to type: DataType, name: String) throws(RuntimeError) -> Value {
        switch (value, type) {
        case (.integer, .integer), (.real, .real), (.string, .string), (.boolean, .boolean):
            return value
        case (.integer(let v), .real):
            return .real(Double(v))
        case (.real(let v), .integer):
            guard v.isFinite, let truncated = Int64(exactly: v.rounded(.towardZero)) else { throw RuntimeError(.overflow) }
            return .integer(truncated)
        default:
            throw RuntimeError(.cannotAssign(value: value.type, variable: name, variableType: type))
        }
    }

    static func parseInput(_ text: String, as type: DataType) -> Value? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch type {
        case .string:
            return .string(text)
        case .integer:
            if let v = Int64(trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed) { return .integer(v) }
            return nil
        case .real:
            if let v = Double(trimmed.replacingOccurrences(of: ",", with: ".")), v.isFinite { return .real(v) }
            return nil
        case .boolean:
            switch trimmed.lowercased() {
            case "true", "vero", "1", "yes", "si", "sì": return .boolean(true)
            case "false", "falso", "0", "no": return .boolean(false)
            default: return nil
            }
        }
    }

    // MARK: Expressions

    func condition(_ expr: Expr, in frame: Frame) async throws -> Bool {
        let value = try await evaluate(expr, in: frame)
        guard case .boolean(let b) = value else { throw RuntimeError(.conditionNotBoolean(value.type)) }
        return b
    }

    func integer(_ value: Value, context: String) throws(RuntimeError) -> Int64 {
        switch value {
        case .integer(let v): return v
        case .real(let v) where v.rounded(.towardZero) == v && v.isFinite:
            guard let exact = Int64(exactly: v) else { throw RuntimeError(.overflow) }
            return exact
        default: throw RuntimeError(.typeMismatch(operation: context, left: value.type, right: nil))
        }
    }

    func number(_ value: Value, context: String) throws(RuntimeError) -> Double {
        guard let n = value.numeric else { throw RuntimeError(.typeMismatch(operation: context, left: value.type, right: nil)) }
        return n
    }

    func evaluate(_ expr: Expr, in frame: Frame) async throws -> Value {
        switch expr {
        case .integer(let v): return .integer(v)
        case .real(let v): return .real(v)
        case .string(let v): return .string(v)
        case .boolean(let v): return .boolean(v)
        case .pi: return .real(.pi)
        case .group(let inner): return try await evaluate(inner, in: frame)

        case .variable(let name):
            switch try frame.slot(name) {
            case .scalar(let scalar):
                guard let value = scalar.value else { throw RuntimeError(.unassignedVariable(name)) }
                return value
            case .array:
                throw RuntimeError(.isAnArray(name))
            }

        case .element(let name, let indexExpr):
            guard case .array(let array) = try frame.slot(name) else { throw RuntimeError(.notAnArray(name)) }
            let index = try await arrayIndex(indexExpr, name: name, count: array.elements.count, in: frame)
            guard let value = array.elements[index] else { throw RuntimeError(.unassignedVariable("\(name)[\(index)]")) }
            return value

        case .call(let name, let arguments):
            if Identifier.intrinsicNames.contains(name.lowercased()) {
                return try await intrinsic(name, arguments, in: frame)
            }
            guard let value = try await callUser(name, arguments: arguments, in: frame, needsValue: true) else {
                throw RuntimeError(.noReturnValue(name))
            }
            return value

        case .unary(let op, let operand):
            let value = try await evaluate(operand, in: frame)
            switch (op, value) {
            case (.minus, .integer(let v)):
                let (result, overflow) = Int64(0).subtractingReportingOverflow(v)
                if overflow { throw RuntimeError(.overflow) }
                return .integer(result)
            case (.minus, .real(let v)):
                return .real(-v)
            case (.not, .boolean(let v)):
                return .boolean(!v)
            default:
                throw RuntimeError(.typeMismatch(operation: op.symbol, left: value.type, right: nil))
            }

        case .binary(.and, let lhs, let rhs):
            guard case .boolean(let l) = try await evaluate(lhs, in: frame) else {
                throw RuntimeError(.typeMismatch(operation: "and", left: try await evaluate(lhs, in: frame).type, right: nil))
            }
            if !l { return .boolean(false) }
            let r = try await evaluate(rhs, in: frame)
            guard case .boolean(let rb) = r else { throw RuntimeError(.typeMismatch(operation: "and", left: .boolean, right: r.type)) }
            return .boolean(rb)

        case .binary(.or, let lhs, let rhs):
            let lv = try await evaluate(lhs, in: frame)
            guard case .boolean(let l) = lv else { throw RuntimeError(.typeMismatch(operation: "or", left: lv.type, right: nil)) }
            if l { return .boolean(true) }
            let r = try await evaluate(rhs, in: frame)
            guard case .boolean(let rb) = r else { throw RuntimeError(.typeMismatch(operation: "or", left: .boolean, right: r.type)) }
            return .boolean(rb)

        case .binary(let op, let lhs, let rhs):
            let l = try await evaluate(lhs, in: frame)
            let r = try await evaluate(rhs, in: frame)
            return try Interpreter.apply(op, l, r)
        }
    }

    static func apply(_ op: Operator, _ l: Value, _ r: Value) throws(RuntimeError) -> Value {
        func mismatch() -> RuntimeError { RuntimeError(.typeMismatch(operation: op.symbol, left: l.type, right: r.type)) }

        switch op {
        case .concat:
            return .string(l.displayString + r.displayString)

        case .plus, .minus, .times:
            if case .integer(let a) = l, case .integer(let b) = r {
                let (result, overflow) = switch op {
                case .plus: a.addingReportingOverflow(b)
                case .minus: a.subtractingReportingOverflow(b)
                default: a.multipliedReportingOverflow(by: b)
                }
                if overflow { throw RuntimeError(.overflow) }
                return .integer(result)
            }
            guard let a = l.numeric, let b = r.numeric else { throw mismatch() }
            let result = op == .plus ? a + b : op == .minus ? a - b : a * b
            return .real(result)

        case .divide:
            guard let a = l.numeric, let b = r.numeric else { throw mismatch() }
            if b == 0 { throw RuntimeError(.divisionByZero) }
            return .real(a / b)

        case .modulo:
            if case .integer(let a) = l, case .integer(let b) = r {
                if b == 0 { throw RuntimeError(.divisionByZero) }
                let (result, overflow) = a.remainderReportingOverflow(dividingBy: b)
                if overflow { throw RuntimeError(.overflow) }
                return .integer(result)
            }
            guard let a = l.numeric, let b = r.numeric else { throw mismatch() }
            if b == 0 { throw RuntimeError(.divisionByZero) }
            return .real(a.truncatingRemainder(dividingBy: b))

        case .power:
            guard let a = l.numeric, let b = r.numeric else { throw mismatch() }
            let result = Foundation.pow(a, b)
            if result.isNaN { throw RuntimeError(.mathDomain(function: "^")) }
            return .real(result)

        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            let order: ComparisonResult
            switch (l, r) {
            case (.string(let a), .string(let b)):
                order = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            case (.boolean(let a), .boolean(let b)):
                guard op == .equal || op == .notEqual else { throw mismatch() }
                order = a == b ? .orderedSame : .orderedAscending
            default:
                if case .integer(let a) = l, case .integer(let b) = r {
                    order = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
                } else {
                    guard let a = l.numeric, let b = r.numeric else { throw mismatch() }
                    order = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
                }
            }
            let result = switch op {
            case .equal: order == .orderedSame
            case .notEqual: order != .orderedSame
            case .less: order == .orderedAscending
            case .lessEqual: order != .orderedDescending
            case .greater: order == .orderedDescending
            default: order != .orderedAscending
            }
            return .boolean(result)

        case .and, .or, .not:
            throw mismatch()
        }
    }
}

extension Expr {
    /// The expression without surrounding parentheses.
    var unwrapped: Expr {
        if case .group(let inner) = self { return inner.unwrapped }
        return self
    }
}

extension LValue {
    var display: String { name }
}

extension Operator {
    public var symbol: String {
        switch self {
        case .plus: "+"
        case .minus: "-"
        case .times: "*"
        case .divide: "/"
        case .modulo: "mod"
        case .power: "^"
        case .concat: "&"
        case .equal: "="
        case .notEqual: "<>"
        case .less: "<"
        case .lessEqual: "<="
        case .greater: ">"
        case .greaterEqual: ">="
        case .and: "and"
        case .or: "or"
        case .not: "not"
        }
    }
}
