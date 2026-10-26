import Foundation

/// An error raised while checking or running a program. The app turns `kind` into a localized message.
public struct RuntimeError: Error, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case syntax(ExpressionError, source: String)
        case invalidName(String, Identifier.Problem)
        case undeclaredVariable(String)
        case alreadyDeclared(String)
        case unassignedVariable(String)
        case notAnArray(String)
        case isAnArray(String)
        case invalidArraySize(Int64)
        case indexOutOfBounds(name: String, index: Int64, size: Int)
        case typeMismatch(operation: String, left: DataType, right: DataType?)
        case cannotAssign(value: DataType, variable: String, variableType: DataType)
        case conditionNotBoolean(DataType)
        case divisionByZero
        case overflow
        case unknownFunction(String)
        case wrongArgumentCount(function: String, expected: Int, found: Int)
        case argumentMustBeArray(function: String, parameter: String)
        case argumentType(function: String, parameter: String, expected: DataType, found: DataType)
        case noReturnValue(String)
        case returnVariableMissing(function: String, variable: String)
        case mathDomain(function: String)
        case invalidConversion(value: String, to: DataType)
        case invalidArgument(function: String)
        case stackOverflow(limit: Int)
        case noMainFunction
        case fileNotOpen
        case fileAlreadyOpen
        case fileWrongMode
        case fileError(String)
        /// The user refused access to a file outside the flowchart's folder.
        case fileAccessDenied(String)
        /// The path names a folder, a device or something else that isn't a plain file.
        case notAFile(String)
        case fileTooLarge(String)
        case endOfFile
        case incompleteShape
        /// Arrays or texts grew past what the interpreter allows.
        case outOfMemory
        case duplicateFunction(String)
    }

    public var kind: Kind
    /// The shape that failed, when known.
    public var statementID: Statement.ID?
    public var functionName: String?

    public init(_ kind: Kind, statementID: Statement.ID? = nil, functionName: String? = nil) {
        self.kind = kind
        self.statementID = statementID
        self.functionName = functionName
    }
}
