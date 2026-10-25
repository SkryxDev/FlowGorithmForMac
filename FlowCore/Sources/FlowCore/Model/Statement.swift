import Foundation

/// One shape of a flowchart.
public struct Statement: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: Kind

    public init(id: UUID = UUID(), _ kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public enum Kind: Hashable, Sendable {
        case declare(Declare)
        case assign(Assign)
        case input(Input)
        case output(Output)
        case `if`(If)
        case `while`(While)
        case `do`(DoLoop)
        case `for`(ForLoop)
        case call(Call)
        case comment(Comment)
        case breakpoint(Breakpoint)
        case open(OpenFile)
        case close(CloseFile)
        case read(ReadFile)
        case write(WriteFile)
        case turn(Turn)
        case forward(Forward)
        case home
        case clear
        case pen(Pen)
        /// An element this version doesn't understand, kept verbatim so saving doesn't lose it.
        case unknown(xml: String)
    }

    public struct Declare: Hashable, Sendable {
        /// Comma-separated variable names, as typed by the user.
        public var names: String
        public var type: DataType
        public var isArray: Bool
        public var size: String

        public init(names: String = "", type: DataType = .integer, isArray: Bool = false, size: String = "") {
            self.names = names
            self.type = type
            self.isArray = isArray
            self.size = size
        }

        public var nameList: [String] {
            names.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    public struct Assign: Hashable, Sendable {
        public var variable: String
        public var expression: String
        public init(variable: String = "", expression: String = "") {
            self.variable = variable
            self.expression = expression
        }
    }

    public struct Input: Hashable, Sendable {
        public var variable: String
        public init(variable: String = "") { self.variable = variable }
    }

    public struct Output: Hashable, Sendable {
        public var expression: String
        public var newline: Bool
        public init(expression: String = "", newline: Bool = true) {
            self.expression = expression
            self.newline = newline
        }
    }

    public struct If: Hashable, Sendable {
        public var expression: String
        public var thenBody: [Statement]
        public var elseBody: [Statement]
        public init(expression: String = "", thenBody: [Statement] = [], elseBody: [Statement] = []) {
            self.expression = expression
            self.thenBody = thenBody
            self.elseBody = elseBody
        }
    }

    public struct While: Hashable, Sendable {
        public var expression: String
        public var body: [Statement]
        public init(expression: String = "", body: [Statement] = []) {
            self.expression = expression
            self.body = body
        }
    }

    public struct DoLoop: Hashable, Sendable {
        public var expression: String
        public var body: [Statement]
        public init(expression: String = "", body: [Statement] = []) {
            self.expression = expression
            self.body = body
        }
    }

    public struct ForLoop: Hashable, Sendable {
        public var variable: String
        public var start: String
        public var end: String
        public var direction: ForDirection
        public var step: String
        public var body: [Statement]
        public init(variable: String = "", start: String = "", end: String = "",
                    direction: ForDirection = .increasing, step: String = "1", body: [Statement] = []) {
            self.variable = variable
            self.start = start
            self.end = end
            self.direction = direction
            self.step = step
            self.body = body
        }
    }

    public struct Call: Hashable, Sendable {
        public var expression: String
        public init(expression: String = "") { self.expression = expression }
    }

    public struct Comment: Hashable, Sendable {
        public var text: String
        public init(text: String = "") { self.text = text }
    }

    public struct Breakpoint: Hashable, Sendable {
        public var expression: String
        public var always: Bool
        public init(expression: String = "", always: Bool = true) {
            self.expression = expression
            self.always = always
        }
    }

    public struct OpenFile: Hashable, Sendable {
        public var expression: String
        public var mode: FileMode
        public init(expression: String = "", mode: FileMode = .read) {
            self.expression = expression
            self.mode = mode
        }
    }

    public struct CloseFile: Hashable, Sendable {
        public var mode: FileMode
        public init(mode: FileMode = .read) { self.mode = mode }
    }

    public struct ReadFile: Hashable, Sendable {
        public var variable: String
        public init(variable: String = "") { self.variable = variable }
    }

    public struct WriteFile: Hashable, Sendable {
        public var expression: String
        public init(expression: String = "") { self.expression = expression }
    }

    public struct Turn: Hashable, Sendable {
        public var expression: String
        public var direction: TurnDirection
        public init(expression: String = "", direction: TurnDirection = .right) {
            self.expression = expression
            self.direction = direction
        }
    }

    public struct Forward: Hashable, Sendable {
        public var expression: String
        public var penDown: Bool
        public init(expression: String = "", penDown: Bool = true) {
            self.expression = expression
            self.penDown = penDown
        }
    }

    public struct Pen: Hashable, Sendable {
        public var color: PenColor
        public init(color: PenColor = .black) { self.color = color }
    }
}

/// Which family of shape a statement belongs to; drives colors and grouping in the UI.
public enum ShapeCategory: String, CaseIterable, Sendable, Hashable {
    case terminal, declare, assign, input, output, selection, loop, call, comment, breakpoint, file, turtle, unknown
}

extension Statement {
    public var category: ShapeCategory {
        switch kind {
        case .declare: .declare
        case .assign: .assign
        case .input: .input
        case .output: .output
        case .if: .selection
        case .while, .do, .for: .loop
        case .call: .call
        case .comment: .comment
        case .breakpoint: .breakpoint
        case .open, .close, .read, .write: .file
        case .turn, .forward, .home, .clear, .pen: .turtle
        case .unknown: .unknown
        }
    }

    /// The nested blocks of a compound statement (then/else, loop bodies), in a stable order.
    public var blocks: [[Statement]] {
        get {
            switch kind {
            case .if(let s): [s.thenBody, s.elseBody]
            case .while(let s): [s.body]
            case .do(let s): [s.body]
            case .for(let s): [s.body]
            default: []
            }
        }
        set {
            switch kind {
            case .if(var s):
                s.thenBody = newValue[0]
                s.elseBody = newValue[1]
                kind = .if(s)
            case .while(var s):
                s.body = newValue[0]
                kind = .while(s)
            case .do(var s):
                s.body = newValue[0]
                kind = .do(s)
            case .for(var s):
                s.body = newValue[0]
                kind = .for(s)
            default:
                break
            }
        }
    }

    /// True when a required field is still empty, so the editor can grey the shape out.
    public var isIncomplete: Bool {
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch kind {
        case .declare(let s): return s.nameList.isEmpty || (s.isArray && blank(s.size))
        case .assign(let s): return blank(s.variable) || blank(s.expression)
        case .input(let s): return blank(s.variable)
        case .output(let s): return blank(s.expression)
        case .if(let s): return blank(s.expression)
        case .while(let s): return blank(s.expression)
        case .do(let s): return blank(s.expression)
        case .for(let s): return blank(s.variable) || blank(s.start) || blank(s.end)
        case .call(let s): return blank(s.expression)
        case .open(let s): return blank(s.expression)
        case .read(let s): return blank(s.variable)
        case .write(let s): return blank(s.expression)
        case .turn(let s): return blank(s.expression)
        case .forward(let s): return blank(s.expression)
        case .comment, .breakpoint, .close, .home, .clear, .pen, .unknown: return false
        }
    }

    /// A deep copy with fresh identifiers, used when pasting or duplicating.
    public func withNewIDs() -> Statement {
        var copy = self
        copy.id = UUID()
        copy.blocks = copy.blocks.map { $0.map { $0.withNewIDs() } }
        return copy
    }

    /// Creates an empty statement of the given template.
    public static func make(_ template: StatementTemplate) -> Statement {
        switch template {
        case .declare: Statement(.declare(Declare()))
        case .assign: Statement(.assign(Assign()))
        case .input: Statement(.input(Input()))
        case .output: Statement(.output(Output()))
        case .if: Statement(.if(If()))
        case .while: Statement(.while(While()))
        case .do: Statement(.do(DoLoop()))
        case .for: Statement(.for(ForLoop()))
        case .call: Statement(.call(Call()))
        case .comment: Statement(.comment(Comment()))
        case .breakpoint: Statement(.breakpoint(Breakpoint()))
        case .open: Statement(.open(OpenFile()))
        case .close: Statement(.close(CloseFile()))
        case .read: Statement(.read(ReadFile()))
        case .write: Statement(.write(WriteFile()))
        case .turn: Statement(.turn(Turn()))
        case .forward: Statement(.forward(Forward()))
        case .home: Statement(.home)
        case .clear: Statement(.clear)
        case .pen: Statement(.pen(Pen()))
        }
    }

    public var template: StatementTemplate? {
        switch kind {
        case .declare: .declare
        case .assign: .assign
        case .input: .input
        case .output: .output
        case .if: .if
        case .while: .while
        case .do: .do
        case .for: .for
        case .call: .call
        case .comment: .comment
        case .breakpoint: .breakpoint
        case .open: .open
        case .close: .close
        case .read: .read
        case .write: .write
        case .turn: .turn
        case .forward: .forward
        case .home: .home
        case .clear: .clear
        case .pen: .pen
        case .unknown: nil
        }
    }
}

/// Every kind of shape the user can insert.
public enum StatementTemplate: String, CaseIterable, Sendable, Hashable {
    case input, output, declare, assign, `if`, call, `while`, `for`, `do`, comment, breakpoint
    case open, close, read, write
    case forward, turn, home, clear, pen
}
