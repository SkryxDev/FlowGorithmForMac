// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

extension Interpreter {
    /// Size() and EOF() look at an array or the open file rather than at argument values.
    func specialIntrinsic(_ function: Intrinsic, display: String, count: Int, array: Name?, in frame: Frame) throws(RuntimeError) -> Value? {
        switch function {
        case .size:
            guard count == 1 else { throw RuntimeError(.wrongArgumentCount(function: display, expected: 1, found: count)) }
            guard let array, case .array(let storage) = try frame.slot(array) else {
                throw RuntimeError(.argumentMustBeArray(function: display, parameter: "a"))
            }
            return .integer(Int64(storage.elements.count))
        case .eof:
            guard count == 0 else { throw RuntimeError(.wrongArgumentCount(function: display, expected: 0, found: count)) }
            guard let open = file else { throw RuntimeError(.fileNotOpen) }
            guard open.mode == .read else { throw RuntimeError(.fileWrongMode) }
            return .boolean(open.nextLine >= open.lines.count)
        default:
            return nil
        }
    }

    /// Every other built-in function, applied to already evaluated arguments.
    func intrinsic(_ function: Intrinsic, display name: String, _ values: [Value]) throws(RuntimeError) -> Value {
        func expectCount(_ count: Int) throws(RuntimeError) {
            guard values.count == count else {
                throw RuntimeError(.wrongArgumentCount(function: name, expected: count, found: values.count))
            }
        }

        func num(_ i: Int) throws(RuntimeError) -> Double {
            guard let n = values[i].numeric else {
                throw RuntimeError(.typeMismatch(operation: name, left: values[i].type, right: nil))
            }
            return n
        }

        func str(_ i: Int) throws(RuntimeError) -> String {
            guard case .string(let s) = values[i] else {
                throw RuntimeError(.typeMismatch(operation: name, left: values[i].type, right: nil))
            }
            return s
        }

        func real(_ v: Double) throws(RuntimeError) -> Value {
            guard v.isFinite else { throw RuntimeError(.mathDomain(function: name)) }
            return .real(v)
        }

        switch function {
        case .size, .eof:
            // Handled by specialIntrinsic before arguments are evaluated.
            throw RuntimeError(.invalidArgument(function: name))
        case .abs:
            try expectCount(1)
            if case .integer(let v) = values[0] {
                guard v != .min else { throw RuntimeError(.overflow) }
                return .integer(Swift.abs(v))
            }
            return .real(Swift.abs(try num(0)))
        case .arccos:
            try expectCount(1)
            let x = try num(0)
            guard (-1...1).contains(x) else { throw RuntimeError(.mathDomain(function: name)) }
            return .real(acos(x))
        case .arcsin:
            try expectCount(1)
            let x = try num(0)
            guard (-1...1).contains(x) else { throw RuntimeError(.mathDomain(function: name)) }
            return .real(asin(x))
        case .arctan:
            try expectCount(1)
            return .real(atan(try num(0)))
        case .cos:
            try expectCount(1)
            return .real(cos(try num(0)))
        case .sin:
            try expectCount(1)
            return .real(sin(try num(0)))
        case .tan:
            try expectCount(1)
            return try real(tan(try num(0)))
        case .int:
            try expectCount(1)
            if case .integer = values[0] { return values[0] }
            let x = try num(0).rounded(.towardZero)
            guard let v = Int64(exactly: x) else { throw RuntimeError(.overflow) }
            return .integer(v)
        case .ln, .log:
            try expectCount(1)
            let x = try num(0)
            guard x > 0 else { throw RuntimeError(.mathDomain(function: name)) }
            return .real(Foundation.log(x))
        case .log10:
            try expectCount(1)
            let x = try num(0)
            guard x > 0 else { throw RuntimeError(.mathDomain(function: name)) }
            return .real(Foundation.log10(x))
        case .sgn:
            try expectCount(1)
            let x = try num(0)
            return .integer(x > 0 ? 1 : x < 0 ? -1 : 0)
        case .sqrt:
            try expectCount(1)
            let x = try num(0)
            guard x >= 0 else { throw RuntimeError(.mathDomain(function: name)) }
            return .real(x.squareRoot())
        case .random:
            try expectCount(1)
            let n = try integer(values[0], context: name)
            guard n > 0 else { throw RuntimeError(.invalidArgument(function: name)) }
            return .integer(Int64.random(in: 0..<n))
        case .len:
            try expectCount(1)
            return .integer(Int64(try str(0).count))
        case .char:
            try expectCount(2)
            let s = try str(0)
            let i = try integer(values[1], context: name)
            guard i >= 0, i < s.count else { throw RuntimeError(.indexOutOfBounds(name: "Char", index: i, size: s.count)) }
            return .string(String(s[s.index(s.startIndex, offsetBy: Int(i))]))
        case .tochar:
            try expectCount(1)
            let code = try integer(values[0], context: name)
            guard let scalar = UInt32(exactly: code).flatMap(Unicode.Scalar.init) else {
                throw RuntimeError(.invalidArgument(function: name))
            }
            return .string(String(Character(scalar)))
        case .tocode:
            try expectCount(1)
            guard let scalar = try str(0).unicodeScalars.first else { throw RuntimeError(.invalidArgument(function: name)) }
            return .integer(Int64(scalar.value))
        case .tofixed:
            try expectCount(2)
            let x = try num(0)
            let digits = try integer(values[1], context: name)
            guard (0...20).contains(digits) else { throw RuntimeError(.invalidArgument(function: name)) }
            return .string(String(format: "%.\(digits)f", x))
        case .tointeger:
            try expectCount(1)
            switch values[0] {
            case .integer: return values[0]
            case .real(let v):
                guard let i = Int64(exactly: v.rounded(.towardZero)) else { throw RuntimeError(.overflow) }
                return .integer(i)
            case .string(let s):
                guard let v = Interpreter.parseInput(s, as: .integer) else {
                    throw RuntimeError(.invalidConversion(value: s, to: .integer))
                }
                return v
            case .boolean(let b):
                return .integer(b ? 1 : 0)
            }
        case .toreal:
            try expectCount(1)
            switch values[0] {
            case .integer(let v): return .real(Double(v))
            case .real: return values[0]
            case .string(let s):
                guard let v = Interpreter.parseInput(s, as: .real) else {
                    throw RuntimeError(.invalidConversion(value: s, to: .real))
                }
                return v
            case .boolean(let b):
                return .real(b ? 1 : 0)
            }
        case .tostring:
            try expectCount(1)
            return .string(values[0].displayString)
        }
    }
}
