import Foundation

public enum FPRGError: Error, Equatable, Sendable {
    case notXML(String)
    case notAFlowchart
}

/// Reads `.fprg` files: the XML format used by Flowgorithm, all file versions.
public enum FPRGReader {
    public static func read(_ data: Data) throws -> Program {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [.nodePreserveWhitespace])
        } catch {
            throw FPRGError.notXML(error.localizedDescription)
        }
        guard let root = document.rootElement(), root.name == "flowgorithm" else {
            throw FPRGError.notAFlowchart
        }

        var program = Program(fileVersion: root.attr("fileversion") ?? FPRGWriter.currentFileVersion,
                              attributes: [], functions: [])
        for child in root.childElements {
            switch child.name {
            case "attributes":
                program.attributes = child.childElements
                    .filter { $0.name == "attribute" }
                    .map { ProgramAttribute(name: $0.attr("name") ?? "", value: $0.attr("value") ?? "") }
            case "function":
                program.functions.append(function(from: child))
            default:
                break
            }
        }
        if program.functions.isEmpty {
            program.functions = [Function(name: "Main")]
        }
        // Keep Main first, as the editor expects.
        if let mainIndex = program.functions.firstIndex(where: \.isMain), mainIndex != 0 {
            program.functions.insert(program.functions.remove(at: mainIndex), at: 0)
        }
        return program
    }

    public static func read(contentsOf url: URL) throws -> Program {
        try read(Data(contentsOf: url))
    }

    static func function(from element: XMLElement) -> Function {
        let typeName = element.attr("type") ?? "None"
        var function = Function(name: element.attr("name") ?? "Main",
                                returnType: DataType(fprg: typeName),
                                returnVariable: element.attr("variable") ?? "")
        for child in element.childElements {
            switch child.name {
            case "parameters":
                function.parameters = child.childElements.filter { $0.name == "parameter" }.map {
                    Parameter(name: $0.attr("name") ?? "",
                              type: DataType(fprg: $0.attr("type") ?? "") ?? .integer,
                              isArray: $0.bool("array"))
                }
            case "body":
                function.body = statements(in: child)
            default:
                break
            }
        }
        return function
    }

    static func statements(in element: XMLElement) -> [Statement] {
        element.childElements.map(statement(from:))
    }

    static func statement(from element: XMLElement) -> Statement {
        let a = { (name: String) in element.attr(name) ?? "" }
        switch element.name {
        case "declare":
            // Version 1.x files used `variables` and had no array support.
            let names = element.attr("name") ?? element.attr("variables") ?? ""
            return Statement(.declare(.init(names: names,
                                            type: DataType(fprg: a("type")) ?? .integer,
                                            isArray: element.bool("array"),
                                            size: a("size"))))
        case "assign":
            return Statement(.assign(.init(variable: a("variable"), expression: a("expression"))))
        case "input":
            return Statement(.input(.init(variable: a("variable"))))
        case "output":
            return Statement(.output(.init(expression: a("expression"), newline: element.bool("newline", default: true))))
        case "if":
            let then = element.childElements.first { $0.name == "then" }
            let otherwise = element.childElements.first { $0.name == "else" }
            return Statement(.if(.init(expression: a("expression"),
                                       thenBody: then.map(statements(in:)) ?? [],
                                       elseBody: otherwise.map(statements(in:)) ?? [])))
        case "while":
            return Statement(.while(.init(expression: a("expression"), body: statements(in: element))))
        case "do":
            return Statement(.do(.init(expression: a("expression"), body: statements(in: element))))
        case "for":
            let direction = ForDirection(rawValue: a("direction").lowercased()) ?? .increasing
            let step = element.attr("step") ?? "1"
            return Statement(.for(.init(variable: a("variable"), start: a("start"), end: a("end"),
                                        direction: direction, step: step.isEmpty ? "1" : step,
                                        body: statements(in: element))))
        case "call":
            return Statement(.call(.init(expression: a("expression"))))
        case "comment":
            return Statement(.comment(.init(text: a("text"))))
        case "breakpoint":
            return Statement(.breakpoint(.init(expression: a("expression"), always: element.bool("always", default: true))))
        case "open":
            return Statement(.open(.init(expression: a("expression"), mode: FileMode(rawValue: a("mode").lowercased()) ?? .read)))
        case "close":
            return Statement(.close(.init(mode: FileMode(rawValue: a("mode").lowercased()) ?? .read)))
        case "read":
            return Statement(.read(.init(variable: a("variable"))))
        case "write":
            return Statement(.write(.init(expression: a("expression"))))
        case "turn":
            return Statement(.turn(.init(expression: a("expression"),
                                         direction: TurnDirection(rawValue: a("rotate").lowercased()) ?? .right)))
        case "forward":
            return Statement(.forward(.init(expression: a("expression"), penDown: a("pen").lowercased() != "up")))
        case "home":
            return Statement(.home)
        case "clear":
            return Statement(.clear)
        case "pen":
            return Statement(.pen(.init(color: PenColor(rawValue: a("color").lowercased()) ?? .black)))
        default:
            return Statement(.unknown(xml: element.xmlString.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
}

extension XMLElement {
    var childElements: [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }
    }

    func attr(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }

    func bool(_ name: String, default defaultValue: Bool = false) -> Bool {
        guard let value = attr(name)?.lowercased() else { return defaultValue }
        return value == "true" || value == "1" || value == "yes"
    }
}
