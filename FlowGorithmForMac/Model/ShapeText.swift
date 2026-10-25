import FlowCore
import Foundation

/// Localized names and labels for shapes, types and colors.
enum ShapeText {
    static func typeName(_ type: DataType) -> String {
        switch type {
        case .integer: String(localized: "Integer")
        case .real: String(localized: "Real")
        case .string: String(localized: "String")
        case .boolean: String(localized: "Boolean")
        }
    }

    static func colorName(_ color: PenColor) -> String {
        switch color {
        case .black: String(localized: "Black")
        case .gray: String(localized: "Gray")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .teal: String(localized: "Teal")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .brown: String(localized: "Brown")
        }
    }

    static func name(_ template: StatementTemplate) -> String {
        switch template {
        case .input: String(localized: "Input")
        case .output: String(localized: "Output")
        case .declare: String(localized: "Declare")
        case .assign: String(localized: "Assign")
        case .if: String(localized: "If")
        case .call: String(localized: "Call")
        case .while: String(localized: "While")
        case .for: String(localized: "For")
        case .do: String(localized: "Do")
        case .comment: String(localized: "Comment")
        case .breakpoint: String(localized: "Breakpoint")
        case .open: String(localized: "Open")
        case .close: String(localized: "Close")
        case .read: String(localized: "Read")
        case .write: String(localized: "Write")
        case .forward: String(localized: "Forward")
        case .turn: String(localized: "Turn")
        case .home: String(localized: "Home")
        case .clear: String(localized: "Clear")
        case .pen: String(localized: "Pen")
        }
    }

    static func help(_ template: StatementTemplate) -> String {
        switch template {
        case .input: String(localized: "Reads a value from the keyboard and stores it in a variable.")
        case .output: String(localized: "Evaluates an expression and shows the result in the console.")
        case .declare: String(localized: "Creates variables or arrays. Separate several names with commas.")
        case .assign: String(localized: "Stores the result of an expression in a variable.")
        case .if: String(localized: "Checks a Boolean expression and runs the True or the False branch.")
        case .call: String(localized: "Runs a function, passing it arguments.")
        case .while: String(localized: "Repeats its body while the expression is true. The check happens before each run.")
        case .for: String(localized: "Counts a variable through a range of values, running the body each time.")
        case .do: String(localized: "Runs its body, then repeats while the expression is true. The body runs at least once.")
        case .comment: String(localized: "A note for whoever reads the flowchart. It doesn't affect the program.")
        case .breakpoint: String(localized: "Pauses the program here, always or only when a condition is true.")
        case .open: String(localized: "Opens a text file for reading or writing. Relative paths start from the flowchart's folder.")
        case .close: String(localized: "Closes the open file.")
        case .read: String(localized: "Reads the next line of the open file into a variable.")
        case .write: String(localized: "Writes a line to the open file.")
        case .forward: String(localized: "Moves the turtle forward, drawing a line if the pen is down.")
        case .turn: String(localized: "Rotates the turtle left or right by a number of degrees.")
        case .home: String(localized: "Moves the turtle back to the center, facing up.")
        case .clear: String(localized: "Erases the drawing and moves the turtle home.")
        case .pen: String(localized: "Changes the color of the lines the turtle draws.")
        }
    }

    static func symbol(_ template: StatementTemplate) -> String {
        switch template {
        case .input: "keyboard"
        case .output: "text.bubble"
        case .declare: "shippingbox"
        case .assign: "equal.square"
        case .if: "arrow.triangle.branch"
        case .call: "function"
        case .while: "arrow.trianglehead.2.clockwise"
        case .for: "number"
        case .do: "repeat"
        case .comment: "text.quote"
        case .breakpoint: "pause.octagon"
        case .open: "folder"
        case .close: "xmark.bin"
        case .read: "doc.text"
        case .write: "square.and.pencil"
        case .forward: "arrow.up"
        case .turn: "arrow.clockwise"
        case .home: "house"
        case .clear: "eraser"
        case .pen: "paintbrush.pointed"
        }
    }

    /// The text drawn inside a shape. Empty shapes show their name, like in Flowgorithm.
    static func label(_ statement: Statement) -> String {
        if statement.isIncomplete, let template = statement.template, template != .declare {
            return name(template)
        }
        switch statement.kind {
        case .declare(let s):
            if s.nameList.isEmpty { return name(.declare) }
            let names = s.isArray ? s.nameList.map { "\($0)[\(s.size)]" } : s.nameList
            let type = s.isArray ? String(localized: "\(typeName(s.type)) Array") : typeName(s.type)
            let list = names.joined(separator: ", ")
            return String(localized: "shape.declare", defaultValue: "\(type) \(list)",
                          comment: "Declare shape label: type, then variable names")
        case .assign(let s):
            return "\(s.variable) = \(s.expression)"
        case .input(let s):
            return String(localized: "Input \(s.variable)")
        case .output(let s):
            return String(localized: "Output \(s.expression)")
        case .if(let s):
            return s.expression
        case .while(let s):
            return s.expression
        case .do(let s):
            return s.expression
        case .for(let s):
            let step = s.step.trimmingCharacters(in: .whitespaces)
            let base = s.direction == .increasing
                ? String(localized: "\(s.variable) = \(s.start) to \(s.end)")
                : String(localized: "\(s.variable) = \(s.start) down to \(s.end)")
            return step.isEmpty || step == "1" ? base : base + " " + String(localized: "step \(step)")
        case .call(let s):
            return String(localized: "Call \(s.expression)")
        case .comment(let s):
            return s.text.isEmpty ? name(.comment) : s.text
        case .breakpoint(let s):
            let condition = s.expression.trimmingCharacters(in: .whitespaces)
            return s.always || condition.isEmpty ? name(.breakpoint) : condition
        case .open(let s):
            return switch s.mode {
            case .read: String(localized: "Open \(s.expression) for reading")
            case .write: String(localized: "Open \(s.expression) for writing")
            case .append: String(localized: "Open \(s.expression) for appending")
            }
        case .close:
            return String(localized: "Close file")
        case .read(let s):
            return String(localized: "Read \(s.variable)")
        case .write(let s):
            return String(localized: "Write \(s.expression)")
        case .turn(let s):
            return s.direction == .left
                ? String(localized: "Turn left \(s.expression)°")
                : String(localized: "Turn right \(s.expression)°")
        case .forward(let s):
            return s.penDown ? String(localized: "Forward \(s.expression)") : String(localized: "Move \(s.expression)")
        case .home:
            return name(.home)
        case .clear:
            return name(.clear)
        case .pen(let s):
            return String(localized: "Pen \(colorName(s.color))")
        case .unknown:
            return String(localized: "Unknown shape")
        }
    }

    static func functionHeader(_ function: Function) -> String {
        if function.isMain { return String(localized: "Main") }
        let params = function.parameters.map { "\(typeName($0.type))\($0.isArray ? "[]" : "") \($0.name)" }
        return "\(function.name)(\(params.joined(separator: ", ")))"
    }

    static func functionFooter(_ function: Function) -> String {
        if function.returnType != nil, !function.returnVariable.isEmpty {
            return String(localized: "Return \(function.returnVariable)")
        }
        return String(localized: "End")
    }
}
