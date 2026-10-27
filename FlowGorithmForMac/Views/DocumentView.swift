// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import AppKit
import FlowCore
import SwiftUI

/// Actions the menu bar can trigger in the focused window.
struct DocumentActions {
    var run: () -> Void
    var step: () -> Void
    var pause: () -> Void
    var stop: () -> Void
    var isRunning: Bool
    var isPaused: Bool
    var hasSelection: Bool
    var cut: () -> Void
    var copy: () -> Void
    var paste: () -> Void
    var delete: () -> Void
    var duplicate: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var resetZoom: () -> Void
    var showPanel: (PanelTab) -> Void
    var toggleInspector: () -> Void
    var toggleBottomPanel: () -> Void
    var showsBottomPanel: Bool
    var addFunction: () -> Void
    var programInfo: () -> Void
    var export: (ChartExporter.Format) -> Void
    var print: () -> Void
    var setSpeed: (Double) -> Void
    var speed: Double
    var ignoreBreakpoints: Bool
    var toggleIgnoreBreakpoints: () -> Void
    var removeBreakpoints: () -> Void
    var askAI: () -> Void
}

struct DocumentActionsKey: FocusedValueKey {
    typealias Value = DocumentActions
}

extension FocusedValues {
    var documentActions: DocumentActions? {
        get { self[DocumentActionsKey.self] }
        set { self[DocumentActionsKey.self] = newValue }
    }
}

struct DocumentView: View {
    @Binding var document: FlowDocument
    let fileURL: URL?

    @State private var editor = EditorModel()
    @State private var session = RunSession()
    @State private var chat = AIChat()
    @AppStorage(SettingsKey.theme) private var themeID = Theme.classic.id
    @AppStorage(SettingsKey.runSpeed) private var savedSpeed = 1.0
    @AppStorage(SettingsKey.maxStack) private var maxStack = 5000
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.compactLayout) private var compact = false
    @AppStorage(SettingsKey.showsInspector) private var savedShowsInspector = true
    @AppStorage(SettingsKey.showsSidebar) private var showsSidebar = true
    @AppStorage(SettingsKey.topPanel) private var savedTopPanel = PanelTab.console.rawValue
    @AppStorage(SettingsKey.bottomPanel) private var savedBottomPanel = PanelTab.variables.rawValue
    @AppStorage(SettingsKey.showsBottomPanel) private var savedShowsBottomPanel = true
    @AppStorage(SettingsKey.zoom) private var savedZoom = 1.0
    @AppStorage(SettingsKey.ignoreBreakpoints) private var savedIgnoreBreakpoints = false
    @AppStorage(SettingsKey.aiMode) private var aiMode = AIMode.auto.rawValue
    /// Set when a program has been running at full speed for a while without asking for input.
    @State private var runsLong = false

    var theme: Theme { Theme.named(themeID) }

    var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { showsSidebar ? .all : .detailOnly },
                set: { showsSidebar = $0 != .detailOnly })
    }
    var locked: Bool { session.state.isActive }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            // The AI assistant; the functions live in the toolbar.
            AIPanel(chat: chat, session: session, context: toolContext)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            FlowchartView(program: $document.program, editor: editor, session: session)
                .overlay(alignment: .bottomTrailing) { zoomControls }
                .overlay(alignment: .bottom) {
                    errorBanner
                    longRunBanner
                }
                .navigationTitle(editor.currentFunction(in: document.program).map(\.isMain) == false
                                 ? editor.currentFunction(in: document.program)!.name : "")
        }
        .inspector(isPresented: $editor.showsInspector) {
            InspectorPanel(program: document.program, editor: editor, session: session)
                .inspectorColumnWidth(min: 280, ideal: 360, max: 640)
        }
        .environment(\.aiActions, AIActions(isAvailable: OpenRouterAccount.shared.status == .signedIn, ask: askAI))
        .toolbar { toolbar }
        .background { functionKeys }
        .focusedSceneValue(\.documentActions, actions)
        .sheet(item: $editor.editingStatement) { statement in
            ShapeEditorSheet(statement: statement, function: editor.currentFunction(in: document.program), theme: theme) {
                editor.replace($0, in: $document.program)
            }
        }
        .sheet(item: $editor.editingFunction) { function in
            FunctionEditorSheet(function: function, isNew: false,
                                existingNames: document.program.functions.filter { $0.id != function.id }.map(\.name)) {
                editor.updateFunction($0, in: $document.program)
            }
        }
        .sheet(isPresented: $editor.isAddingFunction) {
            FunctionEditorSheet(function: Function(name: ""), isNew: true,
                                existingNames: document.program.functions.map(\.name)) {
                editor.addFunction($0, to: $document.program)
            }
        }
        .sheet(isPresented: $editor.showsProgramInfo) {
            ProgramInfoSheet(program: $document.program)
        }
        // Dismissed only through its buttons, which answer the program.
        .alert(fileAlertTitle, isPresented: Binding(get: { session.fileRequest != nil }, set: { _ in }),
               presenting: session.fileRequest) { _ in
            Button("Block", role: .cancel) { session.answerFileAccess(false) }
            Button("Allow") { session.answerFileAccess(true) }
        } message: { request in
            fileAlertMessage(request)
        }
        .onAppear {
            session.speed = savedSpeed
            session.ignoreBreakpoints = savedIgnoreBreakpoints
            editor.showsInspector = savedShowsInspector
            editor.topPanel = PanelTab(rawValue: savedTopPanel) ?? .console
            editor.bottomPanel = PanelTab(rawValue: savedBottomPanel) ?? .variables
            editor.showsBottomPanel = savedShowsBottomPanel
            editor.zoom = min(EditorModel.maxZoom, max(EditorModel.minZoom, savedZoom))
            if editor.functionID == nil { editor.functionID = document.program.main?.id }
        }
        .onDisappear {
            // A closed window must not keep a program running, or the assistant working, in the background.
            session.stop()
            chat.stop()
        }
        .onChange(of: session.speed) { _, speed in savedSpeed = speed }
        .onChange(of: session.ignoreBreakpoints) { _, ignore in savedIgnoreBreakpoints = ignore }
        .onChange(of: editor.showsInspector) { _, shows in savedShowsInspector = shows }
        .onChange(of: editor.topPanel) { _, tab in savedTopPanel = tab.rawValue }
        .onChange(of: editor.bottomPanel) { _, tab in savedBottomPanel = tab.rawValue }
        .onChange(of: editor.showsBottomPanel) { _, shows in savedShowsBottomPanel = shows }
        .onChange(of: editor.zoom) { _, zoom in savedZoom = zoom }
        .task(id: session.state) {
            // A program that keeps running at full speed without asking anything is probably stuck.
            runsLong = false
            guard session.state == .running else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled, session.state == .running, session.speed >= 0.98 {
                withAnimation(.snappy) { runsLong = true }
            }
        }
        .onChange(of: session.state) { _, state in
            switch state {
            case .waitingForInput: editor.show(.console)
            case .failed: editor.show(.console)
            default: break
            }
        }
    }

    // MARK: Running

    var baseDirectory: URL? { fileURL?.deletingLastPathComponent() }

    var fileAlertTitle: Text {
        switch session.fileRequest?.mode {
        case .write?: Text("Allow the program to overwrite this file?")
        case .append?: Text("Allow the program to add lines to this file?")
        case .read?, nil: Text("Allow the program to read this file?")
        }
    }

    func fileAlertMessage(_ request: FileRequest) -> Text {
        if fileURL == nil {
            return Text("“\(request.path)”: this flowchart isn't saved yet, so every file needs your permission. Allow only if you trust whoever made it.")
        }
        return Text("“\(request.path)” is outside the flowchart's folder. Allow only if you trust whoever made this flowchart.")
    }

    func run() {
        if session.state == .paused {
            session.run(document.program, baseDirectory: baseDirectory)
            return
        }
        guard !session.state.isActive else { return }
        chat.runStarted()
        if let error = Interpreter.check(document.program) {
            reveal(error)
        }
        editor.show(usesTurtle ? .turtle : .console)
        session.run(document.program, baseDirectory: baseDirectory, maxDepth: maxStack)
    }

    var usesTurtle: Bool {
        document.program.functions.contains { $0.body.flattened.contains { $0.category == .turtle } }
    }

    func step() {
        if !session.state.isActive {
            chat.runStarted()
            editor.show(usesTurtle ? .turtle : .console)
        }
        session.step(document.program, baseDirectory: baseDirectory, maxDepth: maxStack)
    }

    func toolContext() -> ToolContext {
        ToolContext(program: $document.program, editor: editor, locked: session.state.isActive)
    }

    var mode: AIMode { AIMode(rawValue: aiMode) ?? .auto }

    /// Shows the assistant and sends it a request from the chart, the banners or the menus.
    func askAI(_ request: AIRequest) {
        showsSidebar = true
        chat.ask(request, context: toolContext)
    }

    /// Stops a program that seems stuck and asks the assistant why.
    func askAboutLongRun() {
        let place = (session.currentStatement, session.currentFunctionName)
        session.stop()
        askAI(.endlessLoop(place.0, function: place.1))
    }

    /// Jumps to the function and shape where a problem is.
    func reveal(_ error: RuntimeError) {
        if let name = error.functionName, let function = document.program.function(named: name) {
            editor.functionID = function.id
        }
        editor.selection = error.statementID
    }

    // MARK: Pieces

    var actions: DocumentActions {
        DocumentActions(
            run: run,
            step: step,
            pause: { session.pause() },
            stop: { session.stop() },
            isRunning: session.state.isActive,
            isPaused: session.state == .paused,
            hasSelection: editor.selection != nil,
            cut: { if let id = editor.selection, !locked { editor.cut(id, in: $document.program) } },
            copy: { if let id = editor.selection { editor.copy(id, in: document.program) } },
            paste: { if !locked { editor.paste(in: $document.program) } },
            delete: { if let id = editor.selection, !locked { editor.delete(id, in: $document.program) } },
            duplicate: { if let id = editor.selection, !locked { editor.duplicate(id, in: $document.program) } },
            zoomIn: { withAnimation(.snappy) { editor.zoomIn() } },
            zoomOut: { withAnimation(.snappy) { editor.zoomOut() } },
            resetZoom: { withAnimation(.snappy) { editor.resetZoom() } },
            showPanel: { editor.show($0) },
            toggleInspector: { editor.showsInspector.toggle() },
            toggleBottomPanel: { editor.showsBottomPanel.toggle() },
            showsBottomPanel: editor.showsBottomPanel,
            addFunction: { editor.isAddingFunction = true },
            programInfo: { editor.showsProgramInfo = true },
            export: { exportChart($0) },
            print: printChart,
            setSpeed: { session.speed = $0 },
            speed: session.speed,
            ignoreBreakpoints: session.ignoreBreakpoints,
            toggleIgnoreBreakpoints: { session.ignoreBreakpoints.toggle() },
            removeBreakpoints: removeBreakpoints,
            askAI: {
                showsSidebar = true
                chat.requestFocus()
            }
        )
    }

    func removeBreakpoints() {
        for index in document.program.functions.indices {
            for statement in document.program.functions[index].body.flattened where statement.category == .breakpoint {
                document.program.functions[index].body.removeStatement(withID: statement.id)
            }
        }
    }

    func exportChart(_ format: ChartExporter.Format) {
        guard let function = editor.currentFunction(in: document.program) else { return }
        let base = document.program.name.isEmpty ? (fileURL?.deletingPathExtension().lastPathComponent ?? "Flowchart") : document.program.name
        let name = function.isMain ? base : "\(base) - \(function.name)"
        ChartExporter.export(function, format: format, theme: theme, fontSize: fontSize, compact: compact, suggestedName: name)
    }

    func printChart() {
        guard let function = editor.currentFunction(in: document.program) else { return }
        ChartExporter.print(function, theme: theme, fontSize: fontSize, compact: compact)
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                run()
            } label: {
                Label(session.state == .paused ? "Continue" : "Run", systemImage: "play.fill")
            }
            .help("Run the program (⌘R, F5)")
            .disabled(session.state == .running || session.state == .waitingForInput || session.state == .waitingForPermission)

            Button("Step", systemImage: "forward.frame.fill", action: step)
                .help("Run one shape at a time (⌘', F6)")
                .disabled(session.state == .running || session.state == .waitingForInput || session.state == .waitingForPermission)

            Button("Pause", systemImage: "pause.fill") { session.pause() }
                .help("Pause (⌥⌘P, F7)")
                .disabled(session.state != .running)

            Button("Stop", systemImage: "stop.fill") { session.stop() }
                .help("Stop (⌘., F8)")
                .disabled(!session.state.isActive)
        }

        ToolbarItem(placement: .navigation) {
            SpeedControl(session: session)
        }

        ToolbarItemGroup(placement: .principal) {
            StatusChip(session: session)
            FunctionMenu(program: $document.program, editor: editor, locked: locked)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(Theme.all) { theme in
                    Toggle(isOn: Binding(get: { themeID == theme.id }, set: { if $0 { themeID = theme.id } })) {
                        Text(theme.name)
                    }
                }
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .help("Color scheme")

            Menu {
                Button("PNG Image…") { exportChart(.png) }
                Button("PDF Document…") { exportChart(.pdf) }
                Button("SVG Vector…") { exportChart(.svg) }
                Divider()
                Button("Print…", action: printChart)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export or print the flowchart")

            Button("Panels", systemImage: "sidebar.trailing") { editor.showsInspector.toggle() }
                .help("Show or hide console, variables, turtle and code")
        }
    }

    var zoomControls: some View {
        HStack(spacing: 2) {
            Button("Zoom Out", systemImage: "minus") { withAnimation(.snappy) { editor.zoomOut() } }
            Button {
                withAnimation(.snappy) { editor.resetZoom() }
            } label: {
                Text("\(Int((editor.zoom * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 44)
            }
            .help("Actual size")
            Button("Zoom In", systemImage: "plus") { withAnimation(.snappy) { editor.zoomIn() } }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .padding(14)
    }

    @ViewBuilder
    var errorBanner: some View {
        if session.state == .failed, let error = session.error {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.functionName.map { String(localized: "Error in \($0)") } ?? String(localized: "Error"))
                        .font(.headline)
                    Text(ErrorText.message(error))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if error.statementID != nil {
                    Button("Show") { reveal(error) }
                        .buttonStyle(.glass)
                }
                if OpenRouterAccount.shared.status == .signedIn && error != chat.lastFixedError {
                    Button(mode == .study ? "Get a Hint" : "Fix with AI",
                           systemImage: mode == .study ? "graduationcap.fill" : "sparkles") { askAI(.fixError(error)) }
                        .buttonStyle(.glassProminent)
                        .tint(mode.color)
                        .disabled(chat.isWorking)
                }
            }
            .padding(14)
            .frame(maxWidth: 560)
            .glassEffect(.regular.tint(.red.opacity(0.15)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 64)
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    var longRunBanner: some View {
        if runsLong, session.state == .running {
            HStack(spacing: 12) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .symbolEffect(.rotate, options: .repeating)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Still running")
                        .font(.headline)
                    Text("The program has been running for a while without asking anything. It may be stuck in an endless loop.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Stop") { session.stop() }
                    .buttonStyle(.glass)
                if OpenRouterAccount.shared.status == .signedIn {
                    Button("Ask AI", systemImage: mode == .study ? "graduationcap.fill" : "sparkles", action: askAboutLongRun)
                        .buttonStyle(.glassProminent)
                        .tint(mode.color)
                        .disabled(chat.isWorking)
                        .help("Stop the program and ask the assistant why it doesn't end")
                }
            }
            .padding(14)
            .frame(maxWidth: 560)
            .glassEffect(.regular.tint(.orange.opacity(0.15)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 64)
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Flowgorithm's function keys, on top of the Mac shortcuts in the Run menu.
    var functionKeys: some View {
        Group {
            Button("", action: run).keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF708)!)), modifiers: [])
            Button("", action: step).keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF709)!)), modifiers: [])
            Button("") { session.pause() }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF70A)!)), modifiers: [])
            Button("") { session.stop() }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF70B)!)), modifiers: [])
            Button("") { editor.show(.variables) }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF70C)!)), modifiers: [])
            Button("") { editor.show(.console) }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF70D)!)), modifiers: [])
            Button("") { editor.show(.turtle) }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF70E)!)), modifiers: [])
            Button("") { editor.show(.code) }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0xF70F)!)), modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Shows what the program is doing, as a small glass capsule in the toolbar.
struct StatusChip: View {
    var session: RunSession

    var color: Color {
        switch session.state {
        case .idle: .secondary
        case .running: .green
        case .paused, .waitingForInput, .waitingForPermission: .orange
        case .finished: .blue
        case .failed: .red
        case .stopped: .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(session.state == .running ? 0.8 : 0), radius: 4)
            Text(session.statusText)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minWidth: 150)
    }
}

/// Run speed, from one shape every second and a half up to full speed.
struct SpeedControl: View {
    @Bindable var session: RunSession

    var body: some View {
        Menu {
            Picker("Speed", selection: $session.speed) {
                Text("Full speed").tag(1.0)
                Text("Fast").tag(0.75)
                Text("Medium").tag(0.5)
                Text("Slow").tag(0.25)
                Text("Very slow").tag(0.0)
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Ignore breakpoints", isOn: $session.ignoreBreakpoints)
        } label: {
            Label("Speed", systemImage: session.speed >= 0.98 ? "hare.fill" : session.speed < 0.3 ? "tortoise.fill" : "gauge.with.dots.needle.50percent")
        }
        .help("Run speed")
    }
}
