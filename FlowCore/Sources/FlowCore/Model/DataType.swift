import Foundation

/// The four data types of the flowchart language.
public enum DataType: String, CaseIterable, Sendable, Hashable, Codable {
    case integer = "Integer"
    case real = "Real"
    case string = "String"
    case boolean = "Boolean"

    /// Parses the `type` attribute used in `.fprg` files (case-insensitive).
    public init?(fprg: String) {
        switch fprg.lowercased() {
        case "integer": self = .integer
        case "real": self = .real
        case "string": self = .string
        case "boolean": self = .boolean
        default: return nil
        }
    }

    public var isNumeric: Bool { self == .integer || self == .real }
}

public enum FileMode: String, CaseIterable, Sendable, Hashable {
    case read
    case write
    case append
}

public enum TurnDirection: String, CaseIterable, Sendable, Hashable {
    case left
    case right
}

public enum ForDirection: String, CaseIterable, Sendable, Hashable {
    case increasing = "inc"
    case decreasing = "dec"
}

/// The ten pen colors supported by turtle graphics.
public enum PenColor: String, CaseIterable, Sendable, Hashable {
    case black, gray, red, orange, yellow, green, teal, blue, purple, brown

    /// sRGB components in 0...1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .black: (0.10, 0.10, 0.12)
        case .gray: (0.50, 0.50, 0.53)
        case .red: (0.86, 0.16, 0.20)
        case .orange: (0.96, 0.49, 0.13)
        case .yellow: (0.96, 0.76, 0.10)
        case .green: (0.18, 0.66, 0.36)
        case .teal: (0.10, 0.65, 0.70)
        case .blue: (0.16, 0.42, 0.88)
        case .purple: (0.55, 0.30, 0.78)
        case .brown: (0.55, 0.35, 0.20)
        }
    }
}
