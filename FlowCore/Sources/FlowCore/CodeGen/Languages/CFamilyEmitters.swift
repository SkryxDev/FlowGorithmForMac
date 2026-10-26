import Foundation

/// Shared statement shapes for languages with braces: `if (c) { ... } else { ... }`.
class BraceEmitter: Emitter {
    func typeName(_ type: DataType) -> String {
        switch type {
        case .integer: "int"
        case .real: "double"
        case .string: "String"
        case .boolean: "boolean"
        }
    }

    var statementEnd: String { ";" }

    func braced(_ header: String, _ block: [Statement]) {
        line("\(header) {")
        indented { emitBlock(block) }
        line("}")
    }

    override func emitIf(_ s: Statement.If) {
        line("if (\(expr(s.expression))) {")
        indented { emitBlock(s.thenBody) }
        if s.elseBody.isEmpty {
            line("}")
        } else {
            line("} else {")
            indented { emitBlock(s.elseBody) }
            line("}")
        }
    }

    override func emitWhile(_ s: Statement.While) {
        braced("while (\(expr(s.expression)))", s.body)
    }

    override func emitDo(_ s: Statement.DoLoop) {
        line("do {")
        indented { emitBlock(s.body) }
        line("} while (\(expr(s.expression)))\(statementEnd)")
    }

    override func emitFor(_ s: Statement.ForLoop) {
        let f = forParts(s)
        let header: String
        if s.direction == .increasing {
            header = "for (\(f.variable) = \(f.start); \(f.variable) <= \(f.end); \(f.stepIsOne ? "\(f.variable)++" : "\(f.variable) += \(f.step)"))"
        } else {
            header = "for (\(f.variable) = \(f.start); \(f.variable) >= \(f.end); \(f.stepIsOne ? "\(f.variable)--" : "\(f.variable) -= \(f.step)"))"
        }
        braced(header, s.body)
    }

    override func emitAssign(_ s: Statement.Assign) {
        line("\(target(s.variable)) = \(assignedValue(s.expression, to: targetType(s.variable)))\(statementEnd)")
    }

    /// Flowgorithm truncates reals stored into integers; typed languages need an explicit cast.
    func assignedValue(_ source: String, to type: DataType) -> String {
        guard let parsed = parse(source) else { return source }
        if type == .integer, self.type(of: parsed) == .real { return truncate(parsed) }
        return render(parsed).text
    }

    func truncate(_ e: Expr) -> String { "(int) \(wrap(render(e), below: Emitter.atom))" }

    override func emitCall(_ s: Statement.Call) {
        let text = expr(s.expression)
        line("\(text.hasSuffix(")") ? text : text + "()")\(statementEnd)")
    }

    override func emitComment(_ text: String) {
        commentLines(text).forEach { line("// \($0)") }
    }

    /// `(double) a / b` when both sides are integers, so division is never integer division.
    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        if op == .divide, isInteger(l), isInteger(r) {
            let p = precedence(of: .divide)
            let lhs = "(double) \(wrap(render(l), below: Emitter.atom))"
            return Rendered(text: "\(lhs) / \(wrap(render(r), below: p + 1))", precedence: p)
        }
        return super.binary(op, l, r)
    }

    func returnLine(_ function: Function) {
        if function.returnType != nil {
            untagged { line("return \(name(function.returnVariable))\(statementEnd)") }
        }
    }
}

// MARK: - Java

final class JavaEmitter: BraceEmitter {
    override func emitProgram() {
        line("import java.util.*;")
        if uses.contains("file") { line("import java.io.*;") }
        blank()
        line("public class Main {")
        indented {
            line("private static Scanner input = new Scanner(System.in);")
            blank()
            if let main = mainFunction {
                enter(main)
                let throwsClause = uses.contains("file") ? " throws IOException" : ""
                line("public static void main(String[] args)\(throwsClause) {")
                indented { emitBlock(main.body) }
                line("}")
            }
            for function in otherFunctions {
                blank()
                enter(function)
                let params = function.parameters.map { "\(typeName($0.type))\($0.isArray ? "[]" : "") \(identifier($0.name))" }.joined(separator: ", ")
                let returns = function.returnType.map(typeName) ?? "void"
                let throwsClause = uses.contains("file") ? " throws IOException" : ""
                line("public static \(returns) \(functionName(function.name))(\(params))\(throwsClause) {")
                indented {
                    emitBlock(function.body)
                    returnLine(function)
                }
                line("}")
            }
        }
        line("}")
    }

    static let reserved: Set<String> = [
        "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue",
        "default", "do", "double", "else", "enum", "extends", "final", "finally", "float", "for", "goto", "if",
        "implements", "import", "instanceof", "int", "interface", "long", "native", "new", "package", "private",
        "protected", "public", "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this",
        "throw", "throws", "transient", "try", "void", "volatile", "while", "true", "false", "null", "var", "record",
        "yield", "sealed", "permits",
        "input", "file", "args", "Main", "Math", "String", "System", "Scanner", "Integer", "Double",
    ]

    override var reservedNames: Set<String> { Self.reserved }

    /// Java decodes `\u` escapes even inside comments, so `\u000a` would end one early.
    override func emitComment(_ text: String) {
        super.emitComment(text.replacingOccurrences(of: "\\u", with: "\\ u"))
    }

    override func emitDeclare(_ s: Statement.Declare) {
        if s.isArray {
            for variable in s.nameList {
                line("\(typeName(s.type))[] \(name(variable)) = new \(typeName(s.type))[\(expr(s.size))];")
            }
        } else {
            line("\(typeName(s.type)) \(s.nameList.map { name($0) }.joined(separator: ", "));")
        }
    }

    override func emitInput(_ s: Statement.Input) {
        let read = switch targetType(s.variable) {
        case .integer: "Integer.parseInt(input.nextLine())"
        case .real: "Double.parseDouble(input.nextLine())"
        case .string: "input.nextLine()"
        case .boolean: "Boolean.parseBoolean(input.nextLine())"
        }
        line("\(target(s.variable)) = \(read);")
    }

    override func emitOutput(_ s: Statement.Output) {
        line("System.out.\(s.newline ? "println" : "print")(\(expr(s.expression)));")
    }

    override func emitOpen(_ s: Statement.OpenFile) {
        switch s.mode {
        case .read: line("BufferedReader file = new BufferedReader(new FileReader(\(expr(s.expression))));")
        case .write: line("PrintWriter file = new PrintWriter(new FileWriter(\(expr(s.expression))));")
        case .append: line("PrintWriter file = new PrintWriter(new FileWriter(\(expr(s.expression)), true));")
        }
    }

    override func emitClose() { line("file.close();") }

    override func emitRead(_ s: Statement.ReadFile) {
        let read = switch targetType(s.variable) {
        case .integer: "Integer.parseInt(file.readLine())"
        case .real: "Double.parseDouble(file.readLine())"
        case .string: "file.readLine()"
        case .boolean: "Boolean.parseBoolean(file.readLine())"
        }
        line("\(target(s.variable)) = \(read);")
    }

    override func emitWrite(_ s: Statement.WriteFile) { line("file.println(\(expr(s.expression)));") }

    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        let strings = type(of: l) == .string && type(of: r) == .string
        switch op {
        case .equal where strings, .notEqual where strings:
            let text = "\(wrap(render(l), below: Emitter.atom)).equals(\(render(r).text))"
            return op == .equal ? Rendered(text: text, precedence: Emitter.atom) : Rendered(text: "!\(text)", precedence: 7)
        case .less where strings, .lessEqual where strings, .greater where strings, .greaterEqual where strings:
            let compare = "\(wrap(render(l), below: Emitter.atom)).compareTo(\(render(r).text))"
            return Rendered(text: "\(compare) \(operatorText(op)) 0", precedence: precedence(of: op))
        case .power:
            return call("Math.pow", [render(l).text, render(r).text])
        default:
            return super.binary(op, l, r)
        }
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        switch n {
        case "abs": call("Math.abs", [arg(args, 0)])
        case "arccos": call("Math.acos", [arg(args, 0)])
        case "arcsin": call("Math.asin", [arg(args, 0)])
        case "arctan": call("Math.atan", [arg(args, 0)])
        case "cos": call("Math.cos", [arg(args, 0)])
        case "sin": call("Math.sin", [arg(args, 0)])
        case "tan": call("Math.tan", [arg(args, 0)])
        case "sqrt": call("Math.sqrt", [arg(args, 0)])
        case "ln", "log": call("Math.log", [arg(args, 0)])
        case "log10": call("Math.log10", [arg(args, 0)])
        case "int": Rendered(text: "(int) \(argAtom(args, 0))", precedence: 7)
        case "sgn": Rendered(text: "(int) Math.signum(\(arg(args, 0)))", precedence: 7)
        case "random": Rendered(text: "(int) (Math.random() * \(argAtom(args, 0)))", precedence: 7)
        case "len": Rendered(text: "\(argAtom(args, 0)).length()", precedence: Emitter.atom)
        case "size": Rendered(text: "\(argAtom(args, 0)).length", precedence: Emitter.atom)
        case "char": call("String.valueOf", ["\(argAtom(args, 0)).charAt(\(arg(args, 1)))"])
        case "tochar": call("String.valueOf", ["(char) \(argAtom(args, 0))"])
        case "tocode": Rendered(text: "(int) \(argAtom(args, 0)).charAt(0)", precedence: 7)
        case "tofixed": call("String.format", ["\"%.\" + \(argAtom(args, 1)) + \"f\"", arg(args, 0)])
        case "tointeger": call("Integer.parseInt", [arg(args, 0)])
        case "toreal": call("Double.parseDouble", [arg(args, 0)])
        case "tostring": call("String.valueOf", [arg(args, 0)])
        case "eof": Rendered(text: "!file.ready()", precedence: 7)
        default: super.intrinsic(n, args)
        }
    }
}

// MARK: - C#

final class CSharpEmitter: BraceEmitter {
    override func typeName(_ type: DataType) -> String {
        switch type {
        case .integer: "int"
        case .real: "double"
        case .string: "string"
        case .boolean: "bool"
        }
    }

    override func emitProgram() {
        line("using System;")
        if uses.contains("file") { line("using System.IO;") }
        blank()
        line("public class Program")
        line("{")
        indented {
            if uses.contains("random") {
                line("private static Random random = new Random();")
                blank()
            }
            if let main = mainFunction {
                enter(main)
                line("public static void Main()")
                line("{")
                indented { emitBlock(main.body) }
                line("}")
            }
            for function in otherFunctions {
                blank()
                enter(function)
                let params = function.parameters.map { "\(typeName($0.type))\($0.isArray ? "[]" : "") \(identifier($0.name))" }.joined(separator: ", ")
                let returns = function.returnType.map(typeName) ?? "void"
                line("public static \(returns) \(functionName(function.name))(\(params))")
                line("{")
                indented {
                    emitBlock(function.body)
                    returnLine(function)
                }
                line("}")
            }
        }
        line("}")
    }

    static let reserved: Set<String> = [
        "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char", "checked", "class", "const",
        "continue", "decimal", "default", "delegate", "do", "double", "else", "enum", "event", "explicit", "extern",
        "false", "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in", "int", "interface",
        "internal", "is", "lock", "long", "namespace", "new", "null", "object", "operator", "out", "override",
        "params", "private", "protected", "public", "readonly", "ref", "return", "sbyte", "sealed", "short", "sizeof",
        "stackalloc", "static", "string", "struct", "switch", "this", "throw", "true", "try", "typeof", "uint",
        "ulong", "unchecked", "unsafe", "ushort", "using", "virtual", "void", "volatile", "while",
        "random", "file", "Main", "Math", "Console", "Program", "Random",
    ]

    override var reservedNames: Set<String> { Self.reserved }

    override func emitDeclare(_ s: Statement.Declare) {
        if s.isArray {
            for variable in s.nameList {
                line("\(typeName(s.type))[] \(name(variable)) = new \(typeName(s.type))[\(expr(s.size))];")
            }
        } else {
            line("\(typeName(s.type)) \(s.nameList.map { name($0) }.joined(separator: ", "));")
        }
    }

    func parse(type: DataType, _ text: String) -> String {
        switch type {
        case .integer: "int.Parse(\(text))"
        case .real: "double.Parse(\(text))"
        case .string: text
        case .boolean: "bool.Parse(\(text))"
        }
    }

    override func emitInput(_ s: Statement.Input) {
        line("\(target(s.variable)) = \(parse(type: targetType(s.variable), "Console.ReadLine()"));")
    }

    override func emitOutput(_ s: Statement.Output) {
        line("Console.\(s.newline ? "WriteLine" : "Write")(\(expr(s.expression)));")
    }

    override func emitOpen(_ s: Statement.OpenFile) {
        switch s.mode {
        case .read: line("StreamReader file = new StreamReader(\(expr(s.expression)));")
        case .write: line("StreamWriter file = new StreamWriter(\(expr(s.expression)));")
        case .append: line("StreamWriter file = new StreamWriter(\(expr(s.expression)), true);")
        }
    }

    override func emitClose() { line("file.Close();") }

    override func emitRead(_ s: Statement.ReadFile) {
        line("\(target(s.variable)) = \(parse(type: targetType(s.variable), "file.ReadLine()"));")
    }

    override func emitWrite(_ s: Statement.WriteFile) { line("file.WriteLine(\(expr(s.expression)));") }

    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        let strings = type(of: l) == .string && type(of: r) == .string
        switch op {
        case .less where strings, .lessEqual where strings, .greater where strings, .greaterEqual where strings:
            return Rendered(text: "string.Compare(\(render(l).text), \(render(r).text)) \(operatorText(op)) 0", precedence: precedence(of: op))
        case .power:
            return call("Math.Pow", [render(l).text, render(r).text])
        default:
            return super.binary(op, l, r)
        }
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        switch n {
        case "abs": call("Math.Abs", [arg(args, 0)])
        case "arccos": call("Math.Acos", [arg(args, 0)])
        case "arcsin": call("Math.Asin", [arg(args, 0)])
        case "arctan": call("Math.Atan", [arg(args, 0)])
        case "cos": call("Math.Cos", [arg(args, 0)])
        case "sin": call("Math.Sin", [arg(args, 0)])
        case "tan": call("Math.Tan", [arg(args, 0)])
        case "sqrt": call("Math.Sqrt", [arg(args, 0)])
        case "ln", "log": call("Math.Log", [arg(args, 0)])
        case "log10": call("Math.Log10", [arg(args, 0)])
        case "int": Rendered(text: "(int) \(argAtom(args, 0))", precedence: 7)
        case "sgn": call("Math.Sign", [arg(args, 0)])
        case "random": call("random.Next", [arg(args, 0)])
        case "len", "size": Rendered(text: "\(argAtom(args, 0)).Length", precedence: Emitter.atom)
        case "char": Rendered(text: "\(argAtom(args, 0))[\(arg(args, 1))].ToString()", precedence: Emitter.atom)
        case "tochar": Rendered(text: "((char) \(argAtom(args, 0))).ToString()", precedence: Emitter.atom)
        case "tocode": Rendered(text: "(int) \(argAtom(args, 0))[0]", precedence: 7)
        case "tofixed": Rendered(text: "\(argAtom(args, 0)).ToString(\"F\" + \(argAtom(args, 1)))", precedence: Emitter.atom)
        case "tointeger": call("int.Parse", [arg(args, 0)])
        case "toreal": call("double.Parse", [arg(args, 0)])
        case "tostring": Rendered(text: "\(argAtom(args, 0)).ToString()", precedence: Emitter.atom)
        case "eof": Rendered(text: "file.EndOfStream", precedence: Emitter.atom)
        default: super.intrinsic(n, args)
        }
    }

    override var piText: String { "Math.PI" }
}

// MARK: - C++

final class CppEmitter: BraceEmitter {
    override func typeName(_ type: DataType) -> String {
        switch type {
        case .integer: "int"
        case .real: "double"
        case .string: "string"
        case .boolean: "bool"
        }
    }

    static let reserved: Set<String> = [
        "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "bool", "break", "case", "catch",
        "char", "char8_t", "char16_t", "char32_t", "class", "compl", "concept", "const", "consteval", "constexpr",
        "constinit", "const_cast", "continue", "co_await", "co_return", "co_yield", "decltype", "default", "delete",
        "do", "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false", "float", "for",
        "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "not", "not_eq",
        "nullptr", "operator", "or", "or_eq", "private", "protected", "public", "register", "reinterpret_cast",
        "requires", "return", "short", "signed", "sizeof", "static", "static_assert", "static_cast", "struct",
        "switch", "template", "this", "thread_local", "throw", "true", "try", "typedef", "typeid", "typename",
        "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq",
        "main", "file", "std", "string", "vector", "cin", "cout", "endl", "toFixed", "pow", "fmod", "fabs", "rand",
        "stoi", "stod",
    ]

    override var reservedNames: Set<String> { Self.reserved }

    func signature(_ function: Function) -> String {
        let params = function.parameters.map {
            $0.isArray ? "vector<\(typeName($0.type))>& \(identifier($0.name))" : "\(typeName($0.type)) \(identifier($0.name))"
        }.joined(separator: ", ")
        return "\(function.returnType.map(typeName) ?? "void") \(functionName(function.name))(\(params))"
    }

    override func emitProgram() {
        line("#include <iostream>")
        line("#include <string>")
        line("#include <vector>")
        line("#include <cmath>")
        if uses.contains("random") { line("#include <cstdlib>") }
        if uses.contains("file") { line("#include <fstream>") }
        if uses.contains("tofixed") {
            line("#include <sstream>")
            line("#include <iomanip>")
        }
        blank()
        line("using namespace std;")
        blank()
        if uses.contains("tofixed") {
            line("string toFixed(double value, int digits) {")
            indented {
                line("ostringstream out;")
                line("out << fixed << setprecision(digits) << value;")
                line("return out.str();")
            }
            line("}")
            blank()
        }
        for function in otherFunctions {
            line("\(signature(function));")
        }
        if !otherFunctions.isEmpty { blank() }
        if let main = mainFunction {
            enter(main)
            line("int main() {")
            indented {
                if uses.contains("file") { line("fstream file;") }
                emitBlock(main.body)
                untagged { line("return 0;") }
            }
            line("}")
        }
        for function in otherFunctions {
            blank()
            enter(function)
            line("\(signature(function)) {")
            indented {
                emitBlock(function.body)
                returnLine(function)
            }
            line("}")
        }
    }

    override func emitDeclare(_ s: Statement.Declare) {
        if s.isArray {
            for variable in s.nameList {
                line("vector<\(typeName(s.type))> \(name(variable))(\(expr(s.size)));")
            }
        } else {
            line("\(typeName(s.type)) \(s.nameList.map { name($0) }.joined(separator: ", "));")
        }
    }

    override func emitInput(_ s: Statement.Input) {
        let type = targetType(s.variable)
        line(type == .boolean ? "cin >> boolalpha >> \(target(s.variable));" : "cin >> \(target(s.variable));")
    }

    override func emitOutput(_ s: Statement.Output) {
        let parts: [String]
        if let parsed = parse(s.expression) {
            parts = flattenConcat(parsed).map { part in
                let text = wrap(render(part), below: 6)
                return type(of: part) == .boolean ? "boolalpha << \(text)" : text
            }
        } else {
            parts = [s.expression]
        }
        line("cout << \(parts.joined(separator: " << "))\(s.newline ? " << endl" : "");")
    }

    override func emitOpen(_ s: Statement.OpenFile) {
        let mode = switch s.mode {
        case .read: "ios::in"
        case .write: "ios::out"
        case .append: "ios::app"
        }
        line("file.open(\(expr(s.expression)), \(mode));")
    }

    override func emitClose() { line("file.close();") }

    override func emitRead(_ s: Statement.ReadFile) { line("file >> \(target(s.variable));") }

    override func emitWrite(_ s: Statement.WriteFile) { line("file << \(expr(s.expression)) << endl;") }

    override func stringLiteral(_ s: String) -> String { super.stringLiteral(s) }

    override var piText: String { "M_PI" }

    override func concat(_ parts: [Expr]) -> Rendered {
        let p = precedence(of: .plus)
        var texts: [String] = []
        for (index, part) in parts.enumerated() {
            switch type(of: part) {
            case .string:
                if index == 0, case .string = part {
                    texts.append("string(\(render(part).text))")
                } else {
                    texts.append(wrap(render(part), below: p + 1))
                }
            case .boolean:
                texts.append("(\(render(part).text) ? \"true\" : \"false\")")
                if index == 0 { texts[0] = "string\(texts[0])" }
            default:
                texts.append("to_string(\(render(part).text))")
            }
        }
        return Rendered(text: texts.joined(separator: " + "), precedence: p)
    }

    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        if op == .power { return call("pow", [render(l).text, render(r).text]) }
        if op == .modulo, !(isInteger(l) && isInteger(r)) { return call("fmod", [render(l).text, render(r).text]) }
        return super.binary(op, l, r)
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        switch n {
        case "abs": call(args.first.map(isInteger) == true ? "abs" : "fabs", [arg(args, 0)])
        case "arccos": call("acos", [arg(args, 0)])
        case "arcsin": call("asin", [arg(args, 0)])
        case "arctan": call("atan", [arg(args, 0)])
        case "ln", "log": call("log", [arg(args, 0)])
        case "int": Rendered(text: "(int) \(argAtom(args, 0))", precedence: 7)
        case "sgn": Rendered(text: "((\(arg(args, 0)) > 0) - (\(arg(args, 0)) < 0))", precedence: Emitter.atom)
        case "random": Rendered(text: "rand() % \(argAtom(args, 0))", precedence: 6)
        case "len", "size": Rendered(text: "(int) \(argAtom(args, 0)).size()", precedence: 7)
        case "char": call("string", ["1", "\(argAtom(args, 0))[\(arg(args, 1))]"])
        case "tochar": call("string", ["1", "(char) \(argAtom(args, 0))"])
        case "tocode": Rendered(text: "(int) \(argAtom(args, 0))[0]", precedence: 7)
        case "tofixed": call("toFixed", [arg(args, 0), arg(args, 1)])
        case "tointeger": call("stoi", [arg(args, 0)])
        case "toreal": call("stod", [arg(args, 0)])
        case "tostring": call("to_string", [arg(args, 0)])
        case "eof": call("file.eof", [])
        default: super.intrinsic(n, args)
        }
    }
}

// MARK: - JavaScript / TypeScript

final class JavaScriptEmitter: BraceEmitter {
    let typed: Bool

    init(program: Program, typed: Bool) {
        self.typed = typed
        super.init(program: program)
    }

    override func typeName(_ type: DataType) -> String {
        switch type {
        case .integer, .real: "number"
        case .string: "string"
        case .boolean: "boolean"
        }
    }

    override func emitProgram() {
        if uses.contains("input") {
            emitComment("Input uses prompt(): run this in a browser, or provide prompt() in Node.js.")
            blank()
        }
        if let main = mainFunction {
            enter(main)
            emitBlock(main.body)
        }
        for function in otherFunctions {
            blank()
            enter(function)
            let params = function.parameters.map {
                typed ? "\(identifier($0.name)): \(typeName($0.type))\($0.isArray ? "[]" : "")" : identifier($0.name)
            }.joined(separator: ", ")
            let returns = typed ? ": \(function.returnType.map(typeName) ?? "void")" : ""
            line("function \(functionName(function.name))(\(params))\(returns) {")
            indented {
                emitBlock(function.body)
                returnLine(function)
            }
            line("}")
        }
    }

    static let reserved: Set<String> = [
        "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do",
        "else", "enum", "export", "extends", "false", "finally", "for", "function", "if", "implements", "import",
        "in", "instanceof", "interface", "let", "new", "null", "package", "private", "protected", "public",
        "return", "static", "super", "switch", "this", "throw", "true", "try", "typeof", "var", "void", "while",
        "with", "yield", "arguments", "eval", "undefined", "NaN", "Infinity",
        "prompt", "console", "process", "Math", "String", "Array", "parseInt", "parseFloat",
    ]

    override var reservedNames: Set<String> { Self.reserved }

    override func emitDeclare(_ s: Statement.Declare) {
        for variable in s.nameList.map({ name($0) }) {
            if s.isArray {
                let annotation = typed ? ": \(typeName(s.type))[]" : ""
                line("let \(variable)\(annotation) = new Array(\(expr(s.size)));")
            } else {
                line(typed ? "let \(variable): \(typeName(s.type));" : "let \(variable);")
            }
        }
    }

    override func emitInput(_ s: Statement.Input) {
        let read = switch targetType(s.variable) {
        case .integer: "parseInt(prompt())"
        case .real: "parseFloat(prompt())"
        case .string: typed ? "prompt() ?? \"\"" : "prompt()"
        case .boolean: "prompt() === \"true\""
        }
        line("\(target(s.variable)) = \(read);")
    }

    override func emitOutput(_ s: Statement.Output) {
        line(s.newline ? "console.log(\(expr(s.expression)));" : "process.stdout.write(String(\(expr(s.expression))));")
    }

    override func truncate(_ e: Expr) -> String { "Math.trunc(\(render(e).text))" }

    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        switch op {
        case .equal: return infix(op, l, r, text: "===")
        case .notEqual: return infix(op, l, r, text: "!==")
        case .divide: return infix(op, l, r)
        case .power: return infix(op, l, r, text: "**")
        default: return super.binary(op, l, r)
        }
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        switch n {
        case "abs": call("Math.abs", [arg(args, 0)])
        case "arccos": call("Math.acos", [arg(args, 0)])
        case "arcsin": call("Math.asin", [arg(args, 0)])
        case "arctan": call("Math.atan", [arg(args, 0)])
        case "cos": call("Math.cos", [arg(args, 0)])
        case "sin": call("Math.sin", [arg(args, 0)])
        case "tan": call("Math.tan", [arg(args, 0)])
        case "sqrt": call("Math.sqrt", [arg(args, 0)])
        case "ln", "log": call("Math.log", [arg(args, 0)])
        case "log10": call("Math.log10", [arg(args, 0)])
        case "int": call("Math.trunc", [arg(args, 0)])
        case "sgn": call("Math.sign", [arg(args, 0)])
        case "random": call("Math.floor", ["Math.random() * \(argAtom(args, 0))"])
        case "len", "size": Rendered(text: "\(argAtom(args, 0)).length", precedence: Emitter.atom)
        case "char": Rendered(text: "\(argAtom(args, 0)).charAt(\(arg(args, 1)))", precedence: Emitter.atom)
        case "tochar": call("String.fromCharCode", [arg(args, 0)])
        case "tocode": Rendered(text: "\(argAtom(args, 0)).charCodeAt(0)", precedence: Emitter.atom)
        case "tofixed": Rendered(text: "\(argAtom(args, 0)).toFixed(\(arg(args, 1)))", precedence: Emitter.atom)
        case "tointeger": call("parseInt", [arg(args, 0)])
        case "toreal": call("parseFloat", [arg(args, 0)])
        case "tostring": call("String", [arg(args, 0)])
        default: super.intrinsic(n, args)
        }
    }
}

// MARK: - Kotlin

final class KotlinEmitter: BraceEmitter {
    override var statementEnd: String { "" }

    override func typeName(_ type: DataType) -> String {
        switch type {
        case .integer: "Int"
        case .real: "Double"
        case .string: "String"
        case .boolean: "Boolean"
        }
    }

    func arrayType(_ type: DataType) -> String {
        switch type {
        case .integer: "IntArray"
        case .real: "DoubleArray"
        case .string: "Array<String>"
        case .boolean: "BooleanArray"
        }
    }

    func defaultValue(_ type: DataType) -> String {
        switch type {
        case .integer: "0"
        case .real: "0.0"
        case .string: "\"\""
        case .boolean: "false"
        }
    }

    override func emitProgram() {
        line("import kotlin.math.*")
        if uses.contains("file") { line("import java.io.File") }
        blank()
        if let main = mainFunction {
            enter(main)
            line("fun main() {")
            indented { emitBlock(main.body) }
            line("}")
        }
        for function in otherFunctions {
            blank()
            enter(function)
            let params = function.parameters.map { "\(identifier($0.name)): \($0.isArray ? arrayType($0.type) : typeName($0.type))" }
                .joined(separator: ", ")
            let returns = function.returnType.map { ": \(typeName($0))" } ?? ""
            line("fun \(functionName(function.name))(\(params))\(returns) {")
            indented {
                // Kotlin parameters are read-only; copy scalars so the flowchart can change them.
                for parameter in function.parameters where !parameter.isArray {
                    untagged { line("var \(identifier(parameter.name)) = \(identifier(parameter.name))") }
                }
                emitBlock(function.body)
                returnLine(function)
            }
            line("}")
        }
    }

    static let reserved: Set<String> = [
        "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is",
        "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "typeof",
        "val", "var", "when", "while",
        "main", "file", "print", "println", "readln", "File", "PI",
    ]

    override var reservedNames: Set<String> { Self.reserved }

    /// `$` starts a string template in Kotlin.
    override func stringLiteral(_ s: String) -> String {
        super.stringLiteral(s).replacingOccurrences(of: "$", with: "\\$")
    }

    override func emitDeclare(_ s: Statement.Declare) {
        for variable in s.nameList.map({ name($0) }) {
            if s.isArray {
                let size = expr(s.size)
                line(s.type == .string ? "val \(variable) = Array(\(size)) { \"\" }" : "val \(variable) = \(arrayType(s.type))(\(size))")
            } else {
                line("var \(variable): \(typeName(s.type)) = \(defaultValue(s.type))")
            }
        }
    }

    override func emitInput(_ s: Statement.Input) {
        let read = switch targetType(s.variable) {
        case .integer: "readln().toInt()"
        case .real: "readln().toDouble()"
        case .string: "readln()"
        case .boolean: "readln().toBoolean()"
        }
        line("\(target(s.variable)) = \(read)")
    }

    override func emitOutput(_ s: Statement.Output) {
        line("\(s.newline ? "println" : "print")(\(expr(s.expression)))")
    }

    override func emitFor(_ s: Statement.ForLoop) {
        let f = forParts(s)
        let range = s.direction == .increasing ? "\(f.start)..\(f.end)" : "\(f.start) downTo \(f.end)"
        braced("for (\(f.variable) in \(range)\(f.stepIsOne ? "" : " step \(f.step)"))", s.body)
    }

    override func truncate(_ e: Expr) -> String { "\(wrap(render(e), below: Emitter.atom)).toInt()" }

    override func binary(_ op: Operator, _ l: Expr, _ r: Expr) -> Rendered {
        switch op {
        case .divide where isInteger(l) && isInteger(r):
            let p = precedence(of: .divide)
            return Rendered(text: "\(wrap(render(l), below: Emitter.atom)).toDouble() / \(wrap(render(r), below: p + 1))", precedence: p)
        case .power:
            return Rendered(text: "\(wrap(render(l), below: Emitter.atom)).toDouble().pow(\(render(r).text))", precedence: Emitter.atom)
        default:
            return super.binary(op, l, r)
        }
    }

    override var piText: String { "PI" }

    /// Kotlin only adds to a String from the left, so a leading non-string gets `"" +`.
    override func concat(_ parts: [Expr]) -> Rendered {
        let p = precedence(of: .plus)
        var texts = parts.map { wrap(render($0), below: p + 1) }
        if let first = parts.first, type(of: first) != .string { texts.insert("\"\"", at: 0) }
        return Rendered(text: texts.joined(separator: " + "), precedence: p)
    }

    /// kotlin.math functions take Double only.
    func double(_ args: [Expr], _ i: Int) -> String {
        guard i < args.count else { return "" }
        return isInteger(args[i]) ? "\(argAtom(args, i)).toDouble()" : arg(args, i)
    }

    override func intrinsic(_ n: String, _ args: [Expr]) -> Rendered {
        switch n {
        case "arccos": call("acos", [double(args, 0)])
        case "arcsin": call("asin", [double(args, 0)])
        case "arctan": call("atan", [double(args, 0)])
        case "cos", "sin", "tan", "sqrt", "log10": call(n, [double(args, 0)])
        case "ln", "log": call("ln", [double(args, 0)])
        case "int": Rendered(text: "\(argAtom(args, 0)).toInt()", precedence: Emitter.atom)
        case "sgn": Rendered(text: "sign(\(arg(args, 0)).toDouble()).toInt()", precedence: Emitter.atom)
        case "random": Rendered(text: "(0 until \(arg(args, 0))).random()", precedence: Emitter.atom)
        case "len": Rendered(text: "\(argAtom(args, 0)).length", precedence: Emitter.atom)
        case "size": Rendered(text: "\(argAtom(args, 0)).size", precedence: Emitter.atom)
        case "char": Rendered(text: "\(argAtom(args, 0))[\(arg(args, 1))].toString()", precedence: Emitter.atom)
        case "tochar": Rendered(text: "\(argAtom(args, 0)).toChar().toString()", precedence: Emitter.atom)
        case "tocode": Rendered(text: "\(argAtom(args, 0))[0].code", precedence: Emitter.atom)
        case "tofixed": Rendered(text: "\"%.${\(arg(args, 1))}f\".format(\(arg(args, 0)))", precedence: Emitter.atom)
        case "tointeger": Rendered(text: "\(argAtom(args, 0)).toInt()", precedence: Emitter.atom)
        case "toreal": Rendered(text: "\(argAtom(args, 0)).toDouble()", precedence: Emitter.atom)
        case "tostring": Rendered(text: "\(argAtom(args, 0)).toString()", precedence: Emitter.atom)
        default: super.intrinsic(n, args)
        }
    }

    override func emitOpen(_ s: Statement.OpenFile) {
        switch s.mode {
        case .read: line("val file = File(\(expr(s.expression))).bufferedReader()")
        case .write: line("val file = File(\(expr(s.expression))).printWriter()")
        case .append: line("val file = java.io.PrintWriter(java.io.FileWriter(\(expr(s.expression)), true))")
        }
    }

    override func emitClose() { line("file.close()") }

    override func emitRead(_ s: Statement.ReadFile) {
        let suffix = switch targetType(s.variable) {
        case .integer: "!!.toInt()"
        case .real: "!!.toDouble()"
        case .string: "!!"
        case .boolean: "!!.toBoolean()"
        }
        line("\(target(s.variable)) = file.readLine()\(suffix)")
    }

    override func emitWrite(_ s: Statement.WriteFile) { line("file.println(\(expr(s.expression)))") }
}
