// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// The changes the assistant proposes in study mode. The chart draws them; the chat lists them,
/// one line per shape, with the buttons that accept or reject them.
struct ProposalCard: View {
    let entry: AIChat.Entry
    var canAccept: Bool
    var accept: () -> Void
    var reject: () -> Void
    var show: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: show) {
                HStack(spacing: 6) {
                    Label("Proposed change", systemImage: "lightbulb.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AIMode.study.color)
                    Spacer(minLength: 4)
                    if entry.resolution == nil {
                        Text("On the chart")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.resolution != nil)
            .help("Show the proposal on the chart")

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entry.text.split(separator: "\n").prefix(8).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: String(line))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(entry.resolution == nil ? .primary : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.text.split(separator: "\n").count > 8 {
                    Text(verbatim: "…").font(.caption).foregroundStyle(.secondary)
                }
            }
            footer
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIMode.study.color.opacity(entry.resolution == nil ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AIMode.study.color.opacity(entry.resolution == nil ? 0.35 : 0.12), lineWidth: 1))
    }

    @ViewBuilder
    var footer: some View {
        switch entry.resolution {
        case nil:
            HStack(spacing: 8) {
                Button(action: reject) {
                    Label("Reject", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .help("Leave the chart as it is")
                Button(action: accept) {
                    Label("Accept", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AIMode.study.color)
                .disabled(!canAccept)
                .help(canAccept ? "Make these changes on the chart" : "Stop the program to change the chart")
            }
            .controlSize(.small)
        case .accepted?:
            Label("Accepted", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .rejected?:
            Label("Rejected", systemImage: "xmark.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .replaced?:
            Label("Replaced by a newer proposal", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// A small example flowchart the assistant drew in the chat, with a button that puts it on the
/// chart.
struct ExampleCard: View {
    let shapes: [Statement]
    var used: Bool
    /// Whether the function on screen has shapes, which the example then replaces.
    var replaces: Bool
    var canUse: Bool
    var use: () -> Void

    @AppStorage(SettingsKey.theme) private var themeID = Theme.classic.id

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Example", systemImage: "graduationcap.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AIMode.study.color)
            MiniChart(shapes: shapes, theme: Theme.named(themeID))
                .frame(maxWidth: .infinity)
            if used {
                Label("On the chart", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Button(action: use) {
                    Label(replaces ? "Replace the Chart with This Example" : "Put This Example on the Chart",
                          systemImage: "square.and.arrow.down.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!canUse)
                .help(replaces ? "The shapes of the function on screen are replaced; you can undo it" : "Adds these shapes to the function on screen")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIMode.study.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AIMode.study.color.opacity(0.25), lineWidth: 1))
    }
}

/// A few shapes laid out as a small flowchart, from start to end, shrunk to fit the chat when the
/// branches of an if make it wide.
struct MiniChart: View {
    let shapes: [Statement]
    let theme: Theme

    static let fontSize: CGFloat = 11
    /// About the room inside a card at the assistant column's usual width. A fixed size keeps the
    /// column from depending on its content, which AppKit can't settle.
    static let maxWidth: CGFloat = 250

    var body: some View {
        let metrics = ChartMetrics(fontSize: Self.fontSize, compact: true)
        let layout = ChartLayout.make(Function(name: "Main", body: shapes), metrics: metrics)
        // The layout keeps a wide margin for the editor; the chat needs only a little.
        let trim = metrics.margin - 6
        let size = CGSize(width: max(1, layout.size.width - trim * 2), height: max(1, layout.size.height - trim * 2))
        let fit = min(1, Self.maxWidth / size.width)
        ZStack(alignment: .topLeading) {
            ChartLines(layout: layout, theme: theme, fontSize: Self.fontSize, scale: Self.fontSize / 13)
            ForEach(layout.nodes) { node in
                ShapeView(node: node, theme: theme, fontSize: Self.fontSize, scale: Self.fontSize / 13)
                    .position(x: node.frame.midX, y: node.frame.midY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .offset(x: -trim, y: -trim)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .scaleEffect(fit, anchor: .topLeading)
        .frame(width: size.width * fit, height: size.height * fit, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
