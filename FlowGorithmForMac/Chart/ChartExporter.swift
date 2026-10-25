import AppKit
import FlowCore
import SwiftUI
import UniformTypeIdentifiers

/// The chart drawn without any editing decorations, for export and printing.
struct ExportChart: View {
    let layout: ChartLayout
    let theme: Theme
    let fontSize: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.canvas
            ChartLines(layout: layout, theme: theme, fontSize: fontSize, scale: 1)
            ForEach(layout.nodes) { node in
                ShapeView(node: node, theme: theme, fontSize: fontSize, scale: 1)
                    .position(x: node.frame.midX, y: node.frame.midY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .environment(\.colorScheme, .light)
    }
}

enum ChartExporter {
    enum Format {
        case png, pdf, svg

        var type: UTType {
            switch self {
            case .png: .png
            case .pdf: .pdf
            case .svg: .svg
            }
        }
    }

    static func export(_ function: Function, format: Format, theme: Theme, fontSize: Double, compact: Bool, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let metrics = ChartMetrics(fontSize: fontSize, compact: compact)
        let layout = ChartLayout.make(function, metrics: metrics)
        let view = ExportChart(layout: layout, theme: theme, fontSize: fontSize)
        switch format {
        case .png:
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            guard let image = renderer.cgImage else { return }
            let bitmap = NSBitmapImageRep(cgImage: image)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        case .pdf:
            let renderer = ImageRenderer(content: view)
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
                context.closePDF()
            }
        case .svg:
            try? SVGWriter.svg(layout, theme: theme, fontSize: fontSize).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func print(_ function: Function, theme: Theme, fontSize: Double, compact: Bool) {
        let layout = ChartLayout.make(function, metrics: ChartMetrics(fontSize: fontSize, compact: compact))
        let renderer = ImageRenderer(content: ExportChart(layout: layout, theme: theme, fontSize: fontSize))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: layout.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        NSPrintOperation(view: imageView, printInfo: info).run()
    }
}

/// Writes the chart as scalable vector graphics, shape by shape.
enum SVGWriter {
    static func svg(_ layout: ChartLayout, theme: Theme, fontSize: CGFloat) -> String {
        let environment = EnvironmentValues()
        func hex(_ color: Color) -> String {
            let r = color.resolve(in: environment)
            return String(format: "#%02X%02X%02X", Int(r.red * 255), Int(r.green * 255), Int(r.blue * 255))
        }
        func opacity(_ color: Color) -> String { String(format: "%.2f", color.resolve(in: environment).opacity) }
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func data(_ path: Path) -> String {
            var out = ""
            path.forEach { element in
                switch element {
                case .move(let p): out += String(format: "M%.1f %.1f ", p.x, p.y)
                case .line(let p): out += String(format: "L%.1f %.1f ", p.x, p.y)
                case .quadCurve(let p, let c): out += String(format: "Q%.1f %.1f %.1f %.1f ", c.x, c.y, p.x, p.y)
                case .curve(let p, let c1, let c2): out += String(format: "C%.1f %.1f %.1f %.1f %.1f %.1f ", c1.x, c1.y, c2.x, c2.y, p.x, p.y)
                case .closeSubpath: out += "Z "
                }
            }
            return out
        }

        let w = layout.size.width, h = layout.size.height
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(w))\" height=\"\(Int(h))\" viewBox=\"0 0 \(Int(w)) \(Int(h))\" font-family=\"-apple-system, Helvetica, Arial, sans-serif\" font-size=\"\(fontSize)\">\n"
        out += "<rect width=\"100%\" height=\"100%\" fill=\"\(hex(theme.canvas))\"/>\n"
        let line = hex(theme.line)
        for edge in layout.edges where edge.points.count >= 2 {
            let points = edge.points.map { String(format: "%.1f,%.1f", $0.x, $0.y) }.joined(separator: " ")
            let dash = edge.dashed ? " stroke-dasharray=\"3 3\"" : ""
            out += "<polyline points=\"\(points)\" fill=\"none\" stroke=\"\(line)\" stroke-width=\"\(theme.lineWidth)\"\(dash)\(edge.arrow ? " marker-end=\"url(#arrow)\"" : "")/>\n"
        }
        out = out.replacingOccurrences(of: "<rect width", with: """
            <defs><marker id="arrow" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="\(line)"/></marker></defs>
            <rect width
            """)
        for dot in layout.dots {
            out += String(format: "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"5\" fill=\"%@\" stroke=\"%@\" stroke-width=\"%.1f\"/>\n", dot.x, dot.y, hex(theme.canvas), line, theme.lineWidth)
        }
        for text in layout.texts {
            let anchor = text.anchor.x < 0.5 ? "start" : text.anchor.x > 0.5 ? "end" : "middle"
            let dy = text.anchor.y > 0.5 ? -3.0 : fontSize * 0.85
            out += String(format: "<text x=\"%.1f\" y=\"%.1f\" text-anchor=\"%@\" fill=\"%@\" font-size=\"%.1f\">%@</text>\n",
                          text.position.x, text.position.y + dy, anchor, hex(theme.label), fontSize * 0.85, escape(text.text))
        }
        for node in layout.nodes {
            let palette = node.incomplete ? theme.incomplete : theme.palette(for: node.category)
            let outline = NodeOutline(shape: node.shape).path(in: node.frame)
            let dash = node.shape == .comment ? " stroke-dasharray=\"4 3\"" : ""
            out += "<path d=\"\(data(outline))\" fill=\"\(hex(palette.fill))\" fill-opacity=\"\(opacity(palette.fill))\" stroke=\"\(hex(palette.stroke))\" stroke-width=\"\(theme.lineWidth)\"\(dash)/>\n"
            let detail = NodeDetail(shape: node.shape).path(in: node.frame)
            if !detail.isEmpty {
                out += "<path d=\"\(data(detail))\" fill=\"none\" stroke=\"\(hex(palette.stroke))\" stroke-width=\"\(theme.lineWidth * 0.8)\"/>\n"
            }
            let lines = node.label.components(separatedBy: .newlines)
            if node.shape == .breakpoint {
                out += String(format: "<text x=\"%.1f\" y=\"%.1f\" fill=\"%@\" font-weight=\"500\">%@</text>\n",
                              node.frame.maxX + 8, node.frame.midY + fontSize * 0.35, hex(theme.label), escape(node.label))
            } else {
                let lineHeight = fontSize * 1.25
                let top = node.frame.midY - lineHeight * CGFloat(lines.count - 1) / 2 + fontSize * 0.35
                for (index, text) in lines.enumerated() {
                    out += String(format: "<text x=\"%.1f\" y=\"%.1f\" text-anchor=\"middle\" fill=\"%@\" font-weight=\"500\">%@</text>\n",
                                  node.frame.midX, top + lineHeight * CGFloat(index), hex(palette.text), escape(text))
                }
            }
        }
        out += "</svg>\n"
        return out
    }
}
