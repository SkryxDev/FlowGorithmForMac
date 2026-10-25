import AppKit
import FlowCore
import SwiftUI

/// Starts on an empty flowchart, like Flowgorithm, instead of the Open panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
}

@main
struct FlowGorithmForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: FlowDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands { AppCommands() }
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView()
        }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.documentActions) private var actions

    /// When a text field is being edited, standard text commands go to it instead of the chart.
    private var editingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func text(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Export Flowchart") {
                Button("PNG Image…") { actions?.export(.png) }
                Button("PDF Document…") { actions?.export(.pdf) }
                Button("SVG Vector…") { actions?.export(.svg) }
            }
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print Flowchart…") { actions?.print() }
                .keyboardShortcut("p")
                .disabled(actions == nil)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { editingText ? text(#selector(NSText.cut(_:))) : actions?.cut() }
                .keyboardShortcut("x")
            Button("Copy") { editingText ? text(#selector(NSText.copy(_:))) : actions?.copy() }
                .keyboardShortcut("c")
            Button("Paste") { editingText ? text(#selector(NSText.paste(_:))) : actions?.paste() }
                .keyboardShortcut("v")
            Button("Duplicate") { actions?.duplicate() }
                .keyboardShortcut("d")
                .disabled(actions?.hasSelection != true)
            Button("Delete") { editingText ? text(#selector(NSText.delete(_:))) : actions?.delete() }
            Button("Select All") { text(#selector(NSText.selectAll(_:))) }
                .keyboardShortcut("a")
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") { actions?.zoomIn() }
                .keyboardShortcut("+")
            Button("Zoom Out") { actions?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { actions?.resetZoom() }
                .keyboardShortcut("0")
            Divider()
            Button("Show Console") { actions?.showPanel(.console) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Show Variables") { actions?.showPanel(.variables) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Show Turtle Graphics") { actions?.showPanel(.turtle) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("Show Source Code") { actions?.showPanel(.code) }
                .keyboardShortcut("4", modifiers: [.command, .option])
            Button("Show or Hide Panels") { actions?.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu("Program") {
            Button(actions?.isPaused == true ? "Continue" : "Run") { actions?.run() }
                .keyboardShortcut("r")
                .disabled(actions == nil || (actions?.isRunning == true && actions?.isPaused == false))
            Button("Step") { actions?.step() }
                .keyboardShortcut("'")
                .disabled(actions == nil)
            Button("Pause") { actions?.pause() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(actions?.isRunning != true || actions?.isPaused == true)
            Button("Stop") { actions?.stop() }
                .keyboardShortcut(".")
                .disabled(actions?.isRunning != true)
            Divider()
            Picker("Speed", selection: Binding(get: { speedStep }, set: { actions?.setSpeed($0) })) {
                Text("Full speed").tag(1.0)
                Text("Fast").tag(0.75)
                Text("Medium").tag(0.5)
                Text("Slow").tag(0.25)
                Text("Very slow").tag(0.0)
            }
            Toggle("Ignore Breakpoints", isOn: Binding(get: { actions?.ignoreBreakpoints ?? false },
                                                       set: { _ in actions?.toggleIgnoreBreakpoints() }))
            Button("Remove All Breakpoints") { actions?.removeBreakpoints() }
                .disabled(actions == nil || actions?.isRunning == true)
            Divider()
            Button("Add Function…") { actions?.addFunction() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(actions == nil || actions?.isRunning == true)
            Button("Program Info…") { actions?.programInfo() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
    }

    private var speedStep: Double {
        guard let speed = actions?.speed else { return 1 }
        return [1.0, 0.75, 0.5, 0.25, 0.0].min { abs($0 - speed) < abs($1 - speed) } ?? 1
    }
}
