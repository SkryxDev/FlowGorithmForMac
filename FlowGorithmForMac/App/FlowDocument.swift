import FlowCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let flowchart = UTType(importedAs: "org.flowgorithm.fprg", conformingTo: .xml)
}

nonisolated struct FlowDocument: FileDocument {
    var program: Program

    static let readableContentTypes: [UTType] = [.flowchart, .xml]
    static let writableContentTypes: [UTType] = [.flowchart]

    init(program: Program = FlowDocument.newProgram()) {
        self.program = program
    }

    /// An empty flowchart, signed with the user's name unless they turned that off in Settings.
    static func newProgram() -> Program {
        let fillAuthor = UserDefaults.standard.object(forKey: SettingsKey.fillAuthor) as? Bool ?? true
        return .new(authors: fillAuthor ? NSFullUserName() : "")
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            program = try FPRGReader.read(data)
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: FPRGWriter.write(program, updatingSavedDate: Date()))
    }
}
