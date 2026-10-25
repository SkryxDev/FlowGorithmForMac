import Foundation
@testable import FlowCore

struct RunResult {
    var output: String
    var error: RuntimeError?
    var variables: VariablesSnapshot
    var turtle: [TurtleCommand]
}

/// Runs a program to completion, answering input requests from `inputs` in order.
func run(_ program: Program, inputs: [String] = [], baseDirectory: URL? = nil) async -> RunResult {
    let controller = ExecutionController()
    let interpreter = Interpreter(program: program, controller: controller, baseDirectory: baseDirectory)
    var remaining = inputs
    var output = ""
    var error: RuntimeError?
    var variables = VariablesSnapshot()
    var turtle: [TurtleCommand] = []

    async let done: Void = interpreter.run()
    for await event in controller.events {
        switch event {
        case .output(let text, let newline):
            output += text + (newline ? "\n" : "")
        case .inputRequested:
            if remaining.isEmpty {
                controller.stop()
            } else {
                controller.provideInput(remaining.removeFirst())
            }
        case .turtle(let command):
            turtle.append(command)
        case .failed(let e, let v):
            error = e
            variables = v
        case .finished(let v), .stopped(let v):
            variables = v
        default:
            break
        }
    }
    await done
    return RunResult(output: output, error: error, variables: variables, turtle: turtle)
}

func program(_ body: [Statement], functions: [Function] = []) -> Program {
    Program(functions: [Function(name: "Main", body: body)] + functions)
}

func declare(_ names: String, _ type: DataType, array size: String? = nil) -> Statement {
    Statement(.declare(.init(names: names, type: type, isArray: size != nil, size: size ?? "")))
}

func assign(_ variable: String, _ expression: String) -> Statement {
    Statement(.assign(.init(variable: variable, expression: expression)))
}

func output(_ expression: String, newline: Bool = true) -> Statement {
    Statement(.output(.init(expression: expression, newline: newline)))
}

func input(_ variable: String) -> Statement {
    Statement(.input(.init(variable: variable)))
}
