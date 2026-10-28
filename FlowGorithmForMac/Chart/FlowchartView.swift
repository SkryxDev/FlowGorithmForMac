// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI
import UniformTypeIdentifiers

/// The interactive flowchart of the current function.
struct FlowchartView: View {
    @Binding var program: Program
    @Bindable var editor: EditorModel
    var session: RunSession

    @AppStorage(SettingsKey.theme) private var themeID = Theme.classic.id
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.showGrid) private var showsGrid = true
    @AppStorage(SettingsKey.compactLayout) private var compact = false
    @FocusState private var focused: Bool
    @Environment(\.aiActions) private var aiActions
    /// Live pinch factor, shown as a cheap transform; the real zoom (a new layout) is applied when the pinch ends.
    @State private var pinch: CGFloat = 1
    @State private var dropTarget: String?
    @State private var dragging = false
    @State private var scrollPosition = ScrollPosition()
    /// The visible part of the chart, needed only to place the insert menu; it's copied in
    /// from `scroll` when the menu opens or the view scrolls while it's open.
    @State private var visibleRect = CGRect.zero
    @State private var scroll = ScrollTracker()
    @State private var menuSize = CGSize.zero

    nonisolated static let dragPrefix = "flowgorithmformac-shape:"

    var theme: Theme { Theme.named(themeID) }
    var scale: CGFloat { editor.zoom }
    var locked: Bool { session.state.isActive }
    /// While a proposal is on the chart, its shapes are drawn but nothing can be edited, so what the
    /// user accepts is exactly what they see.
    var editingBlocked: Bool { locked || editor.proposal != nil }

    var body: some View {
        let preview = editor.proposal?.preview(of: program)
        let function = editor.currentFunction(in: preview?.program ?? program) ?? Function(name: "Main")
        let metrics = ChartMetrics(fontSize: fontSize * scale, compact: compact)
        let layout = editor.layout(for: function, metrics: metrics)

        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                chart(layout, metrics: metrics, function: function, preview: preview)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
                    .background {
                        ZStack {
                            theme.canvas
                            if showsGrid { ChartGrid(theme: theme, scale: scale).equatable() }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editor.selection = nil
                            editor.insertTarget = nil
                            focused = true
                        }
                    }
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                // Kept outside SwiftUI's state so scrolling doesn't rebuild the whole chart every frame.
                scroll.visibleRect = rect
                if editor.insertTarget != nil { visibleRect = rect }
            }
            .scaleEffect(pinch)
            .overlay(alignment: .topLeading) {
                insertMenu(layout: layout, viewport: geo.size)
            }
            .onChange(of: session.currentStatement) { _, id in
                guard session.state != .running || session.speed < 0.98 else { return }
                reveal(id, in: layout, viewport: geo.size)
            }
            .onChange(of: session.state) { _, state in
                if state.isActive { editor.insertTarget = nil }
                if state == .paused || state == .waitingForInput || state == .waitingForPermission || state == .failed {
                    reveal(session.currentStatement, in: layout, viewport: geo.size)
                }
            }
            .onChange(of: editor.selection) { _, id in
                reveal(id, in: layout, viewport: geo.size)
            }
            .onChange(of: editor.proposal?.id) {
                // Bring the first proposed shape into view.
                guard let preview else { return }
                let first = layout.nodes.first { node in node.statement.map { preview.fresh.contains($0.id) || preview.ghosts.contains($0.id) } ?? false }
                reveal(first?.statement?.id, in: layout, viewport: geo.size)
            }
        }
        .background(theme.canvas)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onDeleteCommand {
            guard !editingBlocked, let selection = editor.selection else { return }
            editor.delete(selection, in: $program)
        }
        .onExitCommand { editor.insertTarget = nil }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let zoom = editor.zoom
                    pinch = min(EditorModel.maxZoom / zoom, max(EditorModel.minZoom / zoom, value.magnification))
                }
                .onEnded { _ in
                    let zoom = (editor.zoom * pinch * 100).rounded() / 100
                    pinch = 1
                    editor.zoom = min(EditorModel.maxZoom, max(EditorModel.minZoom, zoom))
                }
        )
        .onChange(of: session.currentFunctionName) { _, name in
            // Follow execution into other functions.
            guard let name, let target = program.function(named: name), target.id != editor.functionID else { return }
            if session.state == .paused || session.state == .failed || session.speed < 0.98 {
                editor.functionID = target.id
            }
        }
        .onChange(of: editor.functionID) { editor.insertTarget = nil }
    }

    /// The shape palette for the "+" the user clicked, drawn over the chart rather than in a
    /// system popover, and kept inside the visible area.
    @ViewBuilder
    func insertMenu(layout: ChartLayout, viewport: CGSize) -> some View {
        if let target = editor.insertTarget, !editingBlocked,
           let insert = layout.inserts.first(where: { $0.point == target }) {
            let contentWidth = max(layout.size.width, viewport.width)
            let anchor = CGPoint(x: insert.position.x + (contentWidth - layout.size.width) / 2 - visibleRect.minX,
                                 y: insert.position.y - visibleRect.minY)
            let size = menuSize == .zero ? CGSize(width: 520, height: 260) : menuSize
            let fitsRight = anchor.x + 20 + size.width <= viewport.width - 8
            let fitsLeft = anchor.x - 20 - size.width >= 8
            let beside = fitsRight || fitsLeft
            let rightSide = fitsRight || !fitsLeft
            let x = fitsRight ? anchor.x + 20
                : fitsLeft ? anchor.x - 20 - size.width
                : min(max(8, anchor.x - size.width / 2), max(8, viewport.width - size.width - 8))
            let below = anchor.y + 22 + size.height <= viewport.height - 8
            let y = beside ? min(max(8, anchor.y - 36), max(8, viewport.height - size.height - 8))
                : below ? anchor.y + 22 : max(8, anchor.y - 22 - size.height)
            ZStack(alignment: .topLeading) {
                // Clicking anywhere else closes the menu, as a popover would.
                Color.black.opacity(0.001)
                    .frame(width: viewport.width, height: viewport.height)
                    .onTapGesture { editor.insertTarget = nil }
                InsertMenu(theme: theme, canPaste: editor.canPaste) { template in
                    editor.insertTarget = nil
                    editor.insert(template, at: insert.point, in: $program)
                } onPaste: {
                    editor.insertTarget = nil
                    editor.paste(at: insert.point, in: $program)
                }
                .fixedSize()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { menuSize = $0 }
                .offset(x: x, y: y)
                .transition(.scale(scale: 0.92, anchor: rightSide ? .leading : .trailing).combined(with: .opacity))
            }
            .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        }
    }

    /// Scrolls just enough to bring a shape to the middle of the view, if it isn't visible already.
    func reveal(_ id: Statement.ID?, in layout: ChartLayout, viewport: CGSize) {
        guard let id, let node = layout.nodes.first(where: { $0.statement?.id == id }) else { return }
        let contentSize = CGSize(width: max(layout.size.width, viewport.width), height: max(layout.size.height, viewport.height))
        let frame = node.frame.offsetBy(dx: (contentSize.width - layout.size.width) / 2, dy: 0)
        let visible = scroll.visibleRect
        if visible.width > 0, visible.insetBy(dx: 16, dy: 16).contains(frame) { return }
        let x = max(0, min(frame.midX - viewport.width / 2, contentSize.width - viewport.width))
        let y = max(0, min(frame.midY - viewport.height / 2, contentSize.height - viewport.height))
        withAnimation(.smooth(duration: 0.35)) { scrollPosition.scrollTo(point: CGPoint(x: x, y: y)) }
    }

    func highlight(for node: ChartNode, preview: Proposal.Preview?) -> NodeHighlight {
        guard let id = node.statement?.id else { return .none }
        if let preview {
            if preview.ghosts.contains(id) { return .ghost }
            if preview.fresh.contains(id) { return .proposed }
        }
        if session.state == .failed, session.error?.statementID == id { return .error }
        if session.state.isActive, session.currentStatement == id { return .executing }
        if editor.flashing.contains(id) { return .changed }
        if editor.selection == id { return .selected }
        return .none
    }

    func chart(_ layout: ChartLayout, metrics: ChartMetrics, function: Function, preview: Proposal.Preview?) -> some View {
        ZStack(alignment: .topLeading) {
            ChartLines(layout: layout, theme: theme, fontSize: metrics.fontSize, scale: scale)
                .equatable()

            ForEach(layout.nodes) { node in
                let highlight = highlight(for: node, preview: preview)
                ShapeView(node: node, theme: theme, fontSize: metrics.fontSize, scale: scale, highlight: highlight)
                    .equatable()
                    // The old version of a proposed change: faded, almost white, out of the way.
                    .opacity(highlight == .ghost ? 0.32 : 1)
                    .saturation(highlight == .ghost ? 0 : 1)
                    .allowsHitTesting(highlight != .ghost && highlight != .proposed)
                    // Every modifier goes before .position: after it, the view fills the whole chart,
                    // and a drop zone or menu would cover everything.
                    .onTapGesture(count: 2) { open(node, function: function) }
                    .simultaneousGesture(TapGesture().onEnded {
                        editor.selection = node.statement?.id
                        editor.insertTarget = nil
                        focused = true
                    })
                    .contextMenu { contextMenu(for: node, function: function) }
                    .onDrag {
                        guard let id = node.statement?.id, !editingBlocked else { return NSItemProvider() }
                        dragging = true
                        return NSItemProvider(object: "\(Self.dragPrefix)\(id.uuidString)" as NSString)
                    }
                    .help(node.problem ?? "")
                    .position(x: node.frame.midX, y: node.frame.midY)
            }

            if !editingBlocked {
                ForEach(layout.inserts) { insert in
                    InsertButton(theme: theme, scale: scale, targeted: dropTarget == insert.id,
                                 presented: editor.insertTarget == insert.point) {
                        visibleRect = scroll.visibleRect
                        withAnimation(.snappy(duration: 0.2)) {
                            editor.insertTarget = editor.insertTarget == insert.point ? nil : insert.point
                        }
                    }
                    .onDrop(of: [.plainText], isTargeted: Binding(
                        get: { dropTarget == insert.id },
                        set: { dropTarget = $0 ? insert.id : (dropTarget == insert.id ? nil : dropTarget) })) { providers in
                        handleDrop(providers, at: insert.point)
                    }
                    .position(insert.position)
                }
            }
        }
    }

    func open(_ node: ChartNode, function: Function) {
        guard !editingBlocked else { return }
        switch node.role {
        case .statement:
            if let statement = node.statement, statement.template != nil {
                editor.editingStatement = statement
            }
        case .start, .end:
            if function.isMain {
                editor.showsProgramInfo = true
            } else {
                editor.editingFunction = function
            }
        }
    }

    @ViewBuilder
    func contextMenu(for node: ChartNode, function: Function) -> some View {
        if let statement = node.statement {
            Button("Edit…", systemImage: "pencil") { editor.editingStatement = statement }
                .disabled(editingBlocked || statement.template == nil)
            if let aiActions, aiActions.isAvailable {
                Divider()
                Button("Explain with AI", systemImage: "sparkles") {
                    aiActions.ask(.explainShape(statement.id, label: node.label))
                }
                if let problem = problem(of: node, statement: statement) {
                    Button("What's Wrong Here?", systemImage: "questionmark.bubble") {
                        aiActions.ask(.shapeProblem(statement.id, label: node.label, problem: problem))
                    }
                }
            }
            Divider()
            Button("Cut", systemImage: "scissors") { editor.cut(statement.id, in: $program) }.disabled(editingBlocked)
            Button("Copy", systemImage: "doc.on.doc") { editor.copy(statement.id, in: program) }
            Button("Paste After", systemImage: "doc.on.clipboard") {
                editor.selection = statement.id
                editor.paste(in: $program)
            }
            // Not tied to canPaste: the menu is built before the user copies, so it would be stale.
            .disabled(editingBlocked)
            Button("Duplicate", systemImage: "plus.square.on.square") { editor.duplicate(statement.id, in: $program) }.disabled(editingBlocked)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { editor.delete(statement.id, in: $program) }.disabled(editingBlocked)
        } else if function.isMain {
            Button("Program Info…", systemImage: "info.circle") { editor.showsProgramInfo = true }
        } else {
            Button("Edit Function…", systemImage: "function") { editor.editingFunction = function }
                .disabled(editingBlocked)
        }
    }

    /// What the app finds wrong with a shape: the error the last run stopped on, a mistake in its
    /// text, or an empty field.
    func problem(of node: ChartNode, statement: Statement) -> String? {
        if session.state == .failed, let error = session.error, error.statementID == statement.id {
            return ErrorText.message(error)
        }
        if let problem = node.problem { return problem }
        return node.incomplete ? String(localized: "A required field is empty.") : nil
    }

    func handleDrop(_ providers: [NSItemProvider], at point: InsertionPoint) -> Bool {
        dragging = false
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix(Self.dragPrefix),
                  let id = UUID(uuidString: String(text.dropFirst(Self.dragPrefix.count))) else { return }
            Task { @MainActor in
                withAnimation(.snappy) { editor.move(id, to: point, in: $program) }
            }
        }
        return true
    }
}

/// The "+" on a connector. Small and quiet until hovered.
struct InsertButton: View {
    let theme: Theme
    let scale: CGFloat
    var targeted: Bool
    var presented: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        let active = hovering || presented || targeted
        let size = 20 * max(scale, 0.7)
        Circle()
            .fill(Color.accentColor)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: Color.accentColor.opacity(active ? 0.5 : 0), radius: active ? 4 : 0)
            .scaleEffect(active ? (targeted ? 1.3 : 1) : 0.3)
            .opacity(active ? 1 : 0)
            .frame(width: 28 * max(scale, 0.7), height: 24 * max(scale, 0.7))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.snappy(duration: 0.18), value: active)
            .onTapGesture(perform: onTap)
            .help("Add a shape here")
    }
}

/// Holds the scroll view's visible rectangle without triggering view updates.
final class ScrollTracker {
    var visibleRect = CGRect.zero
}
