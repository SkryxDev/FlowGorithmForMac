import Foundation
import Testing
@testable import FlowCore

struct InterpreterTests {
    @Test func whileLoopCounts() async {
        let p = program([
            declare("n", .integer),
            assign("n", "1"),
            Statement(.while(.init(expression: "n <= 3", body: [output("n"), assign("n", "n + 1")]))),
        ])
        let result = await run(p)
        #expect(result.error == nil)
        #expect(result.output == "1\n2\n3\n")
    }

    @Test func forLoopIncreasingAndDecreasing() async {
        let p = program([
            declare("i", .integer),
            Statement(.for(.init(variable: "i", start: "1", end: "10", direction: .increasing, step: "3", body: [output("i", newline: false)]))),
            Statement(.for(.init(variable: "i", start: "3", end: "1", direction: .decreasing, step: "1", body: [output("i", newline: false)]))),
        ])
        #expect(await run(p).output == "147103 21".replacingOccurrences(of: " ", with: ""))
    }

    @Test func doLoopRunsAtLeastOnce() async {
        let p = program([
            declare("n", .integer),
            assign("n", "10"),
            Statement(.do(.init(expression: "n < 5", body: [output("n")]))),
        ])
        #expect(await run(p).output == "10\n")
    }

    @Test func ifTakesTheRightBranch() async {
        let p = program([
            declare("age", .integer),
            input("age"),
            Statement(.if(.init(expression: "age >= 18", thenBody: [output("\"vote\"")], elseBody: [output("\"wait\"")]))),
        ])
        #expect(await run(p, inputs: ["20"]).output == "vote\n")
        #expect(await run(p, inputs: ["12"]).output == "wait\n")
    }

    @Test func invalidInputIsAskedAgain() async {
        let p = program([declare("x", .integer), input("x"), output("x * 2")])
        #expect(await run(p, inputs: ["abc", "21"]).output == "42\n")
    }

    @Test func realsStoredInIntegersAreTruncated() async {
        let p = program([declare("x", .integer), assign("x", "7 / 2"), output("x")])
        #expect(await run(p).output == "3\n")
    }

    @Test func stringIntoIntegerIsAnError() async {
        let p = program([declare("x", .integer), assign("x", "\"hi\"")])
        guard case .cannotAssign = await run(p).error?.kind else {
            Issue.record("expected cannotAssign")
            return
        }
    }

    @Test func undeclaredAndUnassignedVariables() async {
        let undeclared = await run(program([output("y")]))
        #expect(undeclared.error?.kind == .undeclaredVariable("y"))
        let unassigned = await run(program([declare("y", .real), output("y")]))
        #expect(unassigned.error?.kind == .unassignedVariable("y"))
    }

    @Test func namesAreCaseInsensitive() async {
        let p = program([declare("Total", .integer), assign("TOTAL", "5"), output("total")])
        #expect(await run(p).output == "5\n")
    }

    @Test func arrays() async {
        let p = program([
            declare("a", .integer, array: "3"),
            declare("i", .integer),
            Statement(.for(.init(variable: "i", start: "0", end: "Size(a) - 1", body: [assign("a[i]", "i * i")]))),
            output("a[0] & a[1] & a[2]"),
        ])
        let result = await run(p)
        #expect(result.output == "014\n")
        #expect(result.variables.frames.first?.variables.first?.elements == [.integer(0), .integer(1), .integer(4)])
    }

    @Test func arrayIndexOutOfBounds() async {
        let p = program([declare("a", .integer, array: "2"), assign("a[2]", "1")])
        #expect(await run(p).error?.kind == .indexOutOfBounds(name: "a", index: 2, size: 2))
    }

    @Test func functionsReturnValues() async {
        let circle = Function(name: "Area", returnType: .real, returnVariable: "result",
                              parameters: [Parameter(name: "r", type: .real)],
                              body: [declare("result", .real), assign("result", "r * r * 3")])
        let p = program([output("Area(2)")], functions: [circle])
        #expect(await run(p).output == "12\n")
    }

    @Test func arraysArePassedByReference() async {
        let fill = Function(name: "Fill", parameters: [Parameter(name: "v", type: .integer, isArray: true)],
                            body: [assign("v[0]", "99")])
        let p = program([
            declare("a", .integer, array: "1"),
            Statement(.call(.init(expression: "Fill(a)"))),
            output("a[0]"),
        ], functions: [fill])
        #expect(await run(p).output == "99\n")
    }

    @Test func recursion() async {
        let factorial = Function(name: "Fact", returnType: .integer, returnVariable: "f",
                                 parameters: [Parameter(name: "n", type: .integer)],
                                 body: [
                                    declare("f", .integer),
                                    Statement(.if(.init(expression: "n <= 1",
                                                        thenBody: [assign("f", "1")],
                                                        elseBody: [assign("f", "n * Fact(n - 1)")]))),
                                 ])
        #expect(await run(program([output("Fact(10)")], functions: [factorial])).output == "3628800\n")
    }

    @Test func runawayRecursionIsAStackOverflow() async {
        let forever = Function(name: "Forever", body: [Statement(.call(.init(expression: "Forever()")))])
        let result = await run(program([Statement(.call(.init(expression: "Forever()")))], functions: [forever]))
        #expect(result.error?.kind == .stackOverflow(limit: 5000))
    }

    @Test func callingAProcedureInAnExpressionFails() async {
        let hello = Function(name: "Hello", body: [output("\"hi\"")])
        #expect(await run(program([output("Hello()")], functions: [hello])).error?.kind == .noReturnValue("Hello"))
    }

    @Test func turtleMovesAndTurns() async {
        let p = program([
            Statement(.forward(.init(expression: "100", penDown: true))),
            Statement(.turn(.init(expression: "90", direction: .right))),
            Statement(.forward(.init(expression: "50", penDown: true))),
        ])
        let lines = await run(p).turtle.compactMap { command -> (TurtlePoint, TurtlePoint)? in
            if case .line(let from, let to, _, _) = command { return (from, to) }
            return nil
        }
        #expect(lines.count == 2)
        #expect(abs(lines[0].1.y - 100) < 0.0001)
        #expect(abs(lines[1].1.x - 50) < 0.0001)
    }

    @Test func filesCanBeWrittenAndRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = program([
            Statement(.open(.init(expression: "\"data.txt\"", mode: .write))),
            Statement(.write(.init(expression: "1"))),
            Statement(.write(.init(expression: "\"two\""))),
            Statement(.close(.init(mode: .write))),
        ])
        #expect(await run(writer, baseDirectory: directory).error == nil)

        let reader = program([
            declare("line", .string),
            Statement(.open(.init(expression: "\"data.txt\"", mode: .read))),
            Statement(.while(.init(expression: "not EOF()", body: [Statement(.read(.init(variable: "line"))), output("line")]))),
            Statement(.close(.init(mode: .read))),
        ])
        let result = await run(reader, baseDirectory: directory)
        #expect(result.error == nil)
        #expect(result.output == "1\ntwo\n")
    }

    @Test func breakpointsPauseAndResume() async {
        let controller = ExecutionController()
        let p = program([output("1"), Statement(.breakpoint(.init())), output("2")])
        let interpreter = Interpreter(program: p, controller: controller)
        async let done: Void = interpreter.run()
        var events: [String] = []
        for await event in controller.events {
            switch event {
            case .output(let text, _): events.append(text)
            case .paused(_, _, let reason, _):
                events.append("paused \(reason)")
                controller.resume()
            case .finished: events.append("finished")
            default: break
            }
        }
        await done
        #expect(events == ["1", "paused breakpoint", "2", "finished"])
    }

    @Test func steppingPausesAtEveryShape() async {
        let controller = ExecutionController(startPaused: true)
        let p = program([output("1"), output("2")])
        let interpreter = Interpreter(program: p, controller: controller)
        async let done: Void = interpreter.run()
        var pauses = 0
        for await event in controller.events {
            if case .paused = event {
                pauses += 1
                controller.step()
            }
        }
        await done
        #expect(pauses == 2)
    }

    @Test func fastOutputStaysBounded() async {
        let p = program([
            declare("i", .integer),
            Statement(.for(.init(variable: "i", start: "1", end: "50000", body: [output("i")]))),
        ])
        let result = await run(p)
        #expect(result.error == nil)
        #expect(result.output.hasSuffix("50000\n"))
    }

    @Test func hugeForBoundsAreAnErrorNotACrash() async {
        let p = program([
            declare("i", .integer),
            Statement(.for(.init(variable: "i", start: "1e30", end: "1e31", body: []))),
        ])
        #expect(await run(p).error?.kind == .overflow)
    }

    @Test func stopEndsAnInfiniteLoop() async {
        let controller = ExecutionController()
        let p = program([Statement(.while(.init(expression: "true", body: [Statement(.comment(.init(text: "spin")))])))])
        let interpreter = Interpreter(program: p, controller: controller)
        async let done: Void = interpreter.run()
        try? await Task.sleep(for: .milliseconds(50))
        controller.stop()
        var stopped = false
        for await event in controller.events {
            if case .stopped = event { stopped = true }
        }
        await done
        #expect(stopped)
    }
}
