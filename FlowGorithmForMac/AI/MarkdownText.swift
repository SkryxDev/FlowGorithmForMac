// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import SwiftUI

/// A reply with the Markdown models write: paragraphs, bulleted and numbered lists, headings and
/// code blocks, with **bold**, *italics* and `code` inside them. Code is set in a monospaced font.
struct MarkdownText: View {
    let text: String

    enum Block: Hashable {
        case paragraph(String)
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    func view(_ block: Block) -> some View {
        switch block {
        case .paragraph(let line):
            Text(MarkdownText.inline(line))
        case .heading(let line):
            Text(MarkdownText.inline(line)).font(.callout.weight(.semibold))
        case .bullet(let line):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "•").foregroundStyle(.secondary)
                Text(MarkdownText.inline(line))
            }
        case .numbered(let number, let line):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: number).foregroundStyle(.secondary).monospacedDigit()
                Text(MarkdownText.inline(line))
            }
        case .code(let code):
            Text(verbatim: code)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Inline Markdown only: bold, italics, `code` and links.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// Splits a reply into blocks. Lines of a paragraph are joined; a blank line ends it.
    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func endParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    endParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                endParagraph()
            } else if line.hasPrefix("#") {
                endParagraph()
                blocks.append(.heading(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if let rest = ["- ", "* ", "• "].lazy.compactMap({ line.hasPrefix($0) ? String(line.dropFirst(2)) : nil }).first {
                endParagraph()
                blocks.append(.bullet(rest))
            } else if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
                      line[..<dot].count <= 3, !line[..<dot].isEmpty, line[..<dot].allSatisfy(\.isNumber),
                      line[line.index(after: dot)...].hasPrefix(" ") {
                endParagraph()
                blocks.append(.numbered(String(line[...dot]), String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        endParagraph()
        return blocks
    }
}
