import AppKit
import FlowCore
import SwiftUI
import UniformTypeIdentifiers

/// The flowchart translated to a real programming language, kept in sync with the chart.
struct SourceCodeView: View {
    let program: Program
    @Bindable var editor: EditorModel
    var session: RunSession
    @AppStorage(SettingsKey.sourceLanguage) private var languageID = SourceLanguage.python.rawValue
    @AppStorage(SettingsKey.theme) private var themeID = Theme.classic.id
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var cache = SourceCache()

    var language: SourceLanguage { SourceLanguage(rawValue: languageID) ?? .python }
    var theme: Theme { Theme.named(themeID) }

    var body: some View {
        let source = cache.source(for: program, language: language)
        let active = session.state.isActive ? session.currentStatement : editor.selection
        VStack(spacing: 0) {
            HStack {
                Picker("Language", selection: $languageID) {
                    ForEach(SourceLanguage.allCases) { language in
                        Text(language == .pseudocodeItalian ? String(localized: "Pseudocode (Italian)")
                             : language == .pseudocodeEnglish ? String(localized: "Pseudocode (English)")
                             : language.displayName)
                            .tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { copy(source.text) }
                Button("Save…", systemImage: "square.and.arrow.down") { save(source) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(source.lines) { line in
                            CodeLine(line: line, theme: theme, active: line.statementID != nil && line.statementID == active)
                                .id(line.id)
                                .onTapGesture {
                                    if let id = line.statementID { editor.selection = id }
                                }
                                .contextMenu {
                                    Button("Copy Line", systemImage: "doc.on.doc") { copy(line.text.trimmingCharacters(in: .whitespaces)) }
                                    Button("Copy All", systemImage: "doc.on.doc.fill") { copy(source.text) }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                    .scrollTargetLayout()
            }
            .scrollPosition($position, anchor: .center)
            .onChange(of: active) { _, id in
                guard let id, let line = source.lines.first(where: { $0.statementID == id }) else { return }
                withAnimation(.smooth) { position.scrollTo(id: line.id, anchor: .center) }
            }
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func save(_ source: GeneratedSource) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (program.name.isEmpty ? "Program" : program.name) + "." + language.fileExtension
        if let type = UTType(filenameExtension: language.fileExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try source.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private struct CodeLine: View {
    let line: GeneratedSource.Line
    let theme: Theme
    let active: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(line.id + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
                .padding(.trailing, 8)
            Rectangle()
                .fill(line.category.map { theme.palette(for: $0).stroke } ?? .clear)
                .frame(width: 3)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12.5, design: .monospaced))
                .fixedSize()
                .padding(.leading, 10)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
    }
}

/// Remembers the last generated source, so highlighting while a program runs doesn't regenerate it.
final class SourceCache {
    private var key: (program: Program, language: SourceLanguage)?
    private var value: GeneratedSource?

    func source(for program: Program, language: SourceLanguage) -> GeneratedSource {
        if let key, let value, key.language == language, key.program == program { return value }
        let generated = CodeGenerator.generate(program, language: language)
        key = (program, language)
        value = generated
        return generated
    }
}
