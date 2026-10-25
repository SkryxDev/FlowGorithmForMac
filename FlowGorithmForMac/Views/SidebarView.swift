import FlowCore
import SwiftUI

/// Lists the program's functions. Main always comes first.
struct SidebarView: View {
    @Binding var program: Program
    @Bindable var editor: EditorModel
    var locked: Bool

    var body: some View {
        List(selection: Binding(
            get: { editor.currentFunction(in: program)?.id },
            set: { id in
                editor.functionID = id
                editor.selection = nil
            })) {
            Section {
                ForEach(program.functions) { function in
                    FunctionRow(function: function)
                        .tag(function.id)
                        .contextMenu {
                            if function.isMain {
                                Button("Program Info…", systemImage: "info.circle") { editor.showsProgramInfo = true }
                            } else {
                                Button("Edit Function…", systemImage: "pencil") { editor.editingFunction = function }
                                    .disabled(locked)
                                Button("Delete Function", systemImage: "trash", role: .destructive) {
                                    editor.deleteFunction(function.id, from: $program)
                                }
                                .disabled(locked)
                            }
                        }
                }
            } header: {
                Text("Functions")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    editor.isAddingFunction = true
                } label: {
                    Label("Add Function", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(locked)
                Button {
                    editor.showsProgramInfo = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.name.isEmpty ? String(localized: "Untitled program") : program.name)
                            .font(.headline)
                            .lineLimit(1)
                        if !program.authors.isEmpty {
                            Text(program.authors)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Program Info")
            }
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
    }
}

private struct FunctionRow: View {
    let function: Function

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: function.isMain ? "play.circle.fill" : "function")
                .foregroundStyle(function.isMain ? Color.green : Color.purple)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(function.isMain ? String(localized: "Main") : function.name)
                    .fontWeight(.medium)
                if !function.isMain {
                    Text(signature)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    var signature: String {
        let params = function.parameters.map { "\(ShapeText.typeName($0.type))\($0.isArray ? "[]" : "") \($0.name)" }.joined(separator: ", ")
        let returns = function.returnType.map { " → \(ShapeText.typeName($0))" } ?? ""
        return "(\(params))\(returns)"
    }
}
