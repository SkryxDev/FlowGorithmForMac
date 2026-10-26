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

/// A program asking to use a file outside its flowchart's folder.
struct FileRequest: Equatable {
    var path: String
    var mode: FileMode
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
        case idle, running, paused, waitingForInput, waitingForPermission, finished, failed, stopped

        var isActive: Bool { self == .running || self == .paused || self == .waitingForInput || self == .waitingForPermission }
    }

    var state: State = .idle
    var console: [ConsoleEntry] = []
    var variables = VariablesSnapshot()
    var segments: [TurtleSegment] = []
    /// Changes whenever segments are removed rather than appended, so the turtle view knows
    /// it must redraw from scratch instead of adding only the new lines.
    private(set) var turtleGeneration = 0
    var turtlePosition = CGPoint.zero
    var turtleHeading = 90.0
    var currentStatement: Statement.ID?
    var currentFunctionName: String?
    var error: RuntimeError?
    var inputRequest: (variable: String, type: DataType)?
    var fileRequest: FileRequest?
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
    @ObservationIgnored private var nextEntryID = 0
    @ObservationIgnored private var outputLineOpen = false
    /// Characters in the last output entry while it's still open.
    @ObservationIgnored private var openLineLength = 0
    // Output and drawing arrive in bursts; they're collected here and shown about 30 times a second.
    @ObservationIgnored private var pendingOutput: [(text: String, newline: Bool)] = []
    @ObservationIgnored private var pendingSegments: [TurtleSegment] = []
    @ObservationIgnored private var pendingTurtle: (position: CGPoint, heading: Double)?
    @ObservationIgnored private var flushScheduled = false
    private static let maxSegments = 200_000
    private static let maxConsoleEntries = 4000
    /// A line printed without newlines is split into entries this long, so it can't grow
    /// until the window freezes.
    private static let maxEntryLength = 4000
    /// Only the start of a single larger output is shown.
    private static let maxOutputLength = 100_000

    /// A window closed while its program runs must not leave the program running in the background.
    isolated deinit {
        controller?.stop()
    }

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
        case .waitingForPermission: "Waiting for permission"
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
            var lastBreath = ContinuousClock.now
            for await event in controller.events {
                self?.handle(event)
                controller.didHandleEvent()
                // Buffered events don't suspend the loop, so without a pause now and then a fast
                // program would keep the main thread busy and the window would never redraw.
                if ContinuousClock.now - lastBreath > .milliseconds(12) {
                    try? await Task.sleep(for: .milliseconds(2))
                    lastBreath = .now
                }
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
    @ObservationIgnored private var pendingInputs: [String] = []

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

    /// Answers the program's request to use a file outside the flowchart's folder.
    func answerFileAccess(_ allowed: Bool) {
        guard let request = fileRequest else { return }
        fileRequest = nil
        if allowed {
            append(.info, String(localized: "Allowed access to “\(request.path)”."))
        }
        state = .running
        controller?.answerFileAccess(allowed)
    }

    func clearConsole() {
        pendingOutput.removeAll()
        console.removeAll()
        outputLineOpen = false
        openLineLength = 0
        consoleRevision += 1
    }

    func clearTurtle() {
        pendingSegments.removeAll()
        pendingTurtle = nil
        segments.removeAll()
        turtleGeneration += 1
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
        fileRequest = nil
        pendingInputs = []
    }

    // MARK: Events

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            self?.flush()
        }
    }

    /// Moves collected output and drawing into the observed properties in one go.
    private func flush() {
        flushScheduled = false
        if !pendingOutput.isEmpty {
            var entries = console
            var open = outputLineOpen
            var length = openLineLength
            for piece in pendingOutput {
                var rest = Substring(piece.text)
                if rest.utf8.count > Self.maxOutputLength {
                    rest = Substring(String(rest.prefix(Self.maxOutputLength)) + "…")
                }
                repeat {
                    if open, length < Self.maxEntryLength, let last = entries.indices.last, entries[last].kind == .output {
                        let chunk = rest.prefix(Self.maxEntryLength - length)
                        entries[last].text.append(contentsOf: chunk)
                        length += chunk.count
                        rest = rest.dropFirst(chunk.count)
                    } else {
                        let chunk = rest.prefix(Self.maxEntryLength)
                        entries.append(ConsoleEntry(id: nextEntryID, kind: .output, text: String(chunk)))
                        nextEntryID += 1
                        length = chunk.count
                        rest = rest.dropFirst(chunk.count)
                    }
                    open = true
                } while !rest.isEmpty
                open = !piece.newline
            }
            pendingOutput.removeAll(keepingCapacity: true)
            if entries.count > Self.maxConsoleEntries {
                entries.removeFirst(entries.count - Self.maxConsoleEntries)
            }
            console = entries
            outputLineOpen = open
            openLineLength = length
            consoleRevision += 1
        }
        if !pendingSegments.isEmpty {
            segments.append(contentsOf: pendingSegments)
            pendingSegments.removeAll(keepingCapacity: true)
            if segments.count > Self.maxSegments {
                segments.removeFirst(segments.count - Self.maxSegments)
                turtleGeneration += 1
            }
        }
        if let turtle = pendingTurtle {
            turtlePosition = turtle.position
            turtleHeading = turtle.heading
            pendingTurtle = nil
        }
    }

    private func handle(_ event: ExecutionEvent) {
        switch event {
        case .output(let text, let newline):
            pendingOutput.append((text, newline))
            if pendingOutput.count > Self.maxConsoleEntries { flush() } else { scheduleFlush() }
            return
        case .turtle(.line(let from, let to, let color, let drawn)):
            if drawn {
                pendingSegments.append(TurtleSegment(from: CGPoint(x: from.x, y: from.y), to: CGPoint(x: to.x, y: to.y), color: color))
                if pendingSegments.count > 20_000 { flush() } else { scheduleFlush() }
            }
            return
        case .turtle(.turtle(let position, let heading)):
            pendingTurtle = (CGPoint(x: position.x, y: position.y), heading)
            scheduleFlush()
            return
        case .variables(let snapshot):
            variables = snapshot
            return
        default:
            // Anything else must appear after the output that came before it.
            flush()
        }

        switch event {
        case .output, .variables, .turtle(.line), .turtle(.turtle):
            break

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

        case .fileAccessRequested(let path, let mode, let statement):
            currentStatement = statement
            fileRequest = FileRequest(path: path, mode: mode)
            state = .waitingForPermission

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

        case .turtle(.clear):
            pendingSegments.removeAll()
            segments.removeAll()
            turtleGeneration += 1

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
            fileRequest = nil
            controller = nil

        case .stopped(let snapshot):
            variables = snapshot
            currentStatement = nil
            inputRequest = nil
            fileRequest = nil
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
