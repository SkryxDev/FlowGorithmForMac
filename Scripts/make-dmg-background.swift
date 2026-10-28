// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

// Draws the background of the disk image window, at 1x and 2x, into one TIFF Finder picks from.
// Usage: swift Scripts/make-dmg-background.swift Scripts/dmg-background.tiff
// The layout matches Scripts/make-dmg.sh: a 640×400 window, the app at (160, 200), Applications
// at (480, 200).

import AppKit
import SwiftUI

let size = CGSize(width: 640, height: 400)
let appCenter = CGPoint(x: 160, y: 200)
let applicationsCenter = CGPoint(x: 480, y: 200)

/// A flowchart shape outline, drawn faintly around the edges.
struct Outline: Shape {
    enum Kind { case terminal, process, decision, data, declare }
    var kind: Kind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .terminal:
            return Capsule().path(in: rect)
        case .process:
            return RoundedRectangle(cornerRadius: 4).path(in: rect)
        case .declare:
            var path = RoundedRectangle(cornerRadius: 4).path(in: rect)
            path.move(to: CGPoint(x: rect.minX + 7, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + 7, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + 7))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 7))
            return path
        case .decision:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case .data:
            var path = Path()
            let slant = rect.height * 0.35
            path.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// A small flowchart going down, used as a watermark on each side.
struct Watermark: View {
    var shapes: [Outline.Kind]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(shapes.enumerated()), id: \.offset) { index, kind in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1.5, height: 10)
                        .padding(.vertical, -14)
                }
                Outline(kind: kind)
                    .stroke(.white.opacity(0.13), lineWidth: 1.5)
                    .frame(width: kind == .decision ? 64 : kind == .terminal ? 58 : 70, height: kind == .decision ? 38 : 24)
            }
        }
    }
}

/// The slightly curved arrow from the app to Applications, and its head along the curve's end.
struct Arrow: Shape {
    var head = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.maxY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        let control = CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6)
        if head {
            // A quadratic curve leaves its control point toward the end point.
            let angle = atan2(end.y - control.y, end.x - control.x)
            for side in [-1.0, 1.0] {
                let wing = angle + .pi - side * 0.5
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x + cos(wing) * 13, y: end.y + sin(wing) * 13))
            }
        } else {
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
        return path
    }
}

struct Background: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.16, blue: 0.45), Color(red: 0.42, green: 0.35, blue: 0.80)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 360)

            // The editor's dotted canvas.
            Canvas { context, size in
                for x in stride(from: 10.0, to: size.width, by: 20) {
                    for y in stride(from: 10.0, to: size.height, by: 20) {
                        context.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(.white.opacity(0.08)))
                    }
                }
            }

            Watermark(shapes: [.terminal, .declare, .data, .decision, .process, .terminal])
                .position(x: 46, y: 215)
            Watermark(shapes: [.terminal, .data, .decision, .process, .data, .terminal])
                .position(x: 594, y: 215)

            VStack(spacing: 5) {
                Text("FlowGorithmForMac")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                Text("Drag the app into Applications")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                Text("Trascina l'app nella cartella Applicazioni")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .position(x: size.width / 2, y: 64)

            // A frosted shelf the two icons and their names sit on, light enough for Finder's black
            // names in light mode and dark enough for its white names in dark mode.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.24))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1))
                .frame(width: 470, height: 200)
                .position(x: size.width / 2, y: 232)

            ZStack {
                Arrow()
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 7]))
                Arrow(head: true)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 150, height: 30)
            .position(x: size.width / 2, y: appCenter.y - 4)

            Text("1.0")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .position(x: size.width - 26, y: size.height - 16)
        }
        .frame(width: size.width, height: size.height)
    }
}

guard CommandLine.arguments.count > 1 else {
    print("usage: swift Scripts/make-dmg-background.swift <output.tiff>")
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
// Drawing with SwiftUI happens on the main thread, where a script's code already runs.
let tiff: Data? = MainActor.assumeIsolated {
    let image = NSImage(size: size)
    for scale in [1.0, 2.0] {
        let renderer = ImageRenderer(content: Background())
        renderer.scale = scale
        guard let picture = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: picture)
        // Both sizes are the same picture in points: Finder uses the sharp one on Retina screens.
        rep.size = size
        image.addRepresentation(rep)
    }
    return image.tiffRepresentation(using: .lzw, factor: 0)
}
guard let tiff else { print("Couldn't draw the background"); exit(1) }
try tiff.write(to: output)
print(output.path)
