import Foundation
import Synchronization

/// What the interpreter tells the UI while it runs.
public enum ExecutionEvent: Sendable {
    case output(String, newline: Bool)
    case inputRequested(variable: String, type: DataType, statement: Statement.ID)
    case inputRejected(text: String, type: DataType)
    /// The shape about to run; only sent when running slowly or stepping.
    case highlight(Statement.ID, function: String)
    case paused(at: Statement.ID, function: String, reason: PauseReason, variables: VariablesSnapshot)
    case resumed
    case variables(VariablesSnapshot)
    case turtle(TurtleCommand)
    case finished(VariablesSnapshot)
    case failed(RuntimeError, VariablesSnapshot)
    case stopped(VariablesSnapshot)
}

public enum PauseReason: Sendable, Hashable {
    case step, breakpoint, user
}

public enum TurtleCommand: Sendable, Hashable {
    /// A move. `drawn` is false when the pen is up.
    case line(from: TurtlePoint, to: TurtlePoint, color: PenColor, drawn: Bool)
    case turtle(position: TurtlePoint, heading: Double)
    case clear
}

public struct TurtlePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The variables of every active call, innermost last.
public struct VariablesSnapshot: Sendable, Hashable {
    public struct Frame: Sendable, Hashable, Identifiable {
        public var id: Int
        public var function: String
        public var variables: [Variable]

        public init(id: Int, function: String, variables: [Variable]) {
            self.id = id
            self.function = function
            self.variables = variables
        }
    }

    public struct Variable: Sendable, Hashable, Identifiable {
        public var id: String { name }
        public var name: String
        public var type: DataType
        /// `nil` until the variable has been assigned.
        public var value: Value?
        /// Elements for arrays (possibly only the first ones), `nil` for scalars.
        public var elements: [Value?]?
        /// The array's real length, which can exceed `elements.count`.
        public var count: Int

        public init(name: String, type: DataType, value: Value?, elements: [Value?]?, count: Int? = nil) {
            self.name = name
            self.type = type
            self.value = value
            self.elements = elements
            self.count = count ?? elements?.count ?? 0
        }
    }

    public var frames: [Frame]

    public init(frames: [Frame] = []) { self.frames = frames }
}

/// Thread-safe remote control for a running interpreter: run, pause, step, stop, speed and input.
public final class ExecutionController: Sendable {
    struct State {
        var stopRequested = false
        var pauseRequested = false
        var stepping = false
        var delay: Duration = .zero
        var ignoreBreakpoints = false
        var resume: CheckedContinuation<Void, Never>?
        var input: CheckedContinuation<String?, Never>?
    }

    private let state = Mutex(State())
    /// Events sent but not yet handled by the UI. Kept bounded so a program printing
    /// in a tight loop can't fill memory faster than the window can show it.
    private let backlog = Atomic<Int>(0)
    static let backlogLimit = 2000
    public let events: AsyncStream<ExecutionEvent>
    private let sink: AsyncStream<ExecutionEvent>.Continuation

    public init(delay: Duration = .zero, startPaused: Bool = false, ignoreBreakpoints: Bool = false) {
        (events, sink) = AsyncStream.makeStream(of: ExecutionEvent.self, bufferingPolicy: .unbounded)
        state.withLock {
            $0.delay = delay
            $0.stepping = startPaused
            $0.ignoreBreakpoints = ignoreBreakpoints
        }
    }

    // MARK: Called by the UI

    public func setDelay(_ delay: Duration) { state.withLock { $0.delay = delay } }

    public func setIgnoreBreakpoints(_ ignore: Bool) { state.withLock { $0.ignoreBreakpoints = ignore } }

    /// Pauses at the next shape.
    public func pause() { state.withLock { $0.pauseRequested = true } }

    /// Continues running after a pause.
    public func resume() {
        let continuation = state.withLock { s -> CheckedContinuation<Void, Never>? in
            s.stepping = false
            s.pauseRequested = false
            defer { s.resume = nil }
            return s.resume
        }
        continuation?.resume()
    }

    /// Runs one shape, then pauses again.
    public func step() {
        let continuation = state.withLock { s -> CheckedContinuation<Void, Never>? in
            s.stepping = true
            defer { s.resume = nil }
            return s.resume
        }
        if continuation == nil {
            // Running: pause at the next shape.
            state.withLock { $0.pauseRequested = true }
        }
        continuation?.resume()
    }

    public func stop() {
        let (resume, input) = state.withLock { s in
            s.stopRequested = true
            defer {
                s.resume = nil
                s.input = nil
            }
            return (s.resume, s.input)
        }
        resume?.resume()
        input?.resume(returning: nil)
    }

    public func provideInput(_ text: String) {
        let continuation = state.withLock { s in
            defer { s.input = nil }
            return s.input
        }
        continuation?.resume(returning: text)
    }

    public var isStopRequested: Bool { state.withLock { $0.stopRequested } }

    // MARK: Called by the interpreter

    struct Stopped: Error {}

    func emit(_ event: ExecutionEvent) {
        backlog.add(1, ordering: .relaxed)
        sink.yield(event)
    }

    /// The UI calls this after handling each event.
    public func didHandleEvent() {
        backlog.subtract(1, ordering: .relaxed)
    }

    /// True when the UI has fallen far behind; checked before every shape without suspending.
    var isBacklogged: Bool { backlog.load(ordering: .relaxed) > Self.backlogLimit }

    /// Waits while the UI is far behind.
    func waitForBacklog() async throws {
        while backlog.load(ordering: .relaxed) > Self.backlogLimit / 4 {
            if isStopRequested { throw Stopped() }
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    func finish() { sink.finish() }

    var ignoresBreakpoints: Bool { state.withLock { $0.ignoreBreakpoints } }

    enum Gate {
        case run(delay: Duration)
        case pause(PauseReason)
        case stop
    }

    /// What should happen before the next shape. Synchronous, so the common case
    /// (running at full speed) costs one lock and no suspension.
    func gate(breakpoint: Bool) -> Gate {
        state.withLock { s -> Gate in
            if s.stopRequested { return .stop }
            if breakpoint && !s.ignoreBreakpoints {
                s.pauseRequested = false
                s.stepping = false
                return .pause(.breakpoint)
            }
            if s.stepping {
                s.stepping = false
                return .pause(.step)
            }
            if s.pauseRequested {
                s.pauseRequested = false
                return .pause(.user)
            }
            return .run(delay: s.delay)
        }
    }

    /// Acts on a gate other than full-speed running: stops, sleeps or pauses.
    func pass(_ gate: Gate, at id: Statement.ID, function: String, snapshot: () -> VariablesSnapshot) async throws {
        switch gate {
        case .stop:
            throw Stopped()
        case .run(let delay):
            if delay > .zero {
                emit(.highlight(id, function: function))
                try? await Task.sleep(for: delay)
                if isStopRequested { throw Stopped() }
            }
        case .pause(let reason):
            let variables = snapshot()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let stopped = state.withLock { s -> Bool in
                    if s.stopRequested { return true }
                    s.resume = continuation
                    return false
                }
                if stopped {
                    continuation.resume()
                } else {
                    emit(.paused(at: id, function: function, reason: reason, variables: variables))
                }
            }
            if isStopRequested { throw Stopped() }
            emit(.resumed)
        }
    }

    /// Waits for the user to type a value. Throws if the program is stopped meanwhile.
    func readInput(variable: String, type: DataType, statement: Statement.ID) async throws -> String {
        let text = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let stopped = state.withLock { s -> Bool in
                if s.stopRequested { return true }
                s.input = continuation
                return false
            }
            if stopped {
                continuation.resume(returning: nil)
            } else {
                emit(.inputRequested(variable: variable, type: type, statement: statement))
            }
        }
        guard let text else { throw Stopped() }
        return text
    }
}
