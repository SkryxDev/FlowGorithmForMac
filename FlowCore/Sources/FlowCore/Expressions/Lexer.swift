// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

public struct Token: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case integer(Int64)
        case real(Double)
        case string(String)
        case identifier(String)
        case op(Operator)
        case leftParen, rightParen, leftBracket, rightBracket, comma
        case end
    }

    public var kind: Kind
    /// Offset of the token's first character in the expression.
    public var offset: Int
    public var text: String
}

/// Every operator, already normalized: `&&`, `and` and `∧` all become `.and`.
public enum Operator: String, Hashable, Sendable {
    case plus, minus, times, divide, modulo, power, concat
    case equal, notEqual, less, lessEqual, greater, greaterEqual
    case and, or, not
}

public struct ExpressionError: Error, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case empty
        case invalidCharacter(String)
        case unterminatedString
        case invalidNumber(String)
        case unexpected(String)
        case expected(String, found: String)
        case reservedWord(String)
        case notAVariable(String)
        /// Nested or chained too deeply to evaluate safely.
        case tooComplex
    }

    public var kind: Kind
    public var offset: Int

    public init(_ kind: Kind, offset: Int) {
        self.kind = kind
        self.offset = offset
    }
}

enum Lexer {
    static let wordOperators: [String: Operator] = [
        "and": .and, "or": .or, "not": .not, "mod": .modulo,
    ]

    static func tokenize(_ source: String) throws(ExpressionError) -> [Token] {
        let chars = Array(source)
        var tokens: [Token] = []
        var i = 0

        func add(_ kind: Token.Kind, _ start: Int) {
            tokens.append(Token(kind: kind, offset: start, text: String(chars[start..<i])))
        }

        while i < chars.count {
            let c = chars[i]
            let start = i
            if c.isWhitespace {
                i += 1
                continue
            }
            if c.isNumber && c.isASCII || (c == "." && i + 1 < chars.count && chars[i + 1].isASCII && chars[i + 1].isNumber) {
                while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
                var isReal = false
                if i < chars.count, chars[i] == ".", i + 1 < chars.count, chars[i + 1].isASCII, chars[i + 1].isNumber {
                    isReal = true
                    i += 1
                    while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
                } else if i < chars.count, chars[i] == ".", c == "." {
                    isReal = true
                }
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var j = i + 1
                    if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                    if j < chars.count, chars[j].isASCII, chars[j].isNumber {
                        isReal = true
                        i = j
                        while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
                    }
                }
                let text = String(chars[start..<i])
                if isReal {
                    guard let value = Double(text) else { throw ExpressionError(.invalidNumber(text), offset: start) }
                    add(.real(value), start)
                } else {
                    guard let value = Int64(text) else { throw ExpressionError(.invalidNumber(text), offset: start) }
                    add(.integer(value), start)
                }
                continue
            }
            if c.isLetter || c == "_" {
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { i += 1 }
                let word = String(chars[start..<i])
                if let op = wordOperators[word.lowercased()] {
                    add(.op(op), start)
                } else if word == "π" {
                    add(.identifier("pi"), start)
                } else {
                    add(.identifier(word), start)
                }
                continue
            }
            if c == "\"" || c == "“" || c == "”" {
                i += 1
                var value = ""
                var closed = false
                while i < chars.count {
                    let ch = chars[i]
                    if ch == "\"" || ch == "”" || ch == "“" {
                        // A doubled quote is an escaped quote, as in BASIC.
                        if i + 1 < chars.count, chars[i + 1] == "\"" {
                            value.append("\"")
                            i += 2
                            continue
                        }
                        i += 1
                        closed = true
                        break
                    }
                    value.append(ch)
                    i += 1
                }
                guard closed else { throw ExpressionError(.unterminatedString, offset: start) }
                add(.string(value), start)
                continue
            }

            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            var op: Operator?
            var width = 1
            switch c {
            case "+": op = .plus
            case "-", "−": op = .minus
            case "*", "×": op = .times
            case "/", "÷": op = .divide
            case "%": op = .modulo
            case "^", "↑": op = .power
            case "&":
                if next == "&" { op = .and; width = 2 } else { op = .concat }
            case "|":
                if next == "|" { op = .or; width = 2 }
            case "=":
                op = .equal
                if next == "=" { width = 2 }
            case "!":
                if next == "=" { op = .notEqual; width = 2 } else { op = .not }
            case "<":
                if next == "=" { op = .lessEqual; width = 2 } else if next == ">" { op = .notEqual; width = 2 } else { op = .less }
            case ">":
                if next == "=" { op = .greaterEqual; width = 2 } else { op = .greater }
            case "≠": op = .notEqual
            case "≤": op = .lessEqual
            case "≥": op = .greaterEqual
            case "¬": op = .not
            case "∧": op = .and
            case "∨": op = .or
            case "(":
                i += 1; add(.leftParen, start); continue
            case ")":
                i += 1; add(.rightParen, start); continue
            case "[":
                i += 1; add(.leftBracket, start); continue
            case "]":
                i += 1; add(.rightBracket, start); continue
            case ",":
                i += 1; add(.comma, start); continue
            default:
                break
            }
            guard let op else { throw ExpressionError(.invalidCharacter(String(c)), offset: start) }
            i += width
            add(.op(op), start)
        }
        tokens.append(Token(kind: .end, offset: chars.count, text: ""))
        return tokens
    }
}
