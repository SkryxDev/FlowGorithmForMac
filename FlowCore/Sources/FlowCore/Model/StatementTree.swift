// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import Foundation

/// Identifies one block of statements inside a function: the function body itself,
/// or one branch/body of a compound statement.
public struct BlockReference: Hashable, Sendable {
    /// `nil` for the function body.
    public var owner: Statement.ID?
    /// Index into `Statement.blocks` (0 = then/body, 1 = else).
    public var branch: Int

    public init(owner: Statement.ID?, branch: Int = 0) {
        self.owner = owner
        self.branch = branch
    }

    public static let functionBody = BlockReference(owner: nil)
}

/// A position between two statements, where a new shape can be inserted.
public struct InsertionPoint: Hashable, Sendable {
    public var block: BlockReference
    public var index: Int

    public init(block: BlockReference, index: Int) {
        self.block = block
        self.index = index
    }
}

extension Array where Element == Statement {
    public func statement(withID id: Statement.ID) -> Statement? {
        for statement in self {
            if statement.id == id { return statement }
            for block in statement.blocks {
                if let found = block.statement(withID: id) { return found }
            }
        }
        return nil
    }

    /// Where a statement sits: its block and its index in that block.
    public func location(of id: Statement.ID, in block: BlockReference = .functionBody) -> InsertionPoint? {
        for (index, statement) in enumerated() {
            if statement.id == id { return InsertionPoint(block: block, index: index) }
            for (branch, child) in statement.blocks.enumerated() {
                if let found = child.location(of: id, in: BlockReference(owner: statement.id, branch: branch)) {
                    return found
                }
            }
        }
        return nil
    }

    public func block(_ reference: BlockReference) -> [Statement]? {
        guard let owner = reference.owner else { return self }
        guard let statement = statement(withID: owner), reference.branch < statement.blocks.count else { return nil }
        return statement.blocks[reference.branch]
    }

    /// Applies `transform` to the block identified by `reference`. Returns false if it doesn't exist.
    @discardableResult
    public mutating func modifyBlock(_ reference: BlockReference, _ transform: (inout [Statement]) -> Void) -> Bool {
        guard let owner = reference.owner else {
            transform(&self)
            return true
        }
        for index in indices {
            if self[index].id == owner {
                var blocks = self[index].blocks
                guard reference.branch < blocks.count else { return false }
                transform(&blocks[reference.branch])
                self[index].blocks = blocks
                return true
            }
            var blocks = self[index].blocks
            for branch in blocks.indices where blocks[branch].modifyBlock(reference, transform) {
                self[index].blocks = blocks
                return true
            }
        }
        return false
    }

    @discardableResult
    public mutating func insert(_ statement: Statement, at point: InsertionPoint) -> Bool {
        modifyBlock(point.block) { block in
            block.insert(statement, at: Swift.min(Swift.max(point.index, 0), block.count))
        }
    }

    @discardableResult
    public mutating func removeStatement(withID id: Statement.ID) -> Statement? {
        guard let point = location(of: id) else { return nil }
        var removed: Statement?
        modifyBlock(point.block) { block in removed = block.remove(at: point.index) }
        return removed
    }

    @discardableResult
    public mutating func replaceStatement(_ statement: Statement) -> Bool {
        guard let point = location(of: statement.id) else { return false }
        return modifyBlock(point.block) { block in block[point.index] = statement }
    }

    /// Moves a statement to a new insertion point. Refuses to move a statement inside itself.
    @discardableResult
    public mutating func moveStatement(withID id: Statement.ID, to point: InsertionPoint) -> Bool {
        guard let source = location(of: id), let moving = statement(withID: id) else { return false }
        if let owner = point.block.owner, owner == id || moving.blocks.contains(where: { $0.statement(withID: owner) != nil }) {
            return false
        }
        var target = point
        if source.block == target.block && source.index < target.index {
            target.index -= 1
        }
        removeStatement(withID: id)
        return insert(moving, at: target)
    }

    /// Every statement, depth first, in program order.
    public var flattened: [Statement] {
        flatMap { [$0] + $0.blocks.flatMap(\.flattened) }
    }
}
