import Testing
@testable import FlowCore

struct ExpressionTests {
    func evaluate(_ source: String) async -> String {
        let result = await run(program([output(source)]))
        if let error = result.error { return "error: \(error.kind)" }
        return result.output.trimmingCharacters(in: .newlines)
    }

    @Test(arguments: [
        ("1 + 3 ^ 2", "10"),
        ("10 * 2 + 5 * 6", "50"),
        ("7 * (4 - 1)", "21"),
        ("6 / 3 * 2", "4"),
        ("10 mod 3", "1"),
        ("10 % 3", "1"),
        ("1 / 2", "0.5"),
        ("0.1 + 0.2", "0.3"),
        ("-2 ^ 2", "4"),
        ("2 ^ 3 ^ 2", "512"),
        ("\"a\" & 1 & true", "a1true"),
        ("3 > 2 and 2 > 1", "true"),
        ("3 ≥ 4 ∨ ¬false", "true"),
        ("1 <> 1 || 2 != 3", "true"),
        ("not 1 = 2", "error: typeMismatch(operation: \"not\", left: FlowCore.DataType.integer, right: nil)"),
        ("\"abc\" < \"abd\"", "true"),
        ("Len(\"ciao\")", "4"),
        ("Char(\"ciao\", 1)", "i"),
        ("ToFixed(3.14159, 2)", "3.14"),
        ("ToInteger(\"42\") + 1", "43"),
        ("ToReal(\"2,5\") * 2", "5"),
        ("ToCode(\"A\")", "65"),
        ("ToChar(66)", "B"),
        ("Int(-3.7)", "-3"),
        ("Sgn(-12)", "-1"),
        ("Abs(-4)", "4"),
        ("Sqrt(16)", "4"),
        ("Pi > 3.14 and π < 3.15", "true"),
        ("6 × 7 ÷ 2", "21"),
        ("\"He said \"\"hi\"\"\"", "He said \"hi\""),
        ("1e3", "1000"),
        (".5 + .5", "1"),
    ])
    func evaluates(source: String, expected: String) async {
        #expect(await evaluate(source) == expected)
    }

    @Test func divisionByZero() async {
        #expect(await evaluate("1 / 0") == "error: divisionByZero")
        #expect(await evaluate("1 mod 0") == "error: divisionByZero")
    }

    @Test func plusOnStringsIsAnError() async {
        let result = await run(program([output("\"a\" + \"b\"")]))
        guard case .typeMismatch = result.error?.kind else {
            Issue.record("expected a type mismatch, got \(String(describing: result.error))")
            return
        }
    }

    @Test func integerOverflowIsReported() async {
        #expect(await evaluate("9223372036854775807 + 1") == "error: overflow")
    }

    @Test func syntaxErrorsCarryTheirShape() async {
        let bad = output("1 +")
        let result = await run(program([bad]))
        #expect(result.error?.statementID == bad.id)
        guard case .syntax = result.error?.kind else {
            Issue.record("expected a syntax error")
            return
        }
    }

    @Test func parsesLValues() throws {
        let plain = try ExpressionParser.parseLValue("total")
        #expect(plain.name == "total" && plain.index == nil)
        let element = try ExpressionParser.parseLValue("a[i + 1]")
        #expect(element.name == "a")
        #expect(element.index == .binary(.plus, .variable("i"), .integer(1)))
        #expect(throws: ExpressionError.self) { try ExpressionParser.parseLValue("1 + x") }
    }

    func problem(_ source: String) -> ExpressionError.Kind? {
        do {
            _ = try ExpressionParser.parse(source)
            return nil
        } catch {
            return error.kind
        }
    }

    /// Deep expressions are refused instead of exhausting the stack.
    @Test func deepExpressionsAreRefused() {
        let deep = 100_000
        #expect(problem(String(repeating: "(", count: deep) + "1" + String(repeating: ")", count: deep)) == .tooComplex)
        #expect(problem(String(repeating: "-", count: deep) + "1") == .tooComplex)
        #expect(problem("1" + String(repeating: " + 1", count: deep)) == .tooComplex)
        #expect(problem("2" + String(repeating: " ^ 2", count: deep)) == .tooComplex)
        #expect(problem("Abs(" + String(repeating: "Abs(", count: deep) + "1" + String(repeating: ")", count: deep + 1)) == .tooComplex)
    }

    @Test func ordinaryExpressionsStayWithinTheLimits() async {
        let nested = String(repeating: "(", count: 30) + "1" + String(repeating: ")", count: 30)
        #expect(await evaluate(nested) == "1")
        #expect(await evaluate("0" + String(repeating: " + 1", count: 200)) == "200")
    }

    @Test func validatesIdentifiers() {
        #expect(Identifier.validate("noun2") == nil)
        #expect(Identifier.validate("2noun") == .invalidCharacters)
        #expect(Identifier.validate("my_var") == .invalidCharacters)
        #expect(Identifier.validate("Integer") == .reserved)
        #expect(Identifier.validate("len") == .reserved)
        #expect(Identifier.validate("") == .empty)
    }
}
