// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

public enum FPRGError: Error, Equatable, Sendable {
    case notXML(String)
    case notAFlowchart
    case tooDeeplyNested
}

/// Reads `.fprg` files: the XML format used by Flowgorithm, all file versions.
public enum FPRGReader {
    /// Shapes nested deeper than this are refused: drawing, checking and running a chart all
    /// recurse through its blocks, and a crafted file could otherwise crash the app.
    static let maxNesting = 100

    /// External entities are never loaded: a crafted file could otherwise pull the content
    /// of other files on the Mac into the flowchart, to be saved and sent back with it.
    static var parseOptions: XMLNode.Options { [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever] }

    public static func read(_ data: Data) throws -> Program {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: parseOptions)
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
                program.functions.append(try function(from: child))
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

    static func function(from element: XMLElement) throws -> Function {
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
                function.body = try statements(in: child)
            default:
                break
            }
        }
        return function
    }

    static func statements(in element: XMLElement, depth: Int = 0) throws -> [Statement] {
        guard depth < maxNesting else { throw FPRGError.tooDeeplyNested }
        var result: [Statement] = []
        for child in element.childElements {
            result.append(try statement(from: child, depth: depth))
        }
        return result
    }

    /// Recursion goes through `statements`, `statement` and `nested` only, which keep their
    /// stack frames small: a file nested up to `maxNesting` levels must fit in the small stack
    /// of a background thread, where documents may be read.
    static func statement(from element: XMLElement, depth: Int) throws -> Statement {
        switch element.name {
        case "if", "while", "do", "for": try nested(element, depth: depth)
        default: shape(from: element)
        }
    }

    @inline(never)
    static func nested(_ element: XMLElement, depth: Int) throws -> Statement {
        let expression = element.attr("expression") ?? ""
        switch element.name {
        case "if":
            var thenBody: [Statement] = [], elseBody: [Statement] = []
            if let then = element.childElements.first(where: { $0.name == "then" }) {
                thenBody = try statements(in: then, depth: depth + 1)
            }
            if let otherwise = element.childElements.first(where: { $0.name == "else" }) {
                elseBody = try statements(in: otherwise, depth: depth + 1)
            }
            return Statement(.if(.init(expression: expression, thenBody: thenBody, elseBody: elseBody)))
        case "while":
            return Statement(.while(.init(expression: expression, body: try statements(in: element, depth: depth + 1))))
        case "do":
            return Statement(.do(.init(expression: expression, body: try statements(in: element, depth: depth + 1))))
        default:
            return try forLoop(element, depth: depth)
        }
    }

    @inline(never)
    static func forLoop(_ element: XMLElement, depth: Int) throws -> Statement {
        let body = try statements(in: element, depth: depth + 1)
        let a = { (name: String) in element.attr(name) ?? "" }
        let direction = ForDirection(rawValue: a("direction").lowercased()) ?? .increasing
        let step = element.attr("step") ?? "1"
        return Statement(.for(.init(variable: a("variable"), start: a("start"), end: a("end"),
                                    direction: direction, step: step.isEmpty ? "1" : step, body: body)))
    }

    /// Every shape without nested shapes.
    @inline(never)
    static func shape(from element: XMLElement) -> Statement {
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
