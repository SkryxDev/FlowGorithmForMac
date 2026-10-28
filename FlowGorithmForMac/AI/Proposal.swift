// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import Foundation

/// Changes the assistant proposes in study mode. The chart shows them right away, the old shapes
/// faded and the new ones blinking below them, but changes only if the user accepts them.
struct Proposal: Identifiable, Equatable {
    /// Where new shapes go, by the shapes and functions around them rather than by position, so
    /// the proposal still lands in the right place after the chart changes.
    enum Anchor: Equatable {
        case after(Statement.ID)
        case before(Statement.ID)
        case branch(owner: Statement.ID, branch: Int, atEnd: Bool)
        case function(Function.ID, atEnd: Bool)
    }

    enum Change: Equatable {
        /// A shape rewritten, with the same id. `keepsChildren` when the new version leaves out the
        /// shapes inside an if or a loop, which then stay as they are on the chart.
        case replace(Statement, keepsChildren: Bool)
        case insert([Statement], at: Anchor)
        case delete(Statement.ID)
    }

    /// How the chart draws a proposal: the chart as it would be, plus the old version of every
    /// changed or deleted shape, faded, where it was.
    struct Preview {
        var program: Program
        /// The old versions, drawn faded.
        var ghosts: Set<Statement.ID>
        /// The new and changed shapes, drawn blinking.
        var fresh: Set<Statement.ID>
    }

    let id = UUID()
    var changes: [Change]

    /// The chart with the changes made. Changes whose shapes or anchors are gone are skipped.
    func applied(to program: Program) -> (program: Program, touched: [Statement.ID]) {
        var result = program
        var touched: [Statement.ID] = []
        for change in changes {
            switch change {
            case .replace(let shape, let keepsChildren):
                guard let index = result.functions.firstIndex(where: { $0.body.statement(withID: shape.id) != nil }),
                      let current = result.functions[index].body.statement(withID: shape.id) else { continue }
                var updated = shape
                if keepsChildren, updated.blocks.count == current.blocks.count { updated.blocks = current.blocks }
                result.functions[index].body.replaceStatement(updated)
                touched.append(shape.id)
            case .insert(let shapes, let anchor):
                // The same shapes can't go in twice: their ids would no longer be unique.
                let ids = shapes.flatMap { [$0] + $0.blocks.flatMap(\.flattened) }.map(\.id)
                guard !ids.contains(where: { id in result.functions.contains { $0.body.statement(withID: id) != nil } }),
                      let (index, point) = Self.resolve(anchor, in: result) else { continue }
                for (offset, shape) in shapes.enumerated() {
                    result.functions[index].body.insert(shape, at: InsertionPoint(block: point.block, index: point.index + offset))
                }
                touched += ids
            case .delete(let id):
                guard let index = result.functions.firstIndex(where: { $0.body.statement(withID: id) != nil }) else { continue }
                result.functions[index].body.removeStatement(withID: id)
            }
        }
        var seen = Set<Statement.ID>()
        let present = Set(result.functions.flatMap { $0.body.flattened.map(\.id) })
        return (result, touched.filter { present.contains($0) && seen.insert($0).inserted })
    }

    func preview(of program: Program) -> Preview {
        var result = applied(to: program).program
        let before = Set(program.functions.flatMap { $0.body.flattened.map(\.id) })
        var fresh = Set(result.functions.flatMap { $0.body.flattened.map(\.id) }).subtracting(before)
        var ghosts = Set<Statement.ID>()
        var handled = Set<Statement.ID>()
        for change in changes {
            switch change {
            case .replace(let shape, _):
                guard handled.insert(shape.id).inserted,
                      let old = program.functions.lazy.compactMap({ $0.body.statement(withID: shape.id) }).first,
                      let index = result.functions.firstIndex(where: { $0.body.statement(withID: shape.id) != nil }),
                      let location = result.functions[index].body.location(of: shape.id) else { continue }
                fresh.insert(shape.id)
                // Only the shape itself: the shapes inside an if or a loop stay with the new version.
                var ghost = Self.ghost(of: old)
                ghost.blocks = ghost.blocks.map { _ in [] }
                result.functions[index].body.insert(ghost, at: location)
                ghosts.insert(ghost.id)
            case .delete(let id):
                guard handled.insert(id).inserted,
                      let function = program.functions.first(where: { $0.body.statement(withID: id) != nil }),
                      let old = function.body.statement(withID: id),
                      let location = function.body.location(of: id),
                      let index = result.functions.firstIndex(where: { $0.id == function.id }),
                      result.functions[index].body.statement(withID: id) == nil,
                      let block = result.functions[index].body.block(location.block) else { continue }
                let ghost = Self.ghost(of: old)
                result.functions[index].body.insert(ghost, at: InsertionPoint(block: location.block, index: min(location.index, block.count)))
                ghosts.formUnion([ghost.id] + ghost.blocks.flatMap(\.flattened).map(\.id))
            case .insert:
                break
            }
        }
        // A shape changed and then deleted by the same proposal shows only as deleted.
        fresh.formIntersection(Set(result.functions.flatMap { $0.body.flattened.map(\.id) }))
        return Preview(program: result, ghosts: ghosts, fresh: fresh.subtracting(ghosts))
    }

    /// The function a proposal is about, to show it on the chart.
    func function(in program: Program) -> Function.ID? {
        for change in changes {
            let id: Statement.ID?
            switch change {
            case .replace(let shape, _): id = shape.id
            case .delete(let target): id = target
            case .insert(_, .after(let target)), .insert(_, .before(let target)): id = target
            case .insert(_, .branch(let owner, _, _)): id = owner
            case .insert(_, .function(let function, _)): return function
            }
            if let id, let function = program.functions.first(where: { $0.body.statement(withID: id) != nil }) { return function.id }
        }
        return nil
    }

    /// A copy of a shape to draw faded. Its ids come from the original's, always the same ones, so
    /// redrawing the chart finds the same shapes and doesn't lay it out again.
    static func ghost(of shape: Statement) -> Statement {
        var copy = shape
        var bytes = shape.id.uuid
        bytes.0 ^= 0x5A
        bytes.7 ^= 0xC3
        bytes.15 ^= 0x3C
        copy.id = UUID(uuid: bytes)
        copy.blocks = shape.blocks.map { $0.map(ghost(of:)) }
        return copy
    }

    static func resolve(_ anchor: Anchor, in program: Program) -> (Int, InsertionPoint)? {
        switch anchor {
        case .after(let id), .before(let id):
            for (index, function) in program.functions.enumerated() {
                if let location = function.body.location(of: id) {
                    var point = location
                    if case .after = anchor { point.index += 1 }
                    return (index, point)
                }
            }
            return nil
        case .branch(let owner, let branch, let atEnd):
            guard let index = program.functions.firstIndex(where: { $0.body.statement(withID: owner) != nil }),
                  let statement = program.functions[index].body.statement(withID: owner),
                  branch < statement.blocks.count else { return nil }
            return (index, InsertionPoint(block: BlockReference(owner: owner, branch: branch),
                                          index: atEnd ? statement.blocks[branch].count : 0))
        case .function(let id, let atEnd):
            guard let index = program.functions.firstIndex(where: { $0.id == id }) else { return nil }
            return (index, InsertionPoint(block: .functionBody, index: atEnd ? program.functions[index].body.count : 0))
        }
    }
}
