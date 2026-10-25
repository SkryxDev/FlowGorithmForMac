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
    @State private var pinchStart: CGFloat?
    @State private var dropTarget: String?
    @State private var dragging = false
    @State private var scrollPosition = ScrollPosition()
    @State private var visibleRect = CGRect.zero

    nonisolated static let dragPrefix = "flowgorithmformac-shape:"

    var theme: Theme { Theme.named(themeID) }
    var scale: CGFloat { editor.zoom }
    var locked: Bool { session.state.isActive }

    var body: some View {
        let function = editor.currentFunction(in: program) ?? Function(name: "Main")
        let metrics = ChartMetrics(fontSize: fontSize * scale, compact: compact)
        let layout = ChartLayout.make(function, metrics: metrics)

        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                chart(layout, metrics: metrics, function: function)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
                    .background {
                        ZStack {
                            theme.canvas
                            if showsGrid { ChartGrid(theme: theme, scale: scale) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editor.selection = nil
                            focused = true
                        }
                    }
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                visibleRect = rect
            }
            .onChange(of: session.currentStatement) { _, id in
                guard session.state != .running || session.speed < 0.98 else { return }
                reveal(id, in: layout, viewport: geo.size)
            }
            .onChange(of: session.state) { _, state in
                if state == .paused || state == .waitingForInput || state == .failed {
                    reveal(session.currentStatement, in: layout, viewport: geo.size)
                }
            }
            .onChange(of: editor.selection) { _, id in
                reveal(id, in: layout, viewport: geo.size)
            }
        }
        .background(theme.canvas)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onDeleteCommand {
            guard !locked, let selection = editor.selection else { return }
            editor.delete(selection, in: $program)
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? editor.zoom
                    pinchStart = start
                    editor.zoom = min(EditorModel.maxZoom, max(EditorModel.minZoom, start * value.magnification))
                }
                .onEnded { _ in pinchStart = nil }
        )
        .onChange(of: session.currentFunctionName) { _, name in
            // Follow execution into other functions.
            guard let name, let target = program.function(named: name), target.id != editor.functionID else { return }
            if session.state == .paused || session.state == .failed || session.speed < 0.98 {
                editor.functionID = target.id
            }
        }
    }

    /// Scrolls just enough to bring a shape to the middle of the view, if it isn't visible already.
    func reveal(_ id: Statement.ID?, in layout: ChartLayout, viewport: CGSize) {
        guard let id, let node = layout.nodes.first(where: { $0.statement?.id == id }) else { return }
        let contentSize = CGSize(width: max(layout.size.width, viewport.width), height: max(layout.size.height, viewport.height))
        let frame = node.frame.offsetBy(dx: (contentSize.width - layout.size.width) / 2, dy: 0)
        if visibleRect.width > 0, visibleRect.insetBy(dx: 16, dy: 16).contains(frame) { return }
        let x = max(0, min(frame.midX - viewport.width / 2, contentSize.width - viewport.width))
        let y = max(0, min(frame.midY - viewport.height / 2, contentSize.height - viewport.height))
        withAnimation(.smooth(duration: 0.35)) { scrollPosition.scrollTo(point: CGPoint(x: x, y: y)) }
    }

    func highlight(for node: ChartNode) -> NodeHighlight {
        guard let id = node.statement?.id else { return .none }
        if session.state == .failed, session.error?.statementID == id { return .error }
        if session.state.isActive, session.currentStatement == id { return .executing }
        if editor.selection == id { return .selected }
        return .none
    }

    func chart(_ layout: ChartLayout, metrics: ChartMetrics, function: Function) -> some View {
        ZStack(alignment: .topLeading) {
            ChartLines(layout: layout, theme: theme, fontSize: metrics.fontSize, scale: scale)

            ForEach(layout.nodes) { node in
                ShapeView(node: node, theme: theme, fontSize: metrics.fontSize, scale: scale, highlight: highlight(for: node))
                    .id(node.id)
                    .position(x: node.frame.midX, y: node.frame.midY)
                    .onTapGesture(count: 2) { open(node, function: function) }
                    .simultaneousGesture(TapGesture().onEnded {
                        editor.selection = node.statement?.id
                        focused = true
                    })
                    .contextMenu { contextMenu(for: node, function: function) }
                    .onDrag {
                        guard let id = node.statement?.id, !locked else { return NSItemProvider() }
                        dragging = true
                        return NSItemProvider(object: "\(Self.dragPrefix)\(id.uuidString)" as NSString)
                    }
                    .help(node.statement.flatMap { $0.validationError.map(ErrorText.message) } ?? "")
            }

            if !locked {
                ForEach(layout.inserts) { insert in
                    InsertButton(theme: theme, scale: scale, targeted: dropTarget == insert.id,
                                 presented: Binding(
                                    get: { editor.insertTarget == insert.point },
                                    set: { if !$0, editor.insertTarget == insert.point { editor.insertTarget = nil } }),
                                 onTap: { editor.insertTarget = insert.point }) {
                        InsertMenu(theme: theme, canPaste: editor.canPaste) { template in
                            editor.insertTarget = nil
                            editor.insert(template, at: insert.point, in: $program)
                        } onPaste: {
                            editor.insertTarget = nil
                            editor.paste(at: insert.point, in: $program)
                        }
                    }
                    .position(insert.position)
                    .onDrop(of: [.plainText], isTargeted: Binding(
                        get: { dropTarget == insert.id },
                        set: { dropTarget = $0 ? insert.id : (dropTarget == insert.id ? nil : dropTarget) })) { providers in
                        handleDrop(providers, at: insert.point)
                    }
                }
            }
        }
    }

    func open(_ node: ChartNode, function: Function) {
        guard !locked else { return }
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
                .disabled(locked || statement.template == nil)
            Divider()
            Button("Cut", systemImage: "scissors") { editor.cut(statement.id, in: $program) }.disabled(locked)
            Button("Copy", systemImage: "doc.on.doc") { editor.copy(statement.id, in: program) }
            Button("Paste After", systemImage: "doc.on.clipboard") {
                editor.selection = statement.id
                editor.paste(in: $program)
            }
            .disabled(locked || !editor.canPaste)
            Button("Duplicate", systemImage: "plus.square.on.square") { editor.duplicate(statement.id, in: $program) }.disabled(locked)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { editor.delete(statement.id, in: $program) }.disabled(locked)
        } else if function.isMain {
            Button("Program Info…", systemImage: "info.circle") { editor.showsProgramInfo = true }
        } else {
            Button("Edit Function…", systemImage: "function") { editor.editingFunction = function }
        }
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
struct InsertButton<Menu: View>: View {
    let theme: Theme
    let scale: CGFloat
    var targeted: Bool
    @Binding var presented: Bool
    let onTap: () -> Void
    @ViewBuilder let menu: () -> Menu

    @State private var hovering = false

    var body: some View {
        let active = hovering || presented || targeted
        let size = (active ? 20 : 6) * max(scale, 0.7)
        ZStack {
            Circle()
                .fill(active ? Color.accentColor : .clear)
                .shadow(color: active ? Color.accentColor.opacity(0.5) : .clear, radius: 4)
            if active {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(targeted ? 1.3 : 1)
        .frame(width: 28 * max(scale, 0.7), height: 24 * max(scale, 0.7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: active)
        .onTapGesture(perform: onTap)
        .popover(isPresented: $presented, arrowEdge: .trailing, content: menu)
        .help("Add a shape here")
    }
}
