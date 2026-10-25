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

    init(program: Program = .new()) {
        self.program = program
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
