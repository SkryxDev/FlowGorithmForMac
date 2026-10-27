// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// The program's functions, as a menu in the toolbar: shows the function on screen, switches
/// between them and adds, edits or deletes them. Main always comes first.
struct FunctionMenu: View {
    @Binding var program: Program
    @Bindable var editor: EditorModel
    var locked: Bool

    var current: Function? { editor.currentFunction(in: program) }

    var body: some View {
        Menu {
            Picker("Function", selection: Binding(
                get: { current?.id },
                set: { id in
                    editor.functionID = id
                    editor.selection = nil
                })) {
                ForEach(program.functions) { function in
                    Label(Self.title(function, withSignature: true), systemImage: Self.symbol(function))
                        .tag(Optional(function.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Add Function…", systemImage: "plus") { editor.isAddingFunction = true }
                .disabled(locked)
            if let current, !current.isMain {
                Button("Edit Function…", systemImage: "pencil") { editor.editingFunction = current }
                    .disabled(locked)
                Button("Delete Function", systemImage: "trash", role: .destructive) {
                    editor.deleteFunction(current.id, from: $program)
                }
                .disabled(locked)
            }
            Divider()
            Button("Program Info…", systemImage: "info.circle") { editor.showsProgramInfo = true }
        } label: {
            if let current {
                Label(Self.title(current, withSignature: false), systemImage: Self.symbol(current))
                    .labelStyle(.titleAndIcon)
            }
        }
        .help("Functions")
    }

    static func symbol(_ function: Function) -> String {
        function.isMain ? "play.circle.fill" : "function"
    }

    static func title(_ function: Function, withSignature: Bool) -> String {
        if function.isMain { return String(localized: "Main") }
        guard withSignature else { return function.name }
        let params = function.parameters.map { "\(ShapeText.typeName($0.type))\($0.isArray ? "[]" : "") \($0.name)" }.joined(separator: ", ")
        let returns = function.returnType.map { " → \(ShapeText.typeName($0))" } ?? ""
        return "\(function.name)(\(params))\(returns)"
    }
}
