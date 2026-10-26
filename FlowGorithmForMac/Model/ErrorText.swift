import FlowCore
import Foundation

/// Friendly, localized explanations for errors, written for students.
enum ErrorText {
    static func message(_ error: RuntimeError) -> String {
        switch error.kind {
        case .syntax(let e, let source):
            return syntax(e, source: source)
        case .invalidName(let name, let problem):
            switch problem {
            case .empty: return String(localized: "A name is missing.")
            case .invalidCharacters: return String(localized: "“\(name)” isn't a valid name: use a letter followed by letters or digits, no spaces or symbols.")
            case .reserved: return String(localized: "“\(name)” is a reserved word and can't be used as a name.")
            }
        case .undeclaredVariable(let name):
            return String(localized: "The variable “\(name)” doesn't exist. Declare it first with a Declare shape.")
        case .alreadyDeclared(let name):
            return String(localized: "The variable “\(name)” is already declared.")
        case .unassignedVariable(let name):
            return String(localized: "The variable “\(name)” has no value yet. Assign it or read it with Input first.")
        case .notAnArray(let name):
            return String(localized: "“\(name)” isn't an array, so it can't be used with [ ].")
        case .isAnArray(let name):
            return String(localized: "“\(name)” is an array: use an index, as in \(name)[0].")
        case .invalidArraySize(let size):
            return String(localized: "\(size) isn't a valid array size.")
        case .indexOutOfBounds(let name, let index, let size):
            return String(localized: "Index \(index) is outside “\(name)”, which has \(size) elements (0 to \(max(size - 1, 0))).")
        case .typeMismatch(let operation, let left, let right):
            if let right {
                return String(localized: "“\(operation)” can't work on \(ShapeText.typeName(left)) and \(ShapeText.typeName(right)). To join text use &.")
            }
            return String(localized: "“\(operation)” can't work on a \(ShapeText.typeName(left)) value.")
        case .cannotAssign(let value, let variable, let variableType):
            return String(localized: "A \(ShapeText.typeName(value)) value can't be stored in “\(variable)”, which is \(ShapeText.typeName(variableType)).")
        case .conditionNotBoolean(let type):
            return String(localized: "The condition must be true or false, but it's a \(ShapeText.typeName(type)).")
        case .divisionByZero:
            return String(localized: "Division by zero.")
        case .overflow:
            return String(localized: "The number is too big.")
        case .unknownFunction(let name):
            return String(localized: "The function “\(name)” doesn't exist.")
        case .wrongArgumentCount(let function, let expected, let found):
            return String(localized: "“\(function)” needs \(expected) arguments, but got \(found).")
        case .argumentMustBeArray(let function, let parameter):
            return String(localized: "The argument for “\(parameter)” in “\(function)” must be the name of an array.")
        case .argumentType(let function, let parameter, let expected, let found):
            return String(localized: "“\(parameter)” in “\(function)” expects \(ShapeText.typeName(expected)), but got \(ShapeText.typeName(found)).")
        case .noReturnValue(let name):
            return String(localized: "“\(name)” doesn't return a value, so it can't be used in an expression. Use a Call shape.")
        case .returnVariableMissing(let function, let variable):
            return variable.isEmpty
                ? String(localized: "The function “\(function)” has no return variable.")
                : String(localized: "The function “\(function)” must declare its return variable “\(variable)”.")
        case .mathDomain(let function):
            return String(localized: "\(function): the value is outside the allowed range.")
        case .invalidConversion(let value, let type):
            return String(localized: "“\(value)” can't be converted to \(ShapeText.typeName(type)).")
        case .invalidArgument(let function):
            return String(localized: "Invalid argument for \(function).")
        case .stackOverflow(let limit):
            return String(localized: "Stack overflow: more than \(limit) nested calls. Is there a recursion that never ends?")
        case .noMainFunction:
            return String(localized: "The program has no Main function.")
        case .fileNotOpen:
            return String(localized: "No file is open. Use an Open shape first.")
        case .fileAlreadyOpen:
            return String(localized: "A file is already open. Close it first.")
        case .fileWrongMode:
            return String(localized: "The file is open in the wrong mode for this operation.")
        case .fileError(let name):
            return String(localized: "Can't access the file “\(name)”.")
        case .fileAccessDenied(let path):
            return String(localized: "Access to “\(path)” was blocked.")
        case .notAFile(let name):
            return String(localized: "“\(name)” isn't a text file: it's a folder or a special file.")
        case .fileTooLarge(let name):
            return String(localized: "The file “\(name)” is too large (over 32 MB).")
        case .endOfFile:
            return String(localized: "The end of the file has been reached. Check EOF() before reading.")
        case .incompleteShape:
            return String(localized: "This shape is empty: double-click it to fill it in.")
        case .outOfMemory:
            return String(localized: "The program uses too much memory: its arrays or texts are too large.")
        case .duplicateFunction(let name):
            return String(localized: "There are two functions called “\(name)”.")
        }
    }

    static func syntax(_ error: ExpressionError, source: String) -> String {
        switch error.kind {
        case .empty:
            return String(localized: "This shape is empty: double-click it to fill it in.")
        case .invalidCharacter(let c):
            return String(localized: "Unexpected character “\(c)” in “\(source)”.")
        case .unterminatedString:
            return String(localized: "A text is missing its closing quote in “\(source)”.")
        case .invalidNumber(let n):
            return String(localized: "“\(n)” isn't a valid number.")
        case .unexpected(let token):
            return token == "end"
                ? String(localized: "“\(source)” ends too early: something is missing.")
                : String(localized: "Unexpected “\(token)” in “\(source)”.")
        case .expected(let what, let found):
            return String(localized: "Expected “\(what)” but found “\(found)” in “\(source)”.")
        case .reservedWord(let word):
            return String(localized: "“\(word)” is a reserved word.")
        case .notAVariable(let text):
            return String(localized: "“\(text)” isn't a variable name.")
        case .tooComplex:
            return String(localized: "This expression is too long or too deeply nested.")
        }
    }
}
