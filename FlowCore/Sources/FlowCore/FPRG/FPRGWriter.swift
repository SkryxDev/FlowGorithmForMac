import Foundation

/// Writes programs in the `.fprg` XML format, laid out the same way Flowgorithm does.
public enum FPRGWriter {
    /// The file format version Flowgorithm 4.x writes.
    public static let currentFileVersion = "4.2"

    public static func write(_ program: Program, updatingSavedDate date: Date? = nil) -> Data {
        Data(string(program, updatingSavedDate: date).utf8)
    }

    public static func string(_ program: Program, updatingSavedDate date: Date? = nil) -> String {
        var program = program
        if let date {
            program[attribute: "saved"] = savedDateFormatter.string(from: date)
        }
        var out = "<?xml version=\"1.0\"?>\n"
        out += "<flowgorithm fileversion=\"\(escape(currentFileVersion))\">\n"
        out += "    <attributes>\n"
        for attribute in program.attributes {
            out += "        <attribute name=\"\(escape(attribute.name))\" value=\"\(escape(attribute.value))\"/>\n"
        }
        out += "    </attributes>\n"
        for function in program.functions {
            out += "    <function name=\"\(escape(function.name))\" type=\"\(function.returnType?.rawValue ?? "None")\" variable=\"\(escape(function.returnVariable))\">\n"
            if function.parameters.isEmpty {
                out += "        <parameters/>\n"
            } else {
                out += "        <parameters>\n"
                for parameter in function.parameters {
                    out += "            <parameter name=\"\(escape(parameter.name))\" type=\"\(parameter.type.rawValue)\" array=\"\(bool(parameter.isArray))\"/>\n"
                }
                out += "        </parameters>\n"
            }
            out += element("body", children: function.body, indent: 2)
            out += "    </function>\n"
        }
        out += "</flowgorithm>\n"
        return out
    }

    /// Serializes loose statements (for the clipboard) as a `<body>` fragment.
    public static func fragment(_ statements: [Statement]) -> String {
        element("body", children: statements, indent: 0)
    }

    /// Parses a fragment written by `fragment(_:)`; statements get fresh identifiers.
    public static func statements(fromFragment string: String) -> [Statement]? {
        guard let element = try? XMLElement(xmlString: string), element.name == "body" else { return nil }
        return FPRGReader.statements(in: element).map { $0.withNewIDs() }
    }

    static var savedDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss a"
        return formatter
    }

    static func pad(_ indent: Int) -> String { String(repeating: "    ", count: indent) }

    static func bool(_ value: Bool) -> String { value ? "True" : "False" }

    static func element(_ name: String, children: [Statement], indent: Int) -> String {
        if children.isEmpty { return "\(pad(indent))<\(name)/>\n" }
        var out = "\(pad(indent))<\(name)>\n"
        for child in children { out += statement(child, indent: indent + 1) }
        out += "\(pad(indent))</\(name)>\n"
        return out
    }

    static func leaf(_ name: String, _ attributes: [(String, String)], indent: Int) -> String {
        let attrs = attributes.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
        return "\(pad(indent))<\(name)\(attrs)/>\n"
    }

    static func container(_ name: String, _ attributes: [(String, String)], body: [Statement], indent: Int) -> String {
        let attrs = attributes.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
        if body.isEmpty { return "\(pad(indent))<\(name)\(attrs)/>\n" }
        var out = "\(pad(indent))<\(name)\(attrs)>\n"
        for child in body { out += statement(child, indent: indent + 1) }
        out += "\(pad(indent))</\(name)>\n"
        return out
    }

    static func statement(_ statement: Statement, indent: Int) -> String {
        switch statement.kind {
        case .declare(let s):
            return leaf("declare", [("name", s.names), ("type", s.type.rawValue), ("array", bool(s.isArray)), ("size", s.size)], indent: indent)
        case .assign(let s):
            return leaf("assign", [("variable", s.variable), ("expression", s.expression)], indent: indent)
        case .input(let s):
            return leaf("input", [("variable", s.variable)], indent: indent)
        case .output(let s):
            return leaf("output", [("expression", s.expression), ("newline", bool(s.newline))], indent: indent)
        case .if(let s):
            var out = "\(pad(indent))<if expression=\"\(escape(s.expression))\">\n"
            out += element("then", children: s.thenBody, indent: indent + 1)
            out += element("else", children: s.elseBody, indent: indent + 1)
            out += "\(pad(indent))</if>\n"
            return out
        case .while(let s):
            return container("while", [("expression", s.expression)], body: s.body, indent: indent)
        case .do(let s):
            return container("do", [("expression", s.expression)], body: s.body, indent: indent)
        case .for(let s):
            return container("for", [("variable", s.variable), ("start", s.start), ("end", s.end),
                                     ("direction", s.direction.rawValue), ("step", s.step)], body: s.body, indent: indent)
        case .call(let s):
            return leaf("call", [("expression", s.expression)], indent: indent)
        case .comment(let s):
            return leaf("comment", [("text", s.text)], indent: indent)
        case .breakpoint(let s):
            return leaf("breakpoint", [("expression", s.expression), ("always", bool(s.always))], indent: indent)
        case .open(let s):
            return leaf("open", [("expression", s.expression), ("mode", s.mode.rawValue)], indent: indent)
        case .close(let s):
            return leaf("close", [("mode", s.mode.rawValue)], indent: indent)
        case .read(let s):
            return leaf("read", [("variable", s.variable)], indent: indent)
        case .write(let s):
            return leaf("write", [("expression", s.expression)], indent: indent)
        case .turn(let s):
            return leaf("turn", [("expression", s.expression), ("rotate", s.direction.rawValue)], indent: indent)
        case .forward(let s):
            return leaf("forward", [("expression", s.expression), ("pen", s.penDown ? "down" : "up")], indent: indent)
        case .home:
            return leaf("home", [], indent: indent)
        case .clear:
            return leaf("clear", [], indent: indent)
        case .pen(let s):
            return leaf("pen", [("color", s.color.rawValue)], indent: indent)
        case .unknown(let xml):
            return "\(pad(indent))\(xml)\n"
        }
    }

    static func escape(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\r": out += "&#13;"
            case "\n": out += "&#10;"
            case "\t": out += "&#9;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
