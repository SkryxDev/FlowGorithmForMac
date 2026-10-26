// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import SwiftUI

/// The outline of each kind of shape, drawn inside its frame.
struct NodeOutline: Shape {
    var shape: NodeShape

    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        let h = r.height
        switch shape {
        case .terminal:
            p.addRoundedRect(in: r, cornerSize: CGSize(width: h / 2, height: h / 2))

        case .assign, .comment, .unknown:
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))

        case .declare:
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 3, height: 3))

        case .call:
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 3, height: 3))

        case .input, .output:
            let skew = h * 0.3
            p.move(to: CGPoint(x: r.minX + skew, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - skew, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()

        case .decision:
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()

        case .loop:
            let tip = h * 0.3
            p.move(to: CGPoint(x: r.minX + tip, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + tip, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()

        case .turtleTurn:
            // A double arrow: points on both sides.
            let tip = h * 0.32
            let inset = h * 0.18
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX + tip, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + tip, y: r.minY + inset))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.minY + inset))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.maxY - inset))
            p.addLine(to: CGPoint(x: r.minX + tip, y: r.maxY - inset))
            p.addLine(to: CGPoint(x: r.minX + tip, y: r.maxY))
            p.closeSubpath()

        case .breakpoint:
            let c = r.width * 0.29
            p.move(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
            p.closeSubpath()

        case .fileOpen, .fileClose:
            // A sheet of paper with a folded corner.
            let fold = h * 0.35
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()

        case .fileRead, .fileWrite:
            // Rounded on the left like a stored-data symbol.
            let curve = h * 0.3
            p.move(to: CGPoint(x: r.minX + curve, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX - curve * 1.6, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX + curve, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.minX + curve, y: r.minY), control: CGPoint(x: r.minX - curve * 0.6, y: r.midY))
            p.closeSubpath()

        case .turtleForward, .turtlePen:
            // An arrow tag pointing right.
            let tip = h * 0.35
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - tip, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            if shape == .turtleForward {
                p.addLine(to: CGPoint(x: r.minX + tip * 0.7, y: r.midY))
            }
            p.closeSubpath()

        case .turtleHome:
            // A house: a pointed roof over a box.
            let roof = h * 0.28
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + roof))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + roof))
            p.closeSubpath()

        case .turtleClear:
            let curve = h * 0.3
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - curve, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX - curve, y: r.maxY), control: CGPoint(x: r.maxX + curve * 0.6, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
        return p
    }
}

/// Extra inner lines some shapes carry (declare's corner lines, call's side bars).
struct NodeDetail: Shape {
    var shape: NodeShape

    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        switch shape {
        case .declare:
            let inset: CGFloat = 6
            p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY))
            p.move(to: CGPoint(x: r.minX, y: r.minY + inset))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + inset))
        case .call:
            let inset: CGFloat = 7
            p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX - inset, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
        case .fileOpen, .fileClose:
            let fold = r.height * 0.35
            p.move(to: CGPoint(x: r.maxX - fold, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY + fold))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        case .turtlePen:
            let tip = r.height * 0.35
            p.move(to: CGPoint(x: r.minX + 6, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + 6, y: r.maxY))
            _ = tip
        default:
            break
        }
        return p
    }
}

/// The text box inside a shape, inset so text stays clear of slanted edges.
func textInsets(for shape: NodeShape, height h: CGFloat) -> EdgeInsets {
    switch shape {
    case .input, .output, .loop: EdgeInsets(top: 0, leading: h * 0.3, bottom: 0, trailing: h * 0.3)
    case .decision: EdgeInsets(top: 0, leading: h * 0.5, bottom: 0, trailing: h * 0.5)
    case .declare: EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 2)
    case .call: EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
    case .turtleTurn: EdgeInsets(top: 0, leading: h * 0.3, bottom: 0, trailing: h * 0.3)
    case .turtleForward, .turtlePen, .fileOpen, .fileClose: EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: h * 0.3)
    case .turtleHome: EdgeInsets(top: h * 0.2, leading: 0, bottom: 0, trailing: 0)
    case .fileRead, .fileWrite: EdgeInsets(top: 0, leading: h * 0.25, bottom: 0, trailing: h * 0.2)
    default: EdgeInsets()
    }
}
