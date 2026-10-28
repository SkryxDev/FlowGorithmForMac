// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

#if DEBUG
import FlowCore
import Foundation
import SwiftUI

extension AIChat {
    /// A made-up conversation in study mode, for the README screenshot: an example drawn in the chat
    /// and a rename proposed on the chart. Debug builds only, with `-ScreenshotDemo YES`; it sends
    /// no request. In English, like the screenshot.
    func loadScreenshotDemo(context: () -> ToolContext) {
        let live = context()
        let program = live.program.wrappedValue
        let loop = [
            Statement(.declare(.init(names: "i", type: .integer))),
            Statement(.assign(.init(variable: "i", expression: "1"))),
            Statement(.while(.init(expression: "i <= 5", body: [
                Statement(.output(.init(expression: "i"))),
                Statement(.assign(.init(variable: "i", expression: "i + 1"))),
            ]))),
        ]
        demo(Entry(kind: .user, text: "Show me an example of a While loop that counts to 5"))
        demo(Entry(kind: .assistant, text: "A `While` repeats its shapes as long as the condition is true. Here `i` starts at 1 and grows by one each time, so the loop stops after 5.", model: "Gemma 4 31B"))
        demo(Entry(kind: .example, text: "", example: loop))
        demo(Entry(kind: .user, text: "How do I rename fps to hz?"))
        demo(Entry(kind: .assistant, text: "Rename it in every shape that uses it: the declaration, the input and the condition. Here's the change on the chart: accept it if it looks right.", model: "Gemma 4 31B"))

        var changes: [Proposal.Change] = []
        for shape in program.functions.flatMap({ $0.body.flattened }) {
            var renamed = shape
            switch shape.kind {
            case .declare(var declare) where declare.names.contains("fps"):
                declare.names = declare.names.replacingOccurrences(of: "fps", with: "hz")
                renamed.kind = .declare(declare)
            case .input(var input) where input.variable == "fps":
                input.variable = "hz"
                renamed.kind = .input(input)
            case .if(var test) where test.expression.contains("fps"):
                test.expression = test.expression.replacingOccurrences(of: "fps", with: "hz")
                renamed.kind = .if(test)
            default:
                continue
            }
            changes.append(.replace(renamed, keepsChildren: true))
        }
        guard !changes.isEmpty else { return }
        let proposal = Proposal(changes: changes)
        demo(Entry(kind: .proposal, text: Self.summary(of: proposal, in: program), proposal: proposal))
        live.editor.proposal = proposal
    }
}
#endif
