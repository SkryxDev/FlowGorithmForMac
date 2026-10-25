import FlowCore
import SwiftUI

struct ConsoleEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case output, input, error, info, warning
    }

    let id: Int
    var kind: Kind
    var text: String
}

struct TurtleSegment: Hashable {
    var from: CGPoint
    var to: CGPoint
    var color: PenColor
}

/// Runs a program for one window and keeps everything the panels show: console, variables, turtle.
@Observable
final class RunSession {
    enum State: Equatable {
        case idle, running, paused, waitingForInput, finished, failed, stopped

        var isActive: Bool { self == .running || self == .paused || self == .waitingForInput }
    }

    var state: State = .idle
    var console: [ConsoleEntry] = []
    var variables = VariablesSnapshot()
    var segments: [TurtleSegment] = []
    var turtlePosition = CGPoint.zero
    var turtleHeading = 90.0
    var currentStatement: Statement.ID?
    var currentFunctionName: String?
    var error: RuntimeError?
    var inputRequest: (variable: String, type: DataType)?
    var ignoreBreakpoints = false {
        didSet { controller?.setIgnoreBreakpoints(ignoreBreakpoints) }
    }

    /// 0 = slowest, 1 = full speed.
    var speed: Double = 1 {
        didSet { controller?.setDelay(Self.delay(for: speed)) }
    }

    /// Bumped whenever the console changes, so the view can scroll to the end.
    private(set) var consoleRevision = 0
    private var controller: ExecutionController?
    private var eventTask: Task<Void, Never>?
    private var nextEntryID = 0
    private var outputLineOpen = false
    private static let maxConsoleEntries = 4000

    static func delay(for speed: Double) -> Duration {
        if speed >= 0.98 { return .zero }
        // From about 1.5 s per shape down to 15 ms, on a curve that feels even to the eye.
        let seconds = 1.5 * pow(0.01, speed)
        return .milliseconds(Int(seconds * 1000))
    }

    var statusText: LocalizedStringKey {
        switch state {
        case .idle: "Ready"
        case .running: "Running…"
        case .paused: "Paused"
        case .waitingForInput: "Waiting for input"
        case .finished: "Finished"
        case .failed: "Error"
        case .stopped: "Stopped"
        }
    }

    // MARK: Control

    func run(_ program: Program, baseDirectory: URL?, stepping: Bool = false, maxDepth: Int = 5000) {
        if state.isActive {
            if stepping { controller?.step() } else { controller?.resume() }
            return
        }
        reset()
        let controller = ExecutionController(delay: Self.delay(for: speed), startPaused: stepping, ignoreBreakpoints: ignoreBreakpoints)
        self.controller = controller
        state = .running
        let interpreter = Interpreter(program: program, controller: controller, baseDirectory: baseDirectory, maxDepth: maxDepth)
        eventTask = Task { [weak self] in
            async let finished: Void = interpreter.run()
            for await event in controller.events {
                self?.handle(event)
            }
            await finished
        }
    }

    func pause() {
        guard state == .running else { return }
        controller?.pause()
    }

    func step(_ program: Program, baseDirectory: URL?, maxDepth: Int = 5000) {
        if state.isActive {
            controller?.step()
        } else {
            run(program, baseDirectory: baseDirectory, stepping: true, maxDepth: maxDepth)
        }
    }

    func stop() {
        controller?.stop()
    }

    /// Values pasted as several lines; each answers the next input request.
    private var pendingInputs: [String] = []

    func submitInput(_ text: String) {
        guard inputRequest != nil else { return }
        var lines = text.components(separatedBy: .newlines)
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        let first = lines.isEmpty ? "" : lines.removeFirst()
        pendingInputs += lines
        append(.input, first.isEmpty ? " " : first)
        inputRequest = nil
        state = .running
        controller?.provideInput(first)
    }

    func clearConsole() {
        console.removeAll()
        outputLineOpen = false
        consoleRevision += 1
    }

    func clearTurtle() {
        segments.removeAll()
        turtlePosition = .zero
        turtleHeading = 90
    }

    private func reset() {
        clearConsole()
        clearTurtle()
        variables = VariablesSnapshot()
        currentStatement = nil
        currentFunctionName = nil
        error = nil
        inputRequest = nil
        pendingInputs = []
    }

    // MARK: Events

    private func handle(_ event: ExecutionEvent) {
        switch event {
        case .output(let text, let newline):
            if outputLineOpen, let last = console.indices.last, console[last].kind == .output {
                console[last].text += text
                consoleRevision += 1
            } else {
                append(.output, text)
            }
            outputLineOpen = !newline

        case .inputRequested(let variable, let type, let statement):
            currentStatement = statement
            inputRequest = (variable, type)
            if !pendingInputs.isEmpty {
                submitInput(pendingInputs.removeFirst())
                return
            }
            state = .waitingForInput
            outputLineOpen = false

        case .inputRejected(let text, let type):
            append(.warning, String(localized: "“\(text)” isn't a valid \(ShapeText.typeName(type)). Try again."))
            inputRequest = inputRequest ?? ("", type)
            state = .waitingForInput

        case .highlight(let id, let function):
            currentStatement = id
            currentFunctionName = function

        case .paused(let id, let function, let reason, let snapshot):
            currentStatement = id
            currentFunctionName = function
            variables = snapshot
            state = .paused
            if reason == .breakpoint {
                append(.info, String(localized: "Breakpoint: execution paused."))
            }

        case .resumed:
            if state == .paused { state = .running }

        case .variables(let snapshot):
            variables = snapshot

        case .turtle(let command):
            switch command {
            case .line(let from, let to, let color, let drawn):
                if drawn {
                    segments.append(TurtleSegment(from: CGPoint(x: from.x, y: from.y), to: CGPoint(x: to.x, y: to.y), color: color))
                }
            case .turtle(let position, let heading):
                turtlePosition = CGPoint(x: position.x, y: position.y)
                turtleHeading = heading
            case .clear:
                segments.removeAll()
            }

        case .finished(let snapshot):
            variables = snapshot
            currentStatement = nil
            state = .finished
            controller = nil

        case .failed(let error, let snapshot):
            variables = snapshot
            self.error = error
            currentStatement = error.statementID
            currentFunctionName = error.functionName
            append(.error, ErrorText.message(error))
            state = .failed
            inputRequest = nil
            controller = nil

        case .stopped(let snapshot):
            variables = snapshot
            currentStatement = nil
            inputRequest = nil
            append(.info, String(localized: "Program stopped."))
            state = .stopped
            controller = nil
        }
    }

    private func append(_ kind: ConsoleEntry.Kind, _ text: String) {
        console.append(ConsoleEntry(id: nextEntryID, kind: kind, text: text))
        nextEntryID += 1
        if console.count > Self.maxConsoleEntries {
            console.removeFirst(console.count - Self.maxConsoleEntries)
        }
        if kind != .output { outputLineOpen = false }
        consoleRevision += 1
    }
}
