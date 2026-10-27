// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Testing
@testable import FlowCore

struct LinterTests {
    func kinds(_ program: Program) -> [LintProblem.Kind] {
        Linter.problems(in: program).map(\.kind)
    }

    @Test func aCorrectProgramHasNoProblems() {
        let body = [declare("n, i", .integer), declare("total", .real), input("n"), assign("total", "0"),
                    Statement(.for(.init(variable: "i", start: "1", end: "n", body: [assign("total", "total + Square(i)")]))),
                    output("\"Total: \" & ToFixed(total, 2) & \" \" & Pi")]
        let square = Function(name: "Square", returnType: .integer, returnVariable: "r",
                              parameters: [Parameter(name: "x", type: .integer)],
                              body: [declare("r", .integer), assign("r", "x * x")])
        #expect(kinds(program(body, functions: [square])).isEmpty)
    }

    @Test func findsTheMistakesThatStopAProgram() {
        let body = [declare("length, special", .integer), declare("Special", .boolean),
                    input("length"), output("lenght >= 8 or Missing(2)")]
        #expect(kinds(program(body)) == [.duplicateDeclaration("Special"), .undeclared("lenght"), .unknownFunction("Missing")])
    }

    @Test func usesBeforeTheDeclarationAreUndeclared() {
        #expect(kinds(program([assign("x", "1"), declare("x", .integer)])) == [.undeclared("x")])
    }

    @Test func loopsAndBranches() {
        let inLoop = Statement(.while(.init(expression: "true", body: [declare("temp", .integer)])))
        #expect(kinds(program([inLoop])) == [.declaredInLoop("temp")])

        // Declaring the same name in both branches of an if is fine, and it's known afterwards.
        let branches = Statement(.if(.init(expression: "1 > 0", thenBody: [declare("x", .integer)],
                                           elseBody: [declare("x", .real)])))
        #expect(kinds(program([branches, output("x")])).isEmpty)
    }

    @Test func parametersAndReturnVariables() {
        let shadow = Function(name: "Twice", returnType: .integer, returnVariable: "result",
                              parameters: [Parameter(name: "n", type: .integer)],
                              body: [declare("n", .integer), assign("n", "n * 2")])
        #expect(kinds(program([], functions: [shadow])) == [.duplicateDeclaration("n"), .returnVariableNotDeclared("result")])
    }

    @Test func typesFollowTheInterpreterRules() {
        // The AI's password program: a true/false answer stored in an Integer, then used with or.
        let password = [declare("length, special", .integer), input("length"), input("special"),
                        Statement(.if(.init(expression: "length >= 8 or special", thenBody: [output("\"OK\"")])))]
        #expect(kinds(program(password)) == [.typeMismatch("or joins true or false values, but special is an Integer")])

        let mixed = [declare("n", .integer), declare("name", .string), declare("ok", .boolean),
                     assign("n", "\"5\""), assign("name", "\"Ann\" + n"), assign("ok", "n"),
                     Statement(.while(.init(expression: "n", body: []))), output("name < n"), output("Len(n)")]
        #expect(kinds(program(mixed)) == [
            .typeMismatch("n is an Integer but gets a String value"),
            .typeMismatch("+ works on numbers, but \"Ann\" is a String; use & to join text"),
            .typeMismatch("ok is a Boolean (true or false) but gets an Integer value"),
            .typeMismatch("a condition must be true or false, but \"n\" is an Integer"),
            .typeMismatch("name (a String) can't be compared with n (an Integer)"),
            .typeMismatch("Len needs text, but n is an Integer"),
        ])

        // Numbers mix freely, reals go into integers, and text joins anything with &.
        let fine = [declare("i", .integer), declare("r", .real), declare("s", .string), declare("a", .real, array: "3"),
                    assign("r", "i / 2 + Sqrt(9) * Pi"), assign("i", "r"), assign("s", "\"x = \" & r & true"),
                    assign("a[i mod 3]", "Abs(-2) + Size(a)"), output("ToFixed(r, 2) & Char(s, 0) & Len(s)"),
                    Statement(.if(.init(expression: "not (i > r) and s <> \"\"", thenBody: [])))]
        #expect(kinds(program(fine)).isEmpty)
    }

    @Test func expressionsThatDontParseAreLeftToTheSyntaxCheck() {
        #expect(kinds(program([declare("x", .integer), output("x +")])).isEmpty)
    }
}
