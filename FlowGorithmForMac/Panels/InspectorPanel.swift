import FlowCore
import SwiftUI

/// The right-hand panel: two stacked panes, each showing console, variables, turtle or code.
struct InspectorPanel: View {
    let program: Program
    @Bindable var editor: EditorModel
    var session: RunSession

    var body: some View {
        VSplitView {
            pane(selection: $editor.topPanel)
                .frame(minHeight: 160)
            if editor.showsBottomPanel {
                pane(selection: $editor.bottomPanel)
                    .frame(minHeight: 140)
            }
        }
    }

    func pane(selection: Binding<PanelTab>) -> some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: selection) {
                ForEach(PanelTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            Group {
                switch selection.wrappedValue {
                case .console: ConsoleView(session: session)
                case .variables: VariablesView(session: session)
                case .turtle: TurtleView(session: session)
                case .code: SourceCodeView(program: program, editor: editor, session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
