// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

public enum Value: Hashable, Sendable {
    case integer(Int64)
    case real(Double)
    case string(String)
    case boolean(Bool)

    public var type: DataType {
        switch self {
        case .integer: .integer
        case .real: .real
        case .string: .string
        case .boolean: .boolean
        }
    }

    /// How the value is shown in the console and the variable watch.
    public var displayString: String {
        switch self {
        case .integer(let v): String(v)
        case .real(let v): Value.format(v)
        case .string(let v): v
        case .boolean(let v): v ? "true" : "false"
        }
    }

    var numeric: Double? {
        switch self {
        case .integer(let v): Double(v)
        case .real(let v): v
        default: nil
        }
    }

    /// Formats a real like .NET's default `Double.ToString()`: up to 15 significant digits,
    /// no trailing zeros, so 0.1 + 0.2 shows as 0.3 and 10 / 2 as 5.
    public static func format(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value > 0 ? "Infinity" : "-Infinity" }
        if value == 0 { return "0" }
        var text = String(format: "%.15G", value)
        if text.contains("E") {
            // %G gives "1E+20"; trim zero padding in the exponent ("1E+05" -> "1E+05" is fine, .NET also pads to 2).
            return text
        }
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
