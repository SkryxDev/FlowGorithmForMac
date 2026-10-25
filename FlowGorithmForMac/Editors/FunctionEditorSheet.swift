import FlowCore
import SwiftUI

/// Creates or edits a function's name, parameters and return value.
struct FunctionEditorSheet: View {
    @State var function: Function
    let isNew: Bool
    let existingNames: [String]
    let onSave: (Function) -> Void

    @Environment(\.dismiss) private var dismiss

    var nameProblem: String? {
        let name = function.name.trimmingCharacters(in: .whitespaces)
        if let problem = Identifier.validate(name) {
            return ErrorText.message(RuntimeError(.invalidName(name, problem)))
        }
        if existingNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return String(localized: "A function with this name already exists.")
        }
        return nil
    }

    var parameterProblem: String? {
        var seen = Set<String>()
        for parameter in function.parameters {
            if let problem = Identifier.validate(parameter.name) {
                return ErrorText.message(RuntimeError(.invalidName(parameter.name, problem)))
            }
            if !seen.insert(parameter.name.lowercased()).inserted {
                return String(localized: "Two parameters are called “\(parameter.name)”.")
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "function")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.modern.palette(for: .call).fill.gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "New Function" : "Edit Function")
                        .font(.title3.weight(.semibold))
                    Text("Functions take parameters and can return a value through a variable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            Form {
                Section {
                    TextField("Name", text: $function.name, prompt: Text("Average"))
                    if let nameProblem {
                        Label(nameProblem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Parameters") {
                    if function.parameters.isEmpty {
                        Text("No parameters")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($function.parameters) { $parameter in
                        HStack {
                            TextField("Name", text: $parameter.name, prompt: Text("value"))
                                .labelsHidden()
                            Picker("Type", selection: $parameter.type) {
                                ForEach(DataType.allCases, id: \.self) { Text(ShapeText.typeName($0)).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                            Toggle("Array", isOn: $parameter.isArray)
                                .toggleStyle(.checkbox)
                            Button {
                                function.parameters.removeAll { $0.id == parameter.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { function.parameters.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add Parameter", systemImage: "plus") {
                        function.parameters.append(Parameter(name: "", type: .integer))
                    }
                    if let parameterProblem {
                        Label(parameterProblem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Return") {
                    Picker("Returns", selection: $function.returnType) {
                        Text("Nothing").tag(DataType?.none)
                        ForEach(DataType.allCases, id: \.self) { Text(ShapeText.typeName($0)).tag(DataType?.some($0)) }
                    }
                    if function.returnType != nil {
                        TextField("Return variable", text: $function.returnVariable, prompt: Text("result"))
                        Text("Declare this variable inside the function and assign it: its value is returned at the end.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "OK") {
                    function.name = function.name.trimmingCharacters(in: .whitespaces)
                    if function.returnType == nil { function.returnVariable = "" }
                    onSave(function)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(nameProblem != nil || parameterProblem != nil)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }
}

/// Name, authors and description stored in the file.
struct ProgramInfoSheet: View {
    @Binding var program: Program
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var authors = ""
    @State private var about = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Program") {
                    TextField("Name", text: $name)
                    TextField("Authors", text: $authors)
                }
                Section("Description") {
                    TextEditor(text: $about)
                        .frame(minHeight: 100)
                        .font(.body)
                }
                if !program[attribute: "saved"].isEmpty {
                    Section {
                        LabeledContent("Last saved", value: program[attribute: "saved"])
                        LabeledContent("Functions", value: "\(program.functions.count)")
                        LabeledContent("Shapes", value: "\(program.functions.reduce(0) { $0 + $1.body.flattened.count })")
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    program.name = name
                    program.authors = authors
                    program.about = about.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
            .padding(16)
        }
        .frame(width: 460, height: 460)
        .onAppear {
            name = program.name
            authors = program.authors
            about = program.about.replacingOccurrences(of: "\r\n", with: "\n")
        }
    }
}
