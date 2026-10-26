// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation
@testable import FlowCore

struct RunResult {
    var output: String
    var error: RuntimeError?
    var variables: VariablesSnapshot
    var turtle: [TurtleCommand]
    /// Paths of the files the program asked permission for.
    var fileRequests: [String] = []
}

/// Runs a program to completion, answering input requests from `inputs` in order
/// and requests for files outside `baseDirectory` with `allowFiles`.
func run(_ program: Program, inputs: [String] = [], baseDirectory: URL? = nil, allowFiles: Bool = false) async -> RunResult {
    let controller = ExecutionController()
    let interpreter = Interpreter(program: program, controller: controller, baseDirectory: baseDirectory)
    var remaining = inputs
    var output = ""
    var error: RuntimeError?
    var variables = VariablesSnapshot()
    var turtle: [TurtleCommand] = []
    var fileRequests: [String] = []

    async let done: Void = interpreter.run()
    for await event in controller.events {
        defer { controller.didHandleEvent() }
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
        case .fileAccessRequested(let path, _, _):
            fileRequests.append(path)
            controller.answerFileAccess(allowFiles)
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
    return RunResult(output: output, error: error, variables: variables, turtle: turtle, fileRequests: fileRequests)
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

func openFile(_ path: String, _ mode: FileMode) -> Statement {
    Statement(.open(.init(expression: "\"\(path)\"", mode: mode)))
}

func writeLine(_ expression: String) -> Statement {
    Statement(.write(.init(expression: expression)))
}

func closeFile() -> Statement {
    Statement(.close(.init()))
}

/// A new empty folder, removed by the caller.
func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
