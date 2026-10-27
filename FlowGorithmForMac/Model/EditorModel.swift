// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import AppKit
import FlowCore
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case console, variables, turtle, code

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .console: "Console"
        case .variables: "Variables"
        case .turtle: "Turtle"
        case .code: "Code"
        }
    }

    var symbol: String {
        switch self {
        case .console: "bubble.left.and.bubble.right"
        case .variables: "list.bullet.rectangle"
        case .turtle: "scribble.variable"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Per-window editor state: which function is shown, what's selected, zoom and open sheets.
@Observable
final class EditorModel {
    var functionID: Function.ID?
    var selection: Statement.ID?
    var zoom: CGFloat = 1
    var editingStatement: Statement?
    var editingFunction: Function?
    var isAddingFunction = false
    var showsProgramInfo = false
    var insertTarget: InsertionPoint?
    var showsInspector = true
    var topPanel: PanelTab = .console
    var bottomPanel: PanelTab = .variables
    var showsBottomPanel = true
    var lastError: String?
    /// Shapes the assistant just changed, highlighted for a moment.
    private(set) var flashing: Set<Statement.ID> = []
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    // The layout of the shown function, rebuilt only when the function or the metrics change.
    @ObservationIgnored private var cachedLayout: (function: Function, fontSize: CGFloat, compact: Bool, layout: ChartLayout)?
    @ObservationIgnored private var layoutRevision = 0

    func layout(for function: Function, metrics: ChartMetrics) -> ChartLayout {
        if let cached = cachedLayout, cached.fontSize == metrics.fontSize, cached.compact == metrics.compact, cached.function == function {
            return cached.layout
        }
        layoutRevision += 1
        var layout = ChartLayout.make(function, metrics: metrics)
        layout.revision = layoutRevision
        cachedLayout = (function, metrics.fontSize, metrics.compact, layout)
        return layout
    }

    static let minZoom: CGFloat = 0.3
    static let maxZoom: CGFloat = 3

    func zoomIn() { zoom = min(Self.maxZoom, (zoom * 1.2 * 100).rounded() / 100) }
    func zoomOut() { zoom = max(Self.minZoom, (zoom / 1.2 * 100).rounded() / 100) }
    func resetZoom() { zoom = 1 }

    func currentFunction(in program: Program) -> Function? {
        if let functionID, let function = program.functions.first(where: { $0.id == functionID }) { return function }
        return program.main
    }

    /// Highlights shapes for a couple of seconds, so the user sees what the assistant changed.
    func flash(_ ids: [Statement.ID]) {
        flashTask?.cancel()
        guard !ids.isEmpty else { return }
        flashing = Set(ids)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { self?.flashing = [] }
        }
    }

    func show(_ panel: PanelTab) {
        showsInspector = true
        if topPanel != panel && !(showsBottomPanel && bottomPanel == panel) { topPanel = panel }
    }

    // MARK: Editing

    func mutateBody(_ program: Binding<Program>, _ change: (inout [Statement]) -> Void) {
        guard let function = currentFunction(in: program.wrappedValue),
              let index = program.wrappedValue.functionIndex(id: function.id) else { return }
        var body = program.wrappedValue.functions[index].body
        change(&body)
        program.wrappedValue.functions[index].body = body
    }

    func insert(_ template: StatementTemplate, at point: InsertionPoint, in program: Binding<Program>) {
        let statement = Statement.make(template)
        mutateBody(program) { $0.insert(statement, at: point) }
        selection = statement.id
        if needsEditor(template) { editingStatement = statement }
    }

    func needsEditor(_ template: StatementTemplate) -> Bool {
        ![.home, .clear, .close].contains(template)
    }

    func replace(_ statement: Statement, in program: Binding<Program>) {
        mutateBody(program) { $0.replaceStatement(statement) }
    }

    func delete(_ id: Statement.ID, in program: Binding<Program>) {
        mutateBody(program) { $0.removeStatement(withID: id) }
        if selection == id { selection = nil }
    }

    func move(_ id: Statement.ID, to point: InsertionPoint, in program: Binding<Program>) {
        mutateBody(program) { $0.moveStatement(withID: id, to: point) }
        selection = id
    }

    func duplicate(_ id: Statement.ID, in program: Binding<Program>) {
        guard let function = currentFunction(in: program.wrappedValue),
              let statement = function.body.statement(withID: id),
              let location = function.body.location(of: id) else { return }
        let copy = statement.withNewIDs()
        mutateBody(program) { $0.insert(copy, at: InsertionPoint(block: location.block, index: location.index + 1)) }
        selection = copy.id
    }

    // MARK: Clipboard

    static let pasteboardType = NSPasteboard.PasteboardType("dev.skryx.flowgorithmformac.shapes")

    func copy(_ id: Statement.ID, in program: Program) {
        guard let statement = currentFunction(in: program)?.body.statement(withID: id) else { return }
        let fragment = FPRGWriter.fragment([statement])
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(fragment, forType: Self.pasteboardType)
        // Plain text for other apps: the shape as pseudocode, without the function's indentation.
        let lines = CodeGenerator.generate(Program(functions: [Function(name: "Main", body: [statement])]),
                                           language: .pseudocodeEnglish).lines
            .filter { $0.statementID != nil }.map(\.text)
        let indent = lines.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
        board.setString(lines.map { String($0.dropFirst(indent)) }.joined(separator: "\n"), forType: .string)
    }

    func cut(_ id: Statement.ID, in program: Binding<Program>) {
        copy(id, in: program.wrappedValue)
        delete(id, in: program)
    }

    var canPaste: Bool { NSPasteboard.general.string(forType: Self.pasteboardType) != nil }

    /// Pastes after the selected shape, at the given point, or at the end of the function.
    func paste(at point: InsertionPoint? = nil, in program: Binding<Program>) {
        guard let fragment = NSPasteboard.general.string(forType: Self.pasteboardType),
              let statements = FPRGWriter.statements(fromFragment: fragment), !statements.isEmpty,
              let function = currentFunction(in: program.wrappedValue) else { return }
        var target = point
        if target == nil, let selection, let location = function.body.location(of: selection) {
            target = InsertionPoint(block: location.block, index: location.index + 1)
        }
        let insertion = target ?? InsertionPoint(block: .functionBody, index: function.body.count)
        mutateBody(program) { body in
            for (offset, statement) in statements.enumerated() {
                body.insert(statement, at: InsertionPoint(block: insertion.block, index: insertion.index + offset))
            }
        }
        selection = statements.last?.id
    }

    // MARK: Functions

    func addFunction(_ function: Function, to program: Binding<Program>) {
        program.wrappedValue.functions.append(function)
        functionID = function.id
        selection = nil
    }

    func updateFunction(_ function: Function, in program: Binding<Program>) {
        guard let index = program.wrappedValue.functionIndex(id: function.id) else { return }
        var updated = function
        updated.body = program.wrappedValue.functions[index].body
        program.wrappedValue.functions[index] = updated
    }

    func deleteFunction(_ id: Function.ID, from program: Binding<Program>) {
        guard let index = program.wrappedValue.functionIndex(id: id), !program.wrappedValue.functions[index].isMain else { return }
        program.wrappedValue.functions.remove(at: index)
        if functionID == id { functionID = program.wrappedValue.main?.id }
    }
}
