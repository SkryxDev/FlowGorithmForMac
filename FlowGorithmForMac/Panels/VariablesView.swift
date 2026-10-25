import FlowCore
import SwiftUI

/// Shows every variable of each active function call, colored by type.
struct VariablesView: View {
    var session: RunSession

    var body: some View {
        let frames = session.variables.frames
        if frames.allSatisfy({ $0.variables.isEmpty }) {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Variables appear here while the program runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List {
                ForEach(frames.reversed()) { frame in
                    Section {
                        ForEach(frame.variables) { variable in
                            VariableRow(variable: variable)
                        }
                    } header: {
                        Label(frame.function, systemImage: frame.id == frames.count - 1 ? "play.fill" : "function")
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct VariableRow: View {
    let variable: VariablesSnapshot.Variable
    @State private var expanded = true

    var body: some View {
        if let elements = variable.elements {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(Array(elements.enumerated()), id: \.offset) { index, value in
                    HStack {
                        Text("[\(index)]")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        ValueText(value: value, type: variable.type)
                    }
                }
            } label: {
                HStack {
                    TypeBadge(type: variable.type, isArray: true)
                    Text(variable.name).fontWeight(.medium)
                    Spacer()
                    Text("\(elements.count) elements")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack {
                TypeBadge(type: variable.type, isArray: false)
                Text(variable.name).fontWeight(.medium)
                Spacer()
                ValueText(value: variable.value, type: variable.type)
            }
        }
    }
}

private struct ValueText: View {
    let value: Value?
    let type: DataType

    var body: some View {
        if let value {
            Text(type == .string ? "\"\(value.displayString)\"" : value.displayString)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(type.color)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
                .help("No value yet")
        }
    }
}

struct TypeBadge: View {
    let type: DataType
    let isArray: Bool

    var body: some View {
        Text(String(ShapeText.typeName(type).prefix(isArray ? 3 : 3)) + (isArray ? "[]" : ""))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(type.color.gradient, in: Capsule())
            .help(ShapeText.typeName(type))
    }
}
