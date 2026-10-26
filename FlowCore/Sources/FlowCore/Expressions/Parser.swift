import Foundation

/// A parsed expression.
public indirect enum Expr: Hashable, Sendable {
    case integer(Int64)
    case real(Double)
    case string(String)
    case boolean(Bool)
    case pi
    case variable(String)
    case element(String, index: Expr)
    case call(String, arguments: [Expr])
    case unary(Operator, Expr)
    case binary(Operator, Expr, Expr)
    /// Parentheses are kept so code generators can reproduce them.
    case group(Expr)
}

/// The target of an assignment, input or read: `x` or `a[i]`.
public struct LValue: Hashable, Sendable {
    public var name: String
    public var index: Expr?
}

public enum Identifier {
    public static let reservedWords: Set<String> = ["and", "false", "mod", "not", "or", "pi", "true"]
    public static let typeNames: Set<String> = ["boolean", "integer", "real", "string"]
    public static let intrinsicNames: Set<String> = [
        "abs", "arccos", "arcsin", "arctan", "char", "cos", "eof", "int", "len", "ln", "log", "log10",
        "random", "sgn", "sin", "size", "sqrt", "tan", "tochar", "tocode", "tofixed", "tointeger", "toreal", "tostring",
    ]
    public static let futureNames: Set<String> = ["arccosh", "arcsinh", "arctanh", "cosh", "sinh", "tanh"]

    public enum Problem: Hashable, Sendable {
        case empty, invalidCharacters, reserved
    }

    /// Checks a name for a variable or function: a letter, then letters or digits.
    public static func validate(_ name: String) -> Problem? {
        guard let first = name.first else { return .empty }
        guard first.isLetter, name.allSatisfy({ $0.isLetter || $0.isNumber }) else { return .invalidCharacters }
        let lower = name.lowercased()
        if reservedWords.contains(lower) || typeNames.contains(lower) || intrinsicNames.contains(lower) || futureNames.contains(lower) {
            return .reserved
        }
        return nil
    }
}

public enum ExpressionParser {
    public static func parse(_ source: String) throws(ExpressionError) -> Expr {
        var parser = try Parser(source)
        if parser.peek.kind == .end { throw ExpressionError(.empty, offset: 0) }
        let expr = try parser.parseExpression()
        try parser.expectEnd()
        return expr
    }

    public static func parseLValue(_ source: String) throws(ExpressionError) -> LValue {
        var parser = try Parser(source)
        let token = parser.peek
        guard case .identifier(let name) = token.kind else {
            if token.kind == .end { throw ExpressionError(.empty, offset: 0) }
            throw ExpressionError(.notAVariable(source.trimmingCharacters(in: .whitespaces)), offset: token.offset)
        }
        parser.advance()
        var index: Expr?
        if parser.peek.kind == .leftBracket {
            parser.advance()
            index = try parser.parseExpression()
            try parser.expect(.rightBracket, "]")
        }
        try parser.expectEnd()
        return LValue(name: name, index: index)
    }

    /// Parses `name(arg, ...)` for the Call shape.
    public static func parseCall(_ source: String) throws(ExpressionError) -> (name: String, arguments: [Expr]) {
        let expr = try parse(source)
        switch expr {
        case .call(let name, let arguments): return (name, arguments)
        case .variable(let name): return (name, [])
        default: throw ExpressionError(.expected("function call", found: source), offset: 0)
        }
    }
}

struct Parser {
    /// Parsing, checking and running an expression all recurse, so very deep expressions are
    /// refused: a crafted file could otherwise exhaust the stack and crash the app.
    /// `maxNesting` counts open parentheses, arguments, signs and powers; `maxHeight` is the
    /// height of the finished tree (`1 + 1 + 1 + …` is flat to parse but tall to evaluate).
    /// 32 is far beyond any real expression and keeps the parser within a 512 KB thread stack
    /// even in debug builds, where each level costs several kilobytes.
    static let maxNesting = 32
    static let maxHeight = 256

    var tokens: [Token]
    var position = 0
    var nesting = 0
    /// The height of the tree the last parse function returned.
    var height = 0

    init(_ source: String) throws(ExpressionError) {
        tokens = try Lexer.tokenize(source)
    }

    var peek: Token { tokens[position] }

    mutating func advance() { if position < tokens.count - 1 { position += 1 } }

    func describe(_ token: Token) -> String {
        token.kind == .end ? "end" : token.text
    }

    mutating func expect(_ kind: Token.Kind, _ text: String) throws(ExpressionError) {
        guard peek.kind == kind else { throw ExpressionError(.expected(text, found: describe(peek)), offset: peek.offset) }
        advance()
    }

    func expectEnd() throws(ExpressionError) {
        guard peek.kind == .end else { throw ExpressionError(.unexpected(describe(peek)), offset: peek.offset) }
    }

    /// Called before descending another level; pair it with `defer { nesting -= 1 }`.
    mutating func enter() throws(ExpressionError) {
        nesting += 1
        if nesting > Parser.maxNesting { throw ExpressionError(.tooComplex, offset: peek.offset) }
    }

    /// A literal or a plain variable.
    mutating func leaf(_ expr: Expr) -> Expr {
        height = 1
        return expr
    }

    /// A node whose tallest child is `child` high.
    mutating func node(_ expr: Expr, over child: Int) throws(ExpressionError) -> Expr {
        height = child + 1
        if height > Parser.maxHeight { throw ExpressionError(.tooComplex, offset: peek.offset) }
        return expr
    }

    mutating func parseExpression() throws(ExpressionError) -> Expr {
        try enter()
        defer { nesting -= 1 }
        return try parseOr()
    }

    mutating func matchOperator(_ ops: Set<Operator>) -> Operator? {
        if case .op(let op) = peek.kind, ops.contains(op) {
            advance()
            return op
        }
        return nil
    }

    mutating func parseOr() throws(ExpressionError) -> Expr {
        var lhs = try parseAnd()
        while matchOperator([.or]) != nil {
            let left = height
            let rhs = try parseAnd()
            lhs = try node(.binary(.or, lhs, rhs), over: max(left, height))
        }
        return lhs
    }

    mutating func parseAnd() throws(ExpressionError) -> Expr {
        var lhs = try parseRelational()
        while matchOperator([.and]) != nil {
            let left = height
            let rhs = try parseRelational()
            lhs = try node(.binary(.and, lhs, rhs), over: max(left, height))
        }
        return lhs
    }

    mutating func parseRelational() throws(ExpressionError) -> Expr {
        var lhs = try parseConcat()
        while let op = matchOperator([.equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual]) {
            let left = height
            let rhs = try parseConcat()
            lhs = try node(.binary(op, lhs, rhs), over: max(left, height))
        }
        return lhs
    }

    mutating func parseConcat() throws(ExpressionError) -> Expr {
        var lhs = try parseAdditive()
        while matchOperator([.concat]) != nil {
            let left = height
            let rhs = try parseAdditive()
            lhs = try node(.binary(.concat, lhs, rhs), over: max(left, height))
        }
        return lhs
    }

    mutating func parseAdditive() throws(ExpressionError) -> Expr {
        var lhs = try parseMultiplicative()
        while let op = matchOperator([.plus, .minus]) {
            let left = height
            let rhs = try parseMultiplicative()
            lhs = try node(.binary(op, lhs, rhs), over: max(left, height))
        }
        return lhs
    }

    mutating func parseMultiplicative() throws(ExpressionError) -> Expr {
        var lhs = try parsePower()
        while let op = matchOperator([.times, .divide, .modulo]) {
            let left = height
            let rhs = try parsePower()
            lhs = try node(.binary(op, lhs, rhs), over: max(left, height))
        }
        return lhs
    }

    mutating func parsePower() throws(ExpressionError) -> Expr {
        let base = try parseUnary()
        let left = height
        if matchOperator([.power]) != nil {
            // Right-associative, as in mathematics: 2 ^ 3 ^ 2 = 2 ^ 9.
            try enter()
            defer { nesting -= 1 }
            let exponent = try parsePower()
            return try node(.binary(.power, base, exponent), over: max(left, height))
        }
        return base
    }

    mutating func parseUnary() throws(ExpressionError) -> Expr {
        if let op = matchOperator([.minus, .not, .plus]) {
            try enter()
            defer { nesting -= 1 }
            let operand = try parseUnary()
            if op == .plus { return operand }
            return try node(.unary(op, operand), over: height)
        }
        return try parsePrimary()
    }

    /// Only dispatches: each kind of operand has its own function, so the frames on the
    /// recursive path (parentheses, arguments, indexes) stay small even in debug builds.
    mutating func parsePrimary() throws(ExpressionError) -> Expr {
        switch peek.kind {
        case .leftParen: try parseGroup()
        case .identifier: try parseName()
        default: try parseLiteral()
        }
    }

    @inline(never)
    mutating func parseGroup() throws(ExpressionError) -> Expr {
        advance()
        let inner = try parseExpression()
        try expect(.rightParen, ")")
        return try node(.group(inner), over: height)
    }

    /// A variable, a constant, an array element or a function call.
    @inline(never)
    mutating func parseName() throws(ExpressionError) -> Expr {
        guard case .identifier(let name) = peek.kind else { return try parseLiteral() }
        advance()
        switch name.lowercased() {
        case "true": return leaf(.boolean(true))
        case "false": return leaf(.boolean(false))
        case "pi": return leaf(.pi)
        default: break
        }
        if peek.kind == .leftParen { return try parseCall(name) }
        if peek.kind == .leftBracket { return try parseElement(name) }
        return leaf(.variable(name))
    }

    @inline(never)
    mutating func parseCall(_ name: String) throws(ExpressionError) -> Expr {
        advance()
        var arguments: [Expr] = []
        var tallest = 0
        if peek.kind != .rightParen {
            arguments.append(try parseExpression())
            tallest = height
            while peek.kind == .comma {
                advance()
                arguments.append(try parseExpression())
                tallest = max(tallest, height)
            }
        }
        try expect(.rightParen, ")")
        return try node(.call(name, arguments: arguments), over: tallest)
    }

    @inline(never)
    mutating func parseElement(_ name: String) throws(ExpressionError) -> Expr {
        advance()
        let index = try parseExpression()
        try expect(.rightBracket, "]")
        return try node(.element(name, index: index), over: height)
    }

    @inline(never)
    mutating func parseLiteral() throws(ExpressionError) -> Expr {
        let token = peek
        switch token.kind {
        case .integer(let value):
            advance()
            return leaf(.integer(value))
        case .real(let value):
            advance()
            return leaf(.real(value))
        case .string(let value):
            advance()
            return leaf(.string(value))
        case .end:
            throw ExpressionError(.unexpected("end"), offset: token.offset)
        default:
            throw ExpressionError(.unexpected(token.text), offset: token.offset)
        }
    }
}
