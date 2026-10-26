// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation
import Testing
@testable import FlowCore

/// Programs use files next to their flowchart freely and need the user's permission for any other.
struct FileAccessTests {
    @Test func filesInTheFolderOpenWithoutAsking() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let p = program([openFile("notes.txt", .write), writeLine("1"), closeFile()])
        let result = await run(p, baseDirectory: folder)
        #expect(result.error == nil)
        #expect(result.fileRequests.isEmpty)
        #expect(try String(contentsOf: folder.appendingPathComponent("notes.txt"), encoding: .utf8) == "1\n")
    }

    @Test func filesElsewhereNeedPermission() async throws {
        let folder = try temporaryFolder(), elsewhere = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let target = elsewhere.appendingPathComponent("other.txt")
        let p = program([openFile(target.path, .write), writeLine("\"hi\""), closeFile()])

        let denied = await run(p, baseDirectory: folder, allowFiles: false)
        #expect(denied.fileRequests.count == 1)
        guard case .fileAccessDenied = denied.error?.kind else {
            Issue.record("expected fileAccessDenied, got \(String(describing: denied.error))")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))

        let allowed = await run(p, baseDirectory: folder, allowFiles: true)
        #expect(allowed.error == nil)
        #expect(try String(contentsOf: target, encoding: .utf8) == "hi\n")
    }

    @Test func parentFolderPathsNeedPermission() async throws {
        let parent = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("chart")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = await run(program([openFile("../escape.txt", .write), closeFile()]), baseDirectory: folder)
        #expect(result.fileRequests.count == 1)
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("escape.txt").path))
    }

    @Test func linksPointingElsewhereNeedPermission() async throws {
        let folder = try temporaryFolder(), elsewhere = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let secret = elsewhere.appendingPathComponent("secret.txt")
        try "keep out\n".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("data.txt"), withDestinationURL: secret)

        let p = program([
            declare("line", .string),
            openFile("data.txt", .read),
            Statement(.read(.init(variable: "line"))),
            output("line"),
            closeFile(),
        ])
        let result = await run(p, baseDirectory: folder)
        #expect(result.fileRequests.count == 1)
        #expect(result.output.isEmpty)
    }

    @Test func unsavedFlowchartsAskForEveryFile() async throws {
        let elsewhere = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let p = program([openFile(elsewhere.appendingPathComponent("a.txt").path, .write), closeFile()])
        let result = await run(p, baseDirectory: nil, allowFiles: true)
        #expect(result.fileRequests.count == 1)
        #expect(result.error == nil)
    }

    @Test func permissionIsAskedOncePerFile() async throws {
        let folder = try temporaryFolder(), elsewhere = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let path = elsewhere.appendingPathComponent("log.txt").path
        let p = program([
            openFile(path, .append), writeLine("1"), closeFile(),
            openFile(path, .append), writeLine("2"), closeFile(),
        ])
        let result = await run(p, baseDirectory: folder, allowFiles: true)
        #expect(result.fileRequests.count == 1)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "1\n2\n")
    }

    @Test func foldersCantBeOpened() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let result = await run(program([openFile("sub", .read)]), baseDirectory: folder)
        guard case .notAFile = result.error?.kind else {
            Issue.record("expected notAFile, got \(String(describing: result.error))")
            return
        }
    }

    @Test func appendKeepsTextThatIsNotUTF8() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("old.txt")
        // "caffè" in Windows-1252, as older files from school computers often are.
        let original = Data([0x63, 0x61, 0x66, 0x66, 0xE8, 0x0D, 0x0A])
        try original.write(to: url)
        let result = await run(program([openFile("old.txt", .append), writeLine("\"new\""), closeFile()]), baseDirectory: folder)
        #expect(result.error == nil)
        #expect(try Data(contentsOf: url) == original + Data("new\n".utf8))
    }

    @Test func appendStartsOnANewLine() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("list.txt")
        try "a".write(to: url, atomically: true, encoding: .utf8)
        _ = await run(program([openFile("list.txt", .append), writeLine("\"b\""), closeFile()]), baseDirectory: folder)
        #expect(try String(contentsOf: url, encoding: .utf8) == "a\nb\n")
    }

    @Test func readsWindowsFiles() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Windows-1252 text with CRLF line endings.
        try Data([0x75, 0x6E, 0x6F, 0x0D, 0x0A, 0x70, 0x65, 0x72, 0xF2, 0x0D, 0x0A]).write(to: folder.appendingPathComponent("w.txt"))
        let p = program([
            declare("line", .string),
            openFile("w.txt", .read),
            Statement(.while(.init(expression: "not EOF()", body: [Statement(.read(.init(variable: "line"))), output("line")]))),
            closeFile(),
        ])
        let result = await run(p, baseDirectory: folder)
        #expect(result.error == nil)
        #expect(result.output == "uno\nperò\n")
    }

    @Test func arraysHaveAMemoryLimit() async {
        let names = (1...11).map { "a\($0)" }.joined(separator: ", ")
        let result = await run(program([declare(names, .integer, array: "1000000")]))
        #expect(result.error?.kind == .outOfMemory)
    }

    @Test func textsHaveALengthLimit() async {
        let p = program([
            declare("s", .string),
            declare("i", .integer),
            assign("s", "\"x\""),
            Statement(.for(.init(variable: "i", start: "1", end: "30", body: [assign("s", "s & s")]))),
        ])
        #expect(await run(p).error?.kind == .outOfMemory)
    }

    @Test func duplicateFunctionNamesAreAnError() async {
        let p = program([], functions: [Function(name: "Sum"), Function(name: "SUM")])
        guard case .duplicateFunction = await run(p).error?.kind else {
            Issue.record("expected duplicateFunction")
            return
        }
    }
}
