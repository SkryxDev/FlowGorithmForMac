import Foundation

public struct Parameter: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: DataType
    public var isArray: Bool

    public init(id: UUID = UUID(), name: String, type: DataType, isArray: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.isArray = isArray
    }
}

public struct Function: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// `nil` means the function returns nothing ("None" in the file format).
    public var returnType: DataType?
    public var returnVariable: String
    public var parameters: [Parameter]
    public var body: [Statement]

    public init(id: UUID = UUID(), name: String, returnType: DataType? = nil, returnVariable: String = "",
                parameters: [Parameter] = [], body: [Statement] = []) {
        self.id = id
        self.name = name
        self.returnType = returnType
        self.returnVariable = returnVariable
        self.parameters = parameters
        self.body = body
    }

    public var isMain: Bool { name.caseInsensitiveCompare("Main") == .orderedSame }
}

public struct ProgramAttribute: Hashable, Sendable {
    public var name: String
    public var value: String
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// A whole flowchart program: attributes plus its functions (Main first).
public struct Program: Hashable, Sendable {
    public var fileVersion: String
    public var attributes: [ProgramAttribute]
    public var functions: [Function]

    public init(fileVersion: String = FPRGWriter.currentFileVersion,
                attributes: [ProgramAttribute] = [],
                functions: [Function] = [Function(name: "Main")]) {
        self.fileVersion = fileVersion
        self.attributes = attributes
        self.functions = functions
    }

    public subscript(attribute name: String) -> String {
        get { attributes.first { $0.name == name }?.value ?? "" }
        set {
            if let index = attributes.firstIndex(where: { $0.name == name }) {
                attributes[index].value = newValue
            } else {
                attributes.append(ProgramAttribute(name: name, value: newValue))
            }
        }
    }

    public var name: String {
        get { self[attribute: "name"] }
        set { self[attribute: "name"] = newValue }
    }

    public var authors: String {
        get { self[attribute: "authors"] }
        set { self[attribute: "authors"] = newValue }
    }

    public var about: String {
        get { self[attribute: "about"] }
        set { self[attribute: "about"] = newValue }
    }

    public var main: Function? { functions.first(where: \.isMain) ?? functions.first }

    public func function(named name: String) -> Function? {
        functions.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func functionIndex(id: Function.ID) -> Int? {
        functions.firstIndex { $0.id == id }
    }

    /// Finds which function contains a statement.
    public func function(containing statementID: Statement.ID) -> Function? {
        functions.first { $0.body.statement(withID: statementID) != nil }
    }

    /// An empty program. `authors` defaults to the Mac account's full name, as Flowgorithm does.
    public static func new(authors: String = NSFullUserName()) -> Program {
        var program = Program()
        program.attributes = [
            ProgramAttribute(name: "name", value: ""),
            ProgramAttribute(name: "authors", value: authors),
            ProgramAttribute(name: "about", value: ""),
        ]
        return program
    }
}
