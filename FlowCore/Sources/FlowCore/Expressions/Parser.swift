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
    var tokens: [Token]
    var position = 0

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

    mutating func parseExpression() throws(ExpressionError) -> Expr { try parseOr() }

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
            lhs = .binary(.or, lhs, try parseAnd())
        }
        return lhs
    }

    mutating func parseAnd() throws(ExpressionError) -> Expr {
        var lhs = try parseRelational()
        while matchOperator([.and]) != nil {
            lhs = .binary(.and, lhs, try parseRelational())
        }
        return lhs
    }

    mutating func parseRelational() throws(ExpressionError) -> Expr {
        var lhs = try parseConcat()
        while let op = matchOperator([.equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual]) {
            lhs = .binary(op, lhs, try parseConcat())
        }
        return lhs
    }

    mutating func parseConcat() throws(ExpressionError) -> Expr {
        var lhs = try parseAdditive()
        while matchOperator([.concat]) != nil {
            lhs = .binary(.concat, lhs, try parseAdditive())
        }
        return lhs
    }

    mutating func parseAdditive() throws(ExpressionError) -> Expr {
        var lhs = try parseMultiplicative()
        while let op = matchOperator([.plus, .minus]) {
            lhs = .binary(op, lhs, try parseMultiplicative())
        }
        return lhs
    }

    mutating func parseMultiplicative() throws(ExpressionError) -> Expr {
        var lhs = try parsePower()
        while let op = matchOperator([.times, .divide, .modulo]) {
            lhs = .binary(op, lhs, try parsePower())
        }
        return lhs
    }

    mutating func parsePower() throws(ExpressionError) -> Expr {
        let base = try parseUnary()
        if matchOperator([.power]) != nil {
            // Right-associative, as in mathematics: 2 ^ 3 ^ 2 = 2 ^ 9.
            return .binary(.power, base, try parsePower())
        }
        return base
    }

    mutating func parseUnary() throws(ExpressionError) -> Expr {
        if let op = matchOperator([.minus, .not, .plus]) {
            let operand = try parseUnary()
            return op == .plus ? operand : .unary(op, operand)
        }
        return try parsePrimary()
    }

    mutating func parsePrimary() throws(ExpressionError) -> Expr {
        let token = peek
        switch token.kind {
        case .integer(let value):
            advance()
            return .integer(value)
        case .real(let value):
            advance()
            return .real(value)
        case .string(let value):
            advance()
            return .string(value)
        case .leftParen:
            advance()
            let inner = try parseExpression()
            try expect(.rightParen, ")")
            return .group(inner)
        case .identifier(let name):
            advance()
            switch name.lowercased() {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            case "pi": return .pi
            default: break
            }
            if peek.kind == .leftParen {
                advance()
                var arguments: [Expr] = []
                if peek.kind != .rightParen {
                    arguments.append(try parseExpression())
                    while peek.kind == .comma {
                        advance()
                        arguments.append(try parseExpression())
                    }
                }
                try expect(.rightParen, ")")
                return .call(name, arguments: arguments)
            }
            if peek.kind == .leftBracket {
                advance()
                let index = try parseExpression()
                try expect(.rightBracket, "]")
                return .element(name, index: index)
            }
            return .variable(name)
        case .end:
            throw ExpressionError(.unexpected("end"), offset: token.offset)
        default:
            throw ExpressionError(.unexpected(token.text), offset: token.offset)
        }
    }
}
