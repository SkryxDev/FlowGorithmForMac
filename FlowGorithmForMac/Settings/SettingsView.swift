import AppKit
import FlowCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Appearance", systemImage: "paintpalette") { AppearanceSettings() }
            Tab("Running", systemImage: "play.circle") { RunningSettings() }
            Tab("Language", systemImage: "globe") { LanguageSettings() }
        }
        .frame(width: 560, height: 560)
        .scenePadding()
    }
}

private struct AppearanceSettings: View {
    @AppStorage(SettingsKey.theme) private var themeID = Theme.classic.id
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.showGrid) private var showsGrid = true
    @AppStorage(SettingsKey.compactLayout) private var compact = false

    var body: some View {
        Form {
            Section("Color scheme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Theme.all) { theme in
                        ThemeCard(theme: theme, selected: themeID == theme.id)
                            .onTapGesture { themeID = theme.id }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Flowchart") {
                Slider(value: $fontSize, in: 10...20, step: 1) {
                    Text("Text size")
                } minimumValueLabel: {
                    Text("A").font(.caption)
                } maximumValueLabel: {
                    Text("A").font(.title3)
                }
                Toggle("Show dot grid", isOn: $showsGrid)
                Toggle("Compact layout", isOn: $compact)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                theme.canvas
                HStack(spacing: 6) {
                    ForEach([ShapeCategory.input, .selection, .loop, .output], id: \.self) { category in
                        let palette = theme.palette(for: category)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [palette.fill, palette.fillEnd], startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.stroke, lineWidth: 1.2))
                            .frame(width: 22, height: 16)
                    }
                }
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
            Text(theme.name)
                .font(.callout.weight(selected ? .semibold : .regular))
        }
        .contentShape(Rectangle())
    }
}

private struct RunningSettings: View {
    @AppStorage(SettingsKey.chatConsole) private var chatConsole = true
    @AppStorage(SettingsKey.runSpeed) private var speed = 1.0
    @AppStorage(SettingsKey.maxStack) private var maxStack = 5000

    var body: some View {
        Form {
            Section("Console") {
                Picker("Style", selection: $chatConsole) {
                    Text("Chat bubbles").tag(true)
                    Text("Plain text").tag(false)
                }
                .pickerStyle(.radioGroup)
            }
            Section("Execution") {
                Slider(value: $speed, in: 0...1) {
                    Text("Default speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                Stepper(value: $maxStack, in: 100...100_000, step: 500) {
                    LabeledContent("Maximum call depth", value: "\(maxStack)")
                }
                Text("Stops runaway recursion with a clear error instead of freezing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LanguageSettings: View {
    @State private var language = AppLanguage.current
    @State private var changed = false

    var body: some View {
        Form {
            Section {
                Picker("App language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { _, newValue in
                    AppLanguage.current = newValue
                    changed = true
                }
                if changed {
                    HStack {
                        Text("Restart the app to apply the new language.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now", action: restart)
                            .buttonStyle(.glassProminent)
                    }
                }
            } footer: {
                Text("Keywords in expressions (and, or, not, mod, true, false) stay in English in every language, as in Flowgorithm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func restart() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
