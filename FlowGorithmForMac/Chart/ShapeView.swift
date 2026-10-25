import FlowCore
import SwiftUI

enum NodeHighlight: Equatable {
    case none, selected, executing, error
}

/// One flowchart shape: outline, fill, detail lines and its label.
struct ShapeView: View {
    let node: ChartNode
    let theme: Theme
    let fontSize: CGFloat
    let scale: CGFloat
    var highlight: NodeHighlight = .none

    var palette: ShapePalette {
        node.incomplete ? theme.incomplete : theme.palette(for: node.category)
    }

    var body: some View {
        let outline = NodeOutline(shape: node.shape)
        let width = theme.lineWidth * scale
        ZStack {
            outline
                .fill(LinearGradient(colors: [palette.fill, palette.fillEnd], startPoint: .top, endPoint: .bottom))
            outline
                .stroke(palette.stroke, style: StrokeStyle(lineWidth: width, lineJoin: .round,
                                                           dash: node.shape == .comment ? [4 * scale, 3 * scale] : []))
            NodeDetail(shape: node.shape)
                .stroke(palette.stroke, lineWidth: width * 0.8)
            if node.shape != .breakpoint {
                Text(node.label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(textInsets(for: node.shape, height: node.frame.height))
                    .padding(.horizontal, 6 * scale)
            }
        }
        .frame(width: node.frame.width, height: node.frame.height)
        .shadow(color: theme.shadow ? palette.stroke.opacity(theme.id == "neon" ? 0.7 : 0.25) : .clear,
                radius: theme.id == "neon" ? 6 * scale : 3 * scale, y: theme.id == "neon" ? 0 : 1.5 * scale)
        .overlay(alignment: .leading) {
            if node.shape == .breakpoint {
                Text(node.label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(theme.label)
                    .fixedSize()
                    .offset(x: node.frame.width + 8 * scale)
            }
        }
        .overlay { highlightRing(outline) }
        .contentShape(outline)
    }

    @ViewBuilder
    func highlightRing(_ outline: NodeOutline) -> some View {
        switch highlight {
        case .none:
            EmptyView()
        case .selected:
            outline
                .stroke(Color.accentColor, lineWidth: 2.5 * scale)
                .padding(-3 * scale)
        case .executing:
            ExecutingRing(outline: outline, scale: scale)
        case .error:
            outline
                .stroke(Color.red, lineWidth: 3 * scale)
                .padding(-3 * scale)
                .shadow(color: .red.opacity(0.6), radius: 6 * scale)
        }
    }
}

/// A softly pulsing ring around the shape that is running.
struct ExecutingRing: View {
    let outline: NodeOutline
    let scale: CGFloat

    var body: some View {
        PhaseAnimator([false, true]) { bright in
            ZStack {
                outline
                    .fill(Color.yellow.opacity(bright ? 0.28 : 0.12))
                outline
                    .stroke(Color.yellow, lineWidth: (bright ? 4.5 : 3) * scale)
                    .padding(-5 * scale)
                    .shadow(color: .orange.opacity(bright ? 1 : 0.5), radius: (bright ? 14 : 6) * scale)
            }
            .scaleEffect(bright ? 1.04 : 1)
        } animation: { _ in .easeInOut(duration: 0.6) }
    }
}

/// Connectors, merge dots and branch labels, drawn in one Canvas.
struct ChartLines: View {
    let layout: ChartLayout
    let theme: Theme
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        Canvas { context, _ in
            let width = theme.lineWidth * scale
            let arrowLength = 8 * scale
            let arrowWidth = 4.5 * scale
            for edge in layout.edges {
                guard edge.points.count >= 2 else { continue }
                var path = Path()
                path.move(to: edge.points[0])
                for point in edge.points.dropFirst() { path.addLine(to: point) }
                if edge.arrow {
                    let end = edge.points[edge.points.count - 1]
                    let before = edge.points[edge.points.count - 2]
                    let angle = atan2(end.y - before.y, end.x - before.x)
                    let base = CGPoint(x: end.x - cos(angle) * arrowLength, y: end.y - sin(angle) * arrowLength)
                    // Stop the line at the arrow's base so the tip stays sharp.
                    var shortened = Path()
                    shortened.move(to: edge.points[0])
                    for point in edge.points.dropFirst().dropLast() { shortened.addLine(to: point) }
                    shortened.addLine(to: base)
                    context.stroke(shortened, with: .color(theme.line), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    var head = Path()
                    head.move(to: end)
                    head.addLine(to: CGPoint(x: base.x + sin(angle) * arrowWidth, y: base.y - cos(angle) * arrowWidth))
                    head.addLine(to: CGPoint(x: base.x - sin(angle) * arrowWidth, y: base.y + cos(angle) * arrowWidth))
                    head.closeSubpath()
                    context.fill(head, with: .color(theme.line))
                } else if edge.dashed {
                    context.stroke(path, with: .color(theme.label), style: StrokeStyle(lineWidth: width, dash: [3 * scale, 3 * scale]))
                } else {
                    context.stroke(path, with: .color(theme.line), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
            let radius = 5 * scale
            for dot in layout.dots {
                let rect = CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(theme.canvas))
                context.stroke(Path(ellipseIn: rect), with: .color(theme.line), lineWidth: width)
            }
            for text in layout.texts {
                let resolved = context.resolve(Text(text.text).font(.system(size: fontSize * 0.85, weight: .medium)).foregroundStyle(theme.label))
                context.draw(resolved, at: text.position, anchor: text.anchor)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A light dot grid behind the chart.
struct ChartGrid: View {
    let theme: Theme
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = max(12, 22 * scale)
            let radius = max(0.6, 1 * scale)
            var path = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(path, with: .color(theme.grid))
        }
        .allowsHitTesting(false)
    }
}
