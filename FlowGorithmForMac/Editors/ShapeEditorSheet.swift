// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// Edits one shape. Changes apply only when the user presses OK.
struct ShapeEditorSheet: View {
    @State var statement: Statement
    let function: Function?
    let theme: Theme
    let onSave: (Statement) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Variables declared anywhere in the function, plus its parameters, for the insert menus.
    var variables: [VariablesSnapshot.Variable] {
        guard let function else { return [] }
        var result = function.parameters.map {
            VariablesSnapshot.Variable(name: $0.name, type: $0.type, value: nil, elements: $0.isArray ? [] : nil)
        }
        for s in function.body.flattened {
            if case .declare(let d) = s.kind {
                result += d.nameList.map { VariablesSnapshot.Variable(name: $0, type: d.type, value: nil, elements: d.isArray ? [] : nil) }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.name.lowercased()).inserted }
    }

    var template: StatementTemplate { statement.template ?? .comment }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fields
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    onSave(statement)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
            .padding(16)
        }
        .frame(width: 480)
        .frame(minHeight: 260)
    }

    var header: some View {
        HStack(spacing: 14) {
            ShapePreview(template: template, theme: theme)
                .frame(width: 96, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(ShapeText.name(template))
                    .font(.title3.weight(.semibold))
                Text(ShapeText.help(template))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    @ViewBuilder
    var fields: some View {
        switch statement.kind {
        case .declare:
            DeclareFields(declare: binding(\.declare))
        case .assign:
            ExpressionField(title: "Variable", text: binding(\.assign).variable, kind: .variable, prompt: "total", variables: variables)
            ExpressionField(title: "Expression", text: binding(\.assign).expression, prompt: "total + 1", variables: variables)
        case .input:
            ExpressionField(title: "Variable", text: binding(\.input).variable, kind: .variable, prompt: "age", variables: variables)
        case .output:
            ExpressionField(title: "Expression", text: binding(\.output).expression, prompt: "\"Hello \" & name", variables: variables)
            Toggle("Start a new line after the output", isOn: binding(\.output).newline)
        case .if:
            ExpressionField(title: "Condition", text: binding(\.ifShape).expression, prompt: "age >= 18", variables: variables)
        case .while:
            ExpressionField(title: "Condition", text: binding(\.whileShape).expression, prompt: "n <= 10", variables: variables)
        case .do:
            ExpressionField(title: "Repeat while", text: binding(\.doShape).expression, prompt: "answer <> \"yes\"", variables: variables)
        case .for:
            ForFields(loop: binding(\.forShape), variables: variables)
        case .call:
            ExpressionField(title: "Function call", text: binding(\.call).expression, kind: .call, prompt: "Greet(name)", variables: variables)
        case .comment:
            ExpressionField(title: "Comment", text: binding(\.comment).text, kind: .text)
        case .breakpoint:
            BreakpointFields(breakpoint: binding(\.breakpoint), variables: variables)
        case .open:
            ExpressionField(title: "File name", text: binding(\.open).expression, prompt: "\"data.txt\"", variables: variables)
            Picker("Mode", selection: binding(\.open).mode) {
                Text("Read").tag(FileMode.read)
                Text("Write").tag(FileMode.write)
                Text("Append").tag(FileMode.append)
            }
            .pickerStyle(.segmented)
        case .close:
            Text("Closes the file opened with the Open shape.")
                .foregroundStyle(.secondary)
        case .read:
            ExpressionField(title: "Variable", text: binding(\.read).variable, kind: .variable, prompt: "line", variables: variables)
        case .write:
            ExpressionField(title: "Expression", text: binding(\.write).expression, prompt: "total", variables: variables)
        case .turn:
            Picker("Direction", selection: binding(\.turn).direction) {
                Label("Left", systemImage: "arrow.counterclockwise").tag(TurnDirection.left)
                Label("Right", systemImage: "arrow.clockwise").tag(TurnDirection.right)
            }
            .pickerStyle(.segmented)
            ExpressionField(title: "Degrees", text: binding(\.turn).expression, prompt: "90", variables: variables)
        case .forward:
            ExpressionField(title: "Distance", text: binding(\.forward).expression, prompt: "100", variables: variables)
            Picker("Pen", selection: binding(\.forward).penDown) {
                Label("Draw a line", systemImage: "pencil.line").tag(true)
                Label("Just move", systemImage: "arrow.up.and.down.and.arrow.left.and.right").tag(false)
            }
            .pickerStyle(.segmented)
        case .pen:
            PenFields(color: binding(\.pen).color)
        case .home, .clear, .unknown:
            EmptyView()
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<Statement, Value?>) -> Binding<Value> {
        Binding(
            get: { statement[keyPath: keyPath]! },
            set: { statement[keyPath: keyPath] = $0 }
        )
    }
}

struct DeclareFields: View {
    @Binding var declare: Statement.Declare

    var body: some View {
        ExpressionField(title: "Variable names", text: $declare.names, kind: .names, prompt: "x, y, total")
        VStack(alignment: .leading, spacing: 8) {
            Text("Type")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Picker("Type", selection: $declare.type) {
                ForEach(DataType.allCases, id: \.self) { type in
                    Text(ShapeText.typeName(type)).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        Toggle("Array", isOn: $declare.isArray.animation(.snappy))
        if declare.isArray {
            ExpressionField(title: "Array size", text: $declare.size, prompt: "10")
        }
    }
}

struct ForFields: View {
    @Binding var loop: Statement.ForLoop
    let variables: [VariablesSnapshot.Variable]

    var body: some View {
        ExpressionField(title: "Variable", text: $loop.variable, kind: .variable, prompt: "i", variables: variables.filter { $0.type.isNumeric && $0.elements == nil })
        HStack(alignment: .top, spacing: 12) {
            ExpressionField(title: "Start value", text: $loop.start, prompt: "1", variables: variables)
            ExpressionField(title: "End value", text: $loop.end, prompt: "10", variables: variables)
        }
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Direction")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Direction", selection: $loop.direction) {
                    Text("Increasing").tag(ForDirection.increasing)
                    Text("Decreasing").tag(ForDirection.decreasing)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ExpressionField(title: "Step", text: $loop.step, prompt: "1", variables: variables)
                .frame(width: 140)
        }
    }
}

struct BreakpointFields: View {
    @Binding var breakpoint: Statement.Breakpoint
    let variables: [VariablesSnapshot.Variable]

    var body: some View {
        Picker("Pause", selection: $breakpoint.always.animation(.snappy)) {
            Text("Always").tag(true)
            Text("Only when a condition is true").tag(false)
        }
        .pickerStyle(.radioGroup)
        if !breakpoint.always {
            ExpressionField(title: "Condition", text: $breakpoint.expression, kind: .optionalExpression, prompt: "i = 5", variables: variables)
        }
    }
}

struct PenFields: View {
    @Binding var color: PenColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
            ForEach(PenColor.allCases, id: \.self) { pen in
                Button {
                    color = pen
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(pen.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if color == pen {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: color == pen ? 3 : 0).padding(-4))
                        Text(ShapeText.colorName(pen))
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Key paths into each kind of statement, so the editor can bind straight to the fields.
extension Statement {
    var declare: Declare? {
        get { if case .declare(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .declare(newValue) } }
    }
    var assign: Assign? {
        get { if case .assign(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .assign(newValue) } }
    }
    var input: Input? {
        get { if case .input(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .input(newValue) } }
    }
    var output: Output? {
        get { if case .output(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .output(newValue) } }
    }
    var ifShape: If? {
        get { if case .if(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .if(newValue) } }
    }
    var whileShape: While? {
        get { if case .while(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .while(newValue) } }
    }
    var doShape: DoLoop? {
        get { if case .do(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .do(newValue) } }
    }
    var forShape: ForLoop? {
        get { if case .for(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .for(newValue) } }
    }
    var call: Call? {
        get { if case .call(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .call(newValue) } }
    }
    var comment: Comment? {
        get { if case .comment(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .comment(newValue) } }
    }
    var breakpoint: Breakpoint? {
        get { if case .breakpoint(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .breakpoint(newValue) } }
    }
    var open: OpenFile? {
        get { if case .open(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .open(newValue) } }
    }
    var read: ReadFile? {
        get { if case .read(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .read(newValue) } }
    }
    var write: WriteFile? {
        get { if case .write(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .write(newValue) } }
    }
    var turn: Turn? {
        get { if case .turn(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .turn(newValue) } }
    }
    var forward: Forward? {
        get { if case .forward(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .forward(newValue) } }
    }
    var pen: Pen? {
        get { if case .pen(let s) = kind { s } else { nil } }
        set { if let newValue { kind = .pen(newValue) } }
    }
}
