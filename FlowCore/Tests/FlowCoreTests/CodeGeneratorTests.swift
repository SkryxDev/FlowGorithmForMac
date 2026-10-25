import Foundation
import Testing
@testable import FlowCore

struct CodeGeneratorTests {
    /// A program that touches most features: input, arrays, loops, functions, concatenation and division.
    static let sample: Program = {
        let average = Function(name: "Average", returnType: .real, returnVariable: "result",
                               parameters: [Parameter(name: "values", type: .integer, isArray: true),
                                            Parameter(name: "count", type: .integer)],
                               body: [
                                declare("result", .real),
                                declare("total, i", .integer),
                                assign("total", "0"),
                                Statement(.for(.init(variable: "i", start: "0", end: "count - 1", body: [assign("total", "total + values[i]")]))),
                                assign("result", "total / count"),
                               ])
        return program([
            declare("n, i", .integer),
            declare("numbers", .integer, array: "5"),
            declare("name", .string),
            declare("ok", .boolean),
            output("\"Name?\""),
            input("name"),
            assign("n", "5"),
            Statement(.for(.init(variable: "i", start: "0", end: "n - 1", body: [assign("numbers[i]", "i * i")]))),
            Statement(.if(.init(expression: "Len(name) > 3 and n mod 2 = 1",
                                thenBody: [output("\"Hi \" & name & \", average \" & Average(numbers, n)")],
                                elseBody: [output("ToFixed(2 ^ 0.5, 3)", newline: false)]))),
            assign("ok", "not (n = 5)"),
            Statement(.while(.init(expression: "n > 0", body: [assign("n", "n - 2")]))),
            Statement(.do(.init(expression: "n < 3", body: [assign("n", "n + 1")]))),
            Statement(.comment(.init(text: "done"))),
            output("Sqrt(16) + Abs(-3) & \" \" & Pi"),
        ], functions: [average])
    }()

    @Test(arguments: SourceLanguage.allCases)
    func generatesTaggedLines(language: SourceLanguage) {
        let source = CodeGenerator.generate(Self.sample, language: language)
        #expect(source.lines.count > 10)
        // Every shape of Main appears on at least one line.
        let tagged = Set(source.lines.compactMap(\.statementID))
        for statement in Self.sample.functions[0].body {
            #expect(tagged.contains(statement.id), "\(language): missing \(statement.kind)")
        }
    }

    @Test func pythonOutput() {
        let p = program([
            declare("x", .integer),
            input("x"),
            Statement(.if(.init(expression: "x >= 18", thenBody: [output("\"Adult \" & x")], elseBody: [output("x / 2", newline: false)]))),
        ])
        let text = CodeGenerator.generate(p, language: .python).text
        #expect(text == """
        # Main
        x = 0
        x = int(input())
        if x >= 18:
            print("Adult " + str(x))
        else:
            print(x / 2, end="")

        """)
    }

    @Test func javaComparesStringsWithEquals() {
        let p = program([declare("a, b", .string), assign("a", "\"x\""), assign("b", "a"),
                         Statement(.if(.init(expression: "a = b", thenBody: [output("1 / 2")])))])
        let text = CodeGenerator.generate(p, language: .java).text
        #expect(text.contains("if (a.equals(b)) {"))
        #expect(text.contains("System.out.println((double) 1 / 2);"))
    }

    @Test func pseudocodeInItalian() {
        let p = program([declare("i", .integer),
                         Statement(.for(.init(variable: "i", start: "1", end: "10", direction: .increasing, step: "2", body: [output("i")])))])
        let text = CodeGenerator.generate(p, language: .pseudocodeItalian).text
        #expect(text.contains("DICHIARA Intero i"))
        #expect(text.contains("PER i DA 1 A 10 PASSO 2"))
        #expect(text.contains("FINE PER"))
    }

    /// Writes every language to a folder so `Scripts/check-codegen.sh` can compile the results.
    @Test func writesSamplesWhenAsked() throws {
        guard let folder = ProcessInfo.processInfo.environment["CODEGEN_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for language in SourceLanguage.allCases {
            let name = language == .java ? "Main" : language.rawValue
            try CodeGenerator.generate(Self.sample, language: language).text
                .write(to: url.appendingPathComponent("\(name).\(language.fileExtension)"), atomically: true, encoding: .utf8)
        }
    }
}
