// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import AppKit
import FlowCore
import SwiftUI

nonisolated enum NodeShape: Hashable {
    case terminal, declare, assign, input, output, decision, loop, call, comment, breakpoint
    case fileOpen, fileClose, fileRead, fileWrite
    case turtleForward, turtleTurn, turtleHome, turtleClear, turtlePen, unknown
}

struct ChartNode: Identifiable {
    enum Role: Hashable {
        case start, end, statement
    }

    var id: String
    var role: Role
    var statement: Statement?
    var shape: NodeShape
    var category: ShapeCategory
    var label: String
    var frame: CGRect
    var incomplete: Bool
    /// Why the shape can't run as written, shown as its tooltip.
    var problem: String? = nil
}

struct ChartEdge: Hashable {
    var points: [CGPoint]
    var arrow: Bool
    var dashed = false
}

struct ChartText: Hashable {
    var text: String
    var position: CGPoint
    var anchor: UnitPoint
}

struct ChartInsert: Identifiable, Hashable {
    var point: InsertionPoint
    var position: CGPoint
    var id: String { "\(point.block.owner?.uuidString ?? "body")-\(point.block.branch)-\(point.index)" }
}

/// Sizes used to lay out a chart. Derived from the font size so zooming text keeps proportions.
struct ChartMetrics {
    var fontSize: CGFloat
    var compact: Bool

    var font: NSFont { .systemFont(ofSize: fontSize, weight: .medium) }
    var gap: CGFloat { (compact ? 20 : 26) * fontSize / 13 }
    var minWidth: CGFloat { 96 * fontSize / 13 }
    var shapeHeight: CGFloat { 34 * fontSize / 13 }
    var horizontalPadding: CGFloat { 16 * fontSize / 13 }
    var branchGap: CGFloat { (compact ? 26 : 36) * fontSize / 13 }
    var maxTextWidth: CGFloat { 300 * fontSize / 13 }
    var dotRadius: CGFloat { 5 * fontSize / 13 }
    var margin: CGFloat { 40 }

    /// Measuring text is the slowest part of a layout; labels repeat, so sizes are remembered.
    private static var measured: [String: CGSize] = [:]

    func measure(_ text: String) -> CGSize {
        let key = "\(fontSize)|\(text)"
        if let size = Self.measured[key] { return size }
        if Self.measured.count > 4000 { Self.measured.removeAll(keepingCapacity: true) }
        let size = rawMeasure(text)
        Self.measured[key] = size
        return size
    }

    private func rawMeasure(_ text: String) -> CGSize {
        let string = text.isEmpty ? " " : text
        let rect = (string as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
}

/// The geometry of one function's flowchart: shapes, connectors, labels and insertion points.
struct ChartLayout {
    /// Changes whenever the layout is rebuilt, so views can skip redrawing an unchanged chart.
    var revision = 0
    var nodes: [ChartNode] = []
    var edges: [ChartEdge] = []
    var texts: [ChartText] = []
    var inserts: [ChartInsert] = []
    var dots: [CGPoint] = []
    var size: CGSize = .zero

    static func make(_ function: Function, metrics: ChartMetrics) -> ChartLayout {
        let builder = Builder(metrics: metrics)
        var fragment = Fragment()

        let startLabel = ShapeText.functionHeader(function)
        let startSize = builder.terminalSize(startLabel)
        fragment.nodes.append(ChartNode(id: "start", role: .start, statement: nil, shape: .terminal, category: .terminal,
                                        label: startLabel, frame: CGRect(x: -startSize.width / 2, y: 0, width: startSize.width, height: startSize.height),
                                        incomplete: false))
        fragment.include(left: startSize.width / 2, right: startSize.width / 2)

        let body = builder.block(function.body, reference: .functionBody, arrowAtEnd: true)
        fragment.merge(body, dx: 0, dy: startSize.height)

        let endLabel = ShapeText.functionFooter(function)
        let endSize = builder.terminalSize(endLabel)
        let endY = startSize.height + body.height
        fragment.nodes.append(ChartNode(id: "end", role: .end, statement: nil, shape: .terminal, category: .terminal,
                                        label: endLabel, frame: CGRect(x: -endSize.width / 2, y: endY, width: endSize.width, height: endSize.height),
                                        incomplete: false))
        fragment.include(left: endSize.width / 2, right: endSize.width / 2)
        fragment.height = endY + endSize.height

        let margin = metrics.margin
        var layout = ChartLayout()
        let dx = margin + fragment.left
        let dy = margin
        layout.nodes = fragment.nodes.map { var n = $0; n.frame = n.frame.offsetBy(dx: dx, dy: dy); return n }
        layout.edges = fragment.edges.map { ChartEdge(points: $0.points.map { $0.offset(dx, dy) }, arrow: $0.arrow, dashed: $0.dashed) }
        layout.texts = fragment.texts.map { ChartText(text: $0.text, position: $0.position.offset(dx, dy), anchor: $0.anchor) }
        layout.inserts = fragment.inserts.map { ChartInsert(point: $0.point, position: $0.position.offset(dx, dy)) }
        layout.dots = fragment.dots.map { $0.offset(dx, dy) }
        layout.size = CGSize(width: fragment.left + fragment.right + margin * 2, height: fragment.height + margin * 2)
        return layout
    }

    /// A piece of chart in local coordinates: the flow axis is x = 0 and the top is y = 0.
    struct Fragment {
        var left: CGFloat = 0
        var right: CGFloat = 0
        var height: CGFloat = 0
        var nodes: [ChartNode] = []
        var edges: [ChartEdge] = []
        var texts: [ChartText] = []
        var inserts: [ChartInsert] = []
        var dots: [CGPoint] = []

        mutating func include(left: CGFloat, right: CGFloat) {
            self.left = max(self.left, left)
            self.right = max(self.right, right)
        }

        mutating func merge(_ other: Fragment, dx: CGFloat, dy: CGFloat) {
            nodes += other.nodes.map { var n = $0; n.frame = n.frame.offsetBy(dx: dx, dy: dy); return n }
            edges += other.edges.map { ChartEdge(points: $0.points.map { $0.offset(dx, dy) }, arrow: $0.arrow, dashed: $0.dashed) }
            texts += other.texts.map { ChartText(text: $0.text, position: $0.position.offset(dx, dy), anchor: $0.anchor) }
            inserts += other.inserts.map { ChartInsert(point: $0.point, position: $0.position.offset(dx, dy)) }
            dots += other.dots.map { $0.offset(dx, dy) }
            include(left: other.left - dx, right: other.right + dx)
        }

        mutating func line(_ points: CGPoint..., arrow: Bool = false) {
            edges.append(ChartEdge(points: points, arrow: arrow))
        }
    }

    struct Builder {
        var metrics: ChartMetrics

        func terminalSize(_ label: String) -> CGSize {
            let text = metrics.measure(label)
            let height = max(metrics.shapeHeight, text.height + 14)
            return CGSize(width: max(metrics.minWidth, text.width + height), height: height)
        }

        func block(_ statements: [Statement], reference: BlockReference, arrowAtEnd: Bool) -> Fragment {
            var fragment = Fragment()
            let gap = metrics.gap
            var y: CGFloat = 0
            for (index, statement) in statements.enumerated() {
                // Comments sit beside the line, so nothing for an arrow to point at.
                fragment.line(CGPoint(x: 0, y: y), CGPoint(x: 0, y: y + gap), arrow: statement.category != .comment)
                fragment.inserts.append(ChartInsert(point: InsertionPoint(block: reference, index: index), position: CGPoint(x: 0, y: y + gap / 2)))
                y += gap
                let piece = layout(statement)
                fragment.merge(piece, dx: 0, dy: y)
                y += piece.height
            }
            fragment.line(CGPoint(x: 0, y: y), CGPoint(x: 0, y: y + gap), arrow: arrowAtEnd)
            fragment.inserts.append(ChartInsert(point: InsertionPoint(block: reference, index: statements.count), position: CGPoint(x: 0, y: y + gap / 2)))
            fragment.height = y + gap
            fragment.include(left: 12, right: 12)
            return fragment
        }

        func shape(of statement: Statement) -> NodeShape {
            switch statement.kind {
            case .declare: .declare
            case .assign: .assign
            case .input: .input
            case .output: .output
            case .if: .decision
            case .while, .for, .do: .loop
            case .call: .call
            case .comment: .comment
            case .breakpoint: .breakpoint
            case .open: .fileOpen
            case .close: .fileClose
            case .read: .fileRead
            case .write: .fileWrite
            case .forward: .turtleForward
            case .turn: .turtleTurn
            case .home: .turtleHome
            case .clear: .turtleClear
            case .pen: .turtlePen
            case .unknown: .unknown
            }
        }

        func node(_ statement: Statement, size: CGSize, y: CGFloat = 0) -> ChartNode {
            ChartNode(id: statement.id.uuidString, role: .statement, statement: statement, shape: shape(of: statement),
                      category: statement.category, label: ShapeText.label(statement),
                      frame: CGRect(x: -size.width / 2, y: y, width: size.width, height: size.height),
                      incomplete: statement.isIncomplete,
                      problem: statement.validationError.map(ErrorText.message))
        }

        func size(for statement: Statement) -> CGSize {
            let label = ShapeText.label(statement)
            let text = metrics.measure(label)
            let pad = metrics.horizontalPadding
            let height = max(metrics.shapeHeight, text.height + 16)
            switch shape(of: statement) {
            case .decision:
                let h = max(metrics.shapeHeight * 1.3, text.height + 26)
                return CGSize(width: max(metrics.minWidth * 1.15, text.width + h + 20), height: h)
            case .loop, .turtleTurn:
                return CGSize(width: max(metrics.minWidth, text.width + 2 * pad + height * 0.6), height: height)
            case .input, .output, .fileRead, .fileWrite:
                return CGSize(width: max(metrics.minWidth, text.width + 2 * pad + height * 0.6), height: height)
            case .call, .declare:
                return CGSize(width: max(metrics.minWidth, text.width + 2 * pad + 12), height: height)
            case .breakpoint:
                let side = metrics.shapeHeight * 0.75
                return CGSize(width: side, height: side)
            case .turtleForward, .turtlePen, .fileOpen, .fileClose, .turtleHome:
                return CGSize(width: max(metrics.minWidth, text.width + 2 * pad + height * 0.4), height: height + (shape(of: statement) == .turtleHome ? 6 : 0))
            default:
                return CGSize(width: max(metrics.minWidth, text.width + 2 * pad), height: height)
            }
        }

        func layout(_ statement: Statement) -> Fragment {
            var f = Fragment()
            let size = size(for: statement)
            let w = size.width, h = size.height
            let labelOffset = 6 * metrics.fontSize / 13
            let trueText = String(localized: "True")
            let falseText = String(localized: "False")

            switch statement.kind {
            case .if(let s):
                f.nodes.append(node(statement, size: size))
                let elseBlock = block(s.elseBody, reference: BlockReference(owner: statement.id, branch: 1), arrowAtEnd: false)
                let thenBlock = block(s.thenBody, reference: BlockReference(owner: statement.id, branch: 0), arrowAtEnd: false)
                let leftAxis = -max(w / 2, elseBlock.right + metrics.branchGap / 2)
                let rightAxis = max(w / 2, thenBlock.left + metrics.branchGap / 2)
                let branchTop = h / 2
                f.line(CGPoint(x: -w / 2, y: branchTop), CGPoint(x: leftAxis, y: branchTop))
                f.line(CGPoint(x: w / 2, y: branchTop), CGPoint(x: rightAxis, y: branchTop))
                f.merge(elseBlock, dx: leftAxis, dy: branchTop)
                f.merge(thenBlock, dx: rightAxis, dy: branchTop)
                let bottom = branchTop + max(elseBlock.height, thenBlock.height)
                let mergeY = bottom + metrics.dotRadius * 2
                let r = metrics.dotRadius
                f.line(CGPoint(x: leftAxis, y: branchTop + elseBlock.height), CGPoint(x: leftAxis, y: mergeY), CGPoint(x: -r, y: mergeY), arrow: true)
                f.line(CGPoint(x: rightAxis, y: branchTop + thenBlock.height), CGPoint(x: rightAxis, y: mergeY), CGPoint(x: r, y: mergeY), arrow: true)
                f.dots.append(CGPoint(x: 0, y: mergeY))
                f.texts.append(ChartText(text: falseText, position: CGPoint(x: -w / 2 - labelOffset, y: branchTop - labelOffset / 2), anchor: .bottomTrailing))
                f.texts.append(ChartText(text: trueText, position: CGPoint(x: w / 2 + labelOffset, y: branchTop - labelOffset / 2), anchor: .bottomLeading))
                f.height = mergeY + r
                f.include(left: w / 2, right: w / 2)

            case .while(let s):
                f = loopAbove(statement, body: s.body, size: size, enter: trueText, exit: falseText)

            case .for(let s):
                f = loopAbove(statement, body: s.body, size: size,
                              enter: String(localized: "Next"), exit: String(localized: "Done"))

            case .do(let s):
                let r = metrics.dotRadius
                f.dots.append(CGPoint(x: 0, y: r))
                let body = block(s.body, reference: BlockReference(owner: statement.id, branch: 0), arrowAtEnd: false)
                let bodyAxis = max(w / 2 + metrics.branchGap * 0.7, body.left + metrics.branchGap * 0.7)
                f.line(CGPoint(x: r, y: r), CGPoint(x: bodyAxis, y: r))
                f.merge(body, dx: bodyAxis, dy: r)
                let bodyEnd = r + body.height
                let top = bodyEnd + metrics.gap * 0.3
                let middle = top + h / 2
                f.line(CGPoint(x: bodyAxis, y: bodyEnd), CGPoint(x: bodyAxis, y: middle), CGPoint(x: w / 2, y: middle), arrow: true)
                f.nodes.append(node(statement, size: size, y: top))
                f.line(CGPoint(x: 0, y: top), CGPoint(x: 0, y: 2 * r), arrow: true)
                f.texts.append(ChartText(text: trueText, position: CGPoint(x: -labelOffset, y: top - labelOffset), anchor: .bottomTrailing))
                f.texts.append(ChartText(text: falseText, position: CGPoint(x: -labelOffset, y: top + h + labelOffset / 2), anchor: .topTrailing))
                let exitEnd = top + h + metrics.gap * 0.5
                f.line(CGPoint(x: 0, y: top + h), CGPoint(x: 0, y: exitEnd))
                f.height = exitEnd
                f.include(left: w / 2, right: w / 2)

            case .comment:
                // A note beside the flow line, joined to it by a dashed line.
                let offset = metrics.gap * 0.9
                var note = node(statement, size: size)
                note.frame.origin.x = offset
                f.nodes.append(note)
                f.line(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: h))
                f.edges.append(ChartEdge(points: [CGPoint(x: 0, y: h / 2), CGPoint(x: offset, y: h / 2)], arrow: false, dashed: true))
                f.height = h
                f.include(left: 12, right: offset + w)

            case .breakpoint:
                f.nodes.append(node(statement, size: size))
                let text = metrics.measure(ShapeText.label(statement))
                f.height = h
                f.include(left: w / 2, right: w / 2 + 8 + text.width)

            default:
                f.nodes.append(node(statement, size: size))
                f.height = h
                f.include(left: w / 2, right: w / 2)
            }
            return f
        }

        /// While and For: the body runs on the right and flows back into the bottom of the shape.
        func loopAbove(_ statement: Statement, body statements: [Statement], size: CGSize, enter: String, exit: String) -> Fragment {
            var f = Fragment()
            let w = size.width, h = size.height
            let labelOffset = 6 * metrics.fontSize / 13
            f.nodes.append(node(statement, size: size))
            let body = block(statements, reference: BlockReference(owner: statement.id, branch: 0), arrowAtEnd: false)
            let returnX = min(w / 2 - 10, 16 * metrics.fontSize / 13)
            let bodyAxis = max(w / 2 + metrics.branchGap * 0.7, returnX + metrics.branchGap * 0.6 + body.left)
            f.line(CGPoint(x: w / 2, y: h / 2), CGPoint(x: bodyAxis, y: h / 2))
            f.merge(body, dx: bodyAxis, dy: h / 2)
            let bodyEnd = h / 2 + body.height
            let returnY = bodyEnd + metrics.gap * 0.35
            f.line(CGPoint(x: bodyAxis, y: bodyEnd), CGPoint(x: bodyAxis, y: returnY), CGPoint(x: returnX, y: returnY), CGPoint(x: returnX, y: h), arrow: true)
            let exitEnd = returnY + metrics.gap * 0.5
            f.line(CGPoint(x: 0, y: h), CGPoint(x: 0, y: exitEnd))
            f.texts.append(ChartText(text: enter, position: CGPoint(x: w / 2 + labelOffset, y: h / 2 - labelOffset / 2), anchor: .bottomLeading))
            f.texts.append(ChartText(text: exit, position: CGPoint(x: -labelOffset, y: h + labelOffset / 2), anchor: .topTrailing))
            f.height = exitEnd
            f.include(left: w / 2, right: w / 2)
            return f
        }
    }
}

extension CGPoint {
    func offset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}
