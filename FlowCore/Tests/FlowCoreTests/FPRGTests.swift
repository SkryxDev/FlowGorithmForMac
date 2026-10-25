import Foundation
import Testing
@testable import FlowCore

struct FPRGTests {
    static let modern = """
    <?xml version="1.0"?>
    <flowgorithm fileversion="4.2">
        <attributes>
            <attribute name="name" value="Sample"/>
            <attribute name="authors" value="Student"/>
            <attribute name="about" value="Line one&#13;&#10;line two"/>
            <attribute name="saved" value="2026-10-25 09:23:25 PM"/>
        </attributes>
        <function name="Main" type="None" variable="">
            <parameters/>
            <body>
                <declare name="age, n" type="Integer" array="False" size=""/>
                <declare name="list" type="Real" array="True" size="10"/>
                <output expression="&quot;Age?&quot;" newline="True"/>
                <input variable="age"/>
                <if expression="age &gt;= 18">
                    <then>
                        <output expression="&quot;ok&quot;" newline="False"/>
                    </then>
                    <else/>
                </if>
                <for variable="n" start="1" end="3" direction="dec" step="2">
                    <assign variable="list[n]" expression="n / 2"/>
                </for>
                <do expression="n &lt; 3">
                    <call expression="Show(n)"/>
                </do>
                <comment text="hello"/>
                <breakpoint expression="n = 2" always="False"/>
                <open expression="&quot;out.txt&quot;" mode="write"/>
                <write expression="n"/>
                <close mode="write"/>
                <read variable="x"/>
                <pen color="teal"/>
                <home/>
                <clear/>
                <turn expression="90" rotate="left"/>
                <forward expression="10" pen="up"/>
                <future thing="1"/>
            </body>
        </function>
        <function name="Show" type="Integer" variable="r">
            <parameters>
                <parameter name="v" type="Integer" array="False"/>
            </parameters>
            <body>
                <declare name="r" type="Integer" array="False" size=""/>
            </body>
        </function>
    </flowgorithm>
    """

    @Test func readsEveryShape() throws {
        let program = try FPRGReader.read(Data(Self.modern.utf8))
        #expect(program.name == "Sample")
        #expect(program.about == "Line one\r\nline two")
        #expect(program.functions.map(\.name) == ["Main", "Show"])
        #expect(program.functions[1].returnType == .integer)
        #expect(program.functions[1].parameters.first?.name == "v")

        let body = program.functions[0].body
        guard case .declare(let d) = body[0].kind else { Issue.record("declare"); return }
        #expect(d.nameList == ["age", "n"])
        guard case .declare(let array) = body[1].kind else { Issue.record("array"); return }
        #expect(array.isArray && array.size == "10" && array.type == .real)
        guard case .output(let o) = body[2].kind else { Issue.record("output"); return }
        #expect(o.expression == "\"Age?\"" && o.newline)
        guard case .if(let i) = body[4].kind else { Issue.record("if"); return }
        #expect(i.thenBody.count == 1 && i.elseBody.isEmpty)
        guard case .for(let f) = body[5].kind else { Issue.record("for"); return }
        #expect(f.direction == .decreasing && f.step == "2" && f.body.count == 1)
        guard case .breakpoint(let b) = body[8].kind else { Issue.record("breakpoint"); return }
        #expect(!b.always && b.expression == "n = 2")
        guard case .pen(let pen) = body[13].kind else { Issue.record("pen"); return }
        #expect(pen.color == .teal)
        guard case .turn(let turn) = body[16].kind else { Issue.record("turn"); return }
        #expect(turn.direction == .left)
        guard case .forward(let forward) = body[17].kind else { Issue.record("forward"); return }
        #expect(!forward.penDown)
        guard case .unknown(let xml) = body[18].kind else { Issue.record("unknown"); return }
        #expect(xml.contains("future"))
    }

    @Test func roundTripsWithoutLosingAnything() throws {
        let program = try FPRGReader.read(Data(Self.modern.utf8))
        let written = FPRGWriter.string(program)
        let reread = try FPRGReader.read(Data(written.utf8))
        #expect(FPRGWriter.string(reread) == written)
        #expect(written.contains("<turn expression=\"90\" rotate=\"left\"/>"))
        #expect(written.contains("<forward expression=\"10\" pen=\"up\"/>"))
        #expect(written.contains("<attribute name=\"about\" value=\"Line one&#13;&#10;line two\"/>"))
    }

    @Test func readsVersionOneFiles() throws {
        let old = """
        <?xml version="1.0"?>
        <flowgorithm fileversion="1.0">
            <attributes><attribute name="name" value="Old"/></attributes>
            <function name="Main" type="None" variable="">
                <parameters/>
                <body>
                    <declare variables="n" type="Integer"/>
                    <for variable="n" start="1" end="3" step="1">
                        <output expression="n"/>
                    </for>
                </body>
            </function>
        </flowgorithm>
        """
        let program = try FPRGReader.read(Data(old.utf8))
        guard case .declare(let d) = program.functions[0].body[0].kind else { Issue.record("declare"); return }
        #expect(d.names == "n")
        guard case .for(let f) = program.functions[0].body[1].kind else { Issue.record("for"); return }
        #expect(f.direction == .increasing)
        guard case .output(let o) = f.body[0].kind else { Issue.record("output"); return }
        #expect(o.newline)
    }

    @Test func rejectsOtherXML() {
        #expect(throws: FPRGError.notAFlowchart) { try FPRGReader.read(Data("<html/>".utf8)) }
    }

    @Test func clipboardFragmentsGetNewIDs() throws {
        let program = try FPRGReader.read(Data(Self.modern.utf8))
        let original = Array(program.functions[0].body[4...5])
        let fragment = FPRGWriter.fragment(original)
        let pasted = try #require(FPRGWriter.statements(fromFragment: fragment))
        #expect(pasted.count == 2)
        #expect(pasted[0].id != original[0].id)
        #expect(FPRGWriter.fragment(pasted) == fragment)
    }

    @Test func treeEditing() {
        let inner = output("1")
        let loop = Statement(.while(.init(expression: "true", body: [inner])))
        var body = [declare("x", .integer), loop]
        #expect(body.location(of: inner.id) == InsertionPoint(block: BlockReference(owner: loop.id), index: 0))

        let added = output("2")
        body.insert(added, at: InsertionPoint(block: BlockReference(owner: loop.id), index: 1))
        #expect(body.block(BlockReference(owner: loop.id))?.count == 2)

        // Moving a loop into its own body is refused.
        let movedIntoItself = body.moveStatement(withID: loop.id, to: InsertionPoint(block: BlockReference(owner: loop.id), index: 0))
        #expect(!movedIntoItself)
        let moved = body.moveStatement(withID: added.id, to: InsertionPoint(block: .functionBody, index: 0))
        #expect(moved)
        #expect(body.first?.id == added.id)
        let removed = body.removeStatement(withID: inner.id)
        #expect(removed?.id == inner.id)
        #expect(body.flattened.count == 3)
    }
}
