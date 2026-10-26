// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// The palette of shapes shown when clicking a connector, grouped like Flowgorithm's menu.
struct InsertMenu: View {
    let theme: Theme
    let canPaste: Bool
    let onInsert: (StatementTemplate) -> Void
    let onPaste: () -> Void

    @State private var showsExtras = false

    struct Section: Identifiable {
        var id: String { title.key }
        var title: LocalizedStringResource
        var templates: [StatementTemplate]
    }

    static let main: [Section] = [
        Section(title: "Input / Output", templates: [.input, .output]),
        Section(title: "Variables", templates: [.declare, .assign]),
        Section(title: "Selection", templates: [.if, .call]),
        Section(title: "Loops", templates: [.while, .for, .do]),
    ]

    static let extras: [Section] = [
        Section(title: "Turtle graphics", templates: [.forward, .turn, .home, .clear, .pen]),
        Section(title: "Files", templates: [.open, .read, .write, .close]),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Self.main) { section in
                        column(section)
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    tile(.comment)
                    tile(.breakpoint)
                    Spacer()
                    if canPaste {
                        Button("Paste", systemImage: "doc.on.clipboard", action: onPaste)
                            .buttonStyle(.glass)
                    }
                    Button {
                        withAnimation(.snappy) { showsExtras.toggle() }
                    } label: {
                        Label(showsExtras ? "Less" : "More", systemImage: showsExtras ? "chevron.left" : "chevron.right")
                    }
                    .buttonStyle(.glass)
                    .help("Turtle graphics and file shapes")
                }
            }
            if showsExtras {
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.extras) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            header(section.title)
                            LazyVGrid(columns: [GridItem(.fixed(108)), GridItem(.fixed(108))], alignment: .leading, spacing: 8) {
                                ForEach(section.templates, id: \.self) { tile($0) }
                            }
                        }
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
    }

    func header(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    func column(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(section.title)
            ForEach(section.templates, id: \.self) { tile($0) }
        }
    }

    func tile(_ template: StatementTemplate) -> some View {
        Button {
            onInsert(template)
        } label: {
            ShapePreview(template: template, theme: theme)
                .frame(width: 108, height: 34)
        }
        .buttonStyle(.plain)
        .help(ShapeText.help(template))
    }
}

/// A small sample of a shape, used in the insert menu.
struct ShapePreview: View {
    let template: StatementTemplate
    let theme: Theme

    var body: some View {
        let statement = Statement.make(template)
        let builder = ChartLayout.Builder(metrics: ChartMetrics(fontSize: 11, compact: false))
        let shape = builder.shape(of: statement)
        let palette = theme.palette(for: statement.category)
        GeometryReader { geo in
            let rect = shape == .breakpoint
                ? CGRect(x: 4, y: (geo.size.height - 22) / 2, width: 22, height: 22)
                : CGRect(origin: .zero, size: geo.size).insetBy(dx: 2, dy: 2)
            ZStack(alignment: .leading) {
                NodeOutline(shape: shape)
                    .fill(LinearGradient(colors: [palette.fill, palette.fillEnd], startPoint: .top, endPoint: .bottom))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                NodeOutline(shape: shape)
                    .stroke(palette.stroke, style: StrokeStyle(lineWidth: 1.2, dash: shape == .comment ? [3, 2] : []))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                NodeDetail(shape: shape)
                    .stroke(palette.stroke, lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                Text(ShapeText.name(template))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(shape == .breakpoint ? Color.primary : palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: shape == .breakpoint ? geo.size.width - 30 : geo.size.width, alignment: shape == .breakpoint ? .leading : .center)
                    .offset(x: shape == .breakpoint ? 30 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}
