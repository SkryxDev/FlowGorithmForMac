// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import AppKit
import FlowCore
import SwiftUI

extension Color {
    /// A color that switches with the system appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

struct ShapePalette {
    var fill: Color
    var fillEnd: Color
    var stroke: Color
    var text: Color
    /// Only some themes use gradients; a flat color is cheaper to draw.
    let isGradient: Bool

    init(fill: Color, fillEnd: Color? = nil, stroke: Color, text: Color) {
        self.fill = fill
        self.fillEnd = fillEnd ?? fill
        self.stroke = stroke
        self.text = text
        isGradient = fillEnd != nil && fillEnd != fill
    }

    var fillStyle: AnyShapeStyle {
        isGradient
            ? AnyShapeStyle(LinearGradient(colors: [fill, fillEnd], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(fill)
    }
}

/// A color scheme for the flowchart. Every color adapts to light and dark mode.
struct Theme: Identifiable {
    var id: String
    var name: LocalizedStringResource
    var canvas: Color
    var grid: Color
    var line: Color
    var label: Color
    var lineWidth: CGFloat
    var shadow: Bool
    var palettes: [ShapeCategory: ShapePalette]
    var incomplete: ShapePalette

    func palette(for category: ShapeCategory) -> ShapePalette {
        palettes[category] ?? incomplete
    }

    static let all: [Theme] = [.classic, .modern, .pastel, .neon, .print]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .classic
    }

    private static func p(_ light: (UInt32, UInt32), _ dark: (UInt32, UInt32), text: (UInt32, UInt32) = (0x1D1D1F, 0xF5F5F7)) -> ShapePalette {
        ShapePalette(fill: Color(light: light.0, dark: dark.0),
                     stroke: Color(light: light.1, dark: dark.1),
                     text: Color(light: text.0, dark: text.1))
    }

    /// Close to the colors students know from Flowgorithm.
    static let classic = Theme(
        id: "classic",
        name: "Classic",
        canvas: Color(light: 0xFFFFFF, dark: 0x1C1C1E),
        grid: Color(light: 0xEDEDF0, dark: 0x2A2A2E),
        line: Color(light: 0x3A3A3C, dark: 0xC7C7CC),
        label: Color(light: 0x6E6E73, dark: 0x98989D),
        lineWidth: 1.4,
        shadow: false,
        palettes: [
            .terminal: p((0xEBDDF7, 0x9B6FC9), (0x3B2A4D, 0xC49BEB)),
            .input: p((0xCFE3F8, 0x4A86C5), (0x1E3A57, 0x7DB5EE)),
            .output: p((0xD4F3D4, 0x4CA64C), (0x1F4021, 0x7ED67E)),
            .declare: p((0xFFF8C9, 0xC2AC4A), (0x45401E, 0xE6D27A)),
            .assign: p((0xFFF8C9, 0xC2AC4A), (0x45401E, 0xE6D27A)),
            .selection: p((0xF8D4D4, 0xC85A5A), (0x4D2626, 0xF08A8A)),
            .loop: p((0xFFE1C4, 0xD98C3F), (0x4D3218, 0xF5AE69)),
            .call: p((0xE6D7F7, 0x9466C2), (0x382A4D, 0xC29BEB)),
            .comment: p((0xFFFFFF, 0x9A9AA0), (0x2C2C2E, 0x8E8E93)),
            .breakpoint: p((0xF27272, 0xC23B3B), (0xC24848, 0xF27272)),
            .file: p((0xFFF5CC, 0xC4A94F), (0x423A1C, 0xE3CB75)),
            .turtle: p((0xE2F5D9, 0x6FA857), (0x26401C, 0x9AD383)),
            .unknown: p((0xE5E5EA, 0x8E8E93), (0x3A3A3C, 0x8E8E93)),
        ],
        incomplete: p((0xE5E5EA, 0x8E8E93), (0x3A3A3C, 0x8E8E93), text: (0x3A3A3C, 0xD1D1D6))
    )

    private static func g(_ from: UInt32, _ to: UInt32, _ stroke: UInt32) -> ShapePalette {
        ShapePalette(fill: Color(hex: from), fillEnd: Color(hex: to), stroke: Color(hex: stroke), text: .white)
    }

    /// Saturated gradients with white text.
    static let modern = Theme(
        id: "modern",
        name: "Modern",
        canvas: Color(light: 0xF6F7FB, dark: 0x16171C),
        grid: Color(light: 0xE6E8F0, dark: 0x22242C),
        line: Color(light: 0x5B6170, dark: 0x9EA4B5),
        label: Color(light: 0x7A8090, dark: 0x8A90A0),
        lineWidth: 1.6,
        shadow: true,
        palettes: [
            .terminal: g(0x8E6CF0, 0x6A47D9, 0x5B3BC4),
            .input: g(0x4FA3F7, 0x2F7BE0, 0x2468C4),
            .output: g(0x3CCB7F, 0x22A762, 0x1C8F53),
            .declare: g(0xF7B731, 0xE69A12, 0xC9850D),
            .assign: g(0xF5A524, 0xE58A0E, 0xC5760B),
            .selection: g(0xF0566A, 0xD9364D, 0xBD2A40),
            .loop: g(0xFF8A3D, 0xF06A1E, 0xD45A16),
            .call: g(0xB36CF0, 0x9347D9, 0x7F3BC4),
            .comment: ShapePalette(fill: Color(light: 0xFFFFFF, dark: 0x262830), stroke: Color(hex: 0x9EA4B5),
                                   text: Color(light: 0x4A4F5C, dark: 0xC5C9D6)),
            .breakpoint: g(0xFF5A5F, 0xE0353B, 0xC22A30),
            .file: g(0x2EC4C4, 0x18A3A8, 0x138A8F),
            .turtle: g(0x6BCB4B, 0x4CAF32, 0x3E962A),
            .unknown: g(0x9EA4B5, 0x7D8396, 0x6A7080),
        ],
        incomplete: ShapePalette(fill: Color(light: 0xE4E6EE, dark: 0x30333D), stroke: Color(hex: 0x9EA4B5),
                                 text: Color(light: 0x5B6170, dark: 0xC5C9D6))
    )

    static let pastel = Theme(
        id: "pastel",
        name: "Pastel",
        canvas: Color(light: 0xFFFDF8, dark: 0x1E1D1B),
        grid: Color(light: 0xF2EEE4, dark: 0x2B2926),
        line: Color(light: 0x857F74, dark: 0xB0A99C),
        label: Color(light: 0x9A9488, dark: 0x9A9488),
        lineWidth: 1.3,
        shadow: false,
        palettes: [
            .terminal: p((0xF1E4FF, 0xC3A6E6), (0x3D3347, 0xC3A6E6), text: (0x4D3F5C, 0xEDE1FA)),
            .input: p((0xE0F0FF, 0x9CC5EB), (0x2C3A47, 0x9CC5EB), text: (0x2F4A63, 0xDDEBF8)),
            .output: p((0xE2F7E6, 0x9BD3A6), (0x2C4031, 0x9BD3A6), text: (0x2F5236, 0xDDF4E1)),
            .declare: p((0xFFF7DE, 0xE3CF8F), (0x47412F, 0xE3CF8F), text: (0x5C4F23, 0xF7EED2)),
            .assign: p((0xFFF7DE, 0xE3CF8F), (0x47412F, 0xE3CF8F), text: (0x5C4F23, 0xF7EED2)),
            .selection: p((0xFFE4E6, 0xE8A3A9), (0x472F31, 0xE8A3A9), text: (0x63323A, 0xF8DDE0)),
            .loop: p((0xFFEBDC, 0xEDB78E), (0x47372B, 0xEDB78E), text: (0x5C3A20, 0xF8E5D6)),
            .call: p((0xEFE6FF, 0xB9A3E3), (0x3A3347, 0xB9A3E3), text: (0x43365C, 0xE9E0FA)),
            .comment: p((0xFFFFFF, 0xC9C3B6), (0x2B2926, 0x8C867A), text: (0x5C574D, 0xD6D0C4)),
            .breakpoint: p((0xF5A3A3, 0xD97070), (0x8C4646, 0xF5A3A3), text: (0x5C2020, 0xFFFFFF)),
            .file: p((0xE6F7F5, 0x95D1CA), (0x2C4442, 0x95D1CA), text: (0x24524C, 0xD9F2EF)),
            .turtle: p((0xEEF7DC, 0xB5D38A), (0x3A4429, 0xB5D38A), text: (0x41541F, 0xEBF4DA)),
            .unknown: p((0xEEEEEE, 0xBBBBBB), (0x3A3A3A, 0x888888)),
        ],
        incomplete: p((0xF0EEEA, 0xC9C3B6), (0x34322E, 0x8C867A), text: (0x857F74, 0xB0A99C))
    )

    private static func n(_ color: UInt32) -> ShapePalette {
        ShapePalette(fill: Color(hex: color, alpha: 0.14), stroke: Color(hex: color), text: Color(hex: 0xF2F4FF))
    }

    /// Always dark, with glowing outlines.
    static let neon = Theme(
        id: "neon",
        name: "Neon",
        canvas: Color(hex: 0x0D0F1A),
        grid: Color(hex: 0x171A2B),
        line: Color(hex: 0x7C86B8),
        label: Color(hex: 0x7C86B8),
        lineWidth: 1.6,
        shadow: true,
        palettes: [
            .terminal: n(0xB388FF),
            .input: n(0x40C4FF),
            .output: n(0x69F0AE),
            .declare: n(0xFFE57F),
            .assign: n(0xFFD740),
            .selection: n(0xFF5C8A),
            .loop: n(0xFF9E40),
            .call: n(0xEA80FC),
            .comment: n(0x8C93B8),
            .breakpoint: n(0xFF5252),
            .file: n(0x64FFDA),
            .turtle: n(0xB2FF59),
            .unknown: n(0x8C93B8),
        ],
        incomplete: n(0x5C6488)
    )

    /// Black and white, for printing and exporting to documents.
    static let print = Theme(
        id: "print",
        name: "Black & White",
        canvas: .white,
        grid: Color(hex: 0xF2F2F2),
        line: .black,
        label: Color(hex: 0x444444),
        lineWidth: 1.2,
        shadow: false,
        palettes: Dictionary(uniqueKeysWithValues: ShapeCategory.allCases.map {
            ($0, ShapePalette(fill: .white, stroke: .black, text: .black))
        }),
        incomplete: ShapePalette(fill: Color(hex: 0xF2F2F2), stroke: Color(hex: 0x777777), text: Color(hex: 0x555555))
    )
}

extension DataType {
    /// Colors used for values in the variable watch and console, as in Flowgorithm.
    var color: Color {
        switch self {
        case .integer: Color(light: 0x2468C4, dark: 0x6FAAF5)
        case .real: Color(light: 0x8A3FC4, dark: 0xC08AF0)
        case .string: Color(light: 0xC2382E, dark: 0xF07A70)
        case .boolean: Color(light: 0x13878F, dark: 0x4FD1D9)
        }
    }
}

extension PenColor {
    var color: Color {
        let c = rgb
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}
