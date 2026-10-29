import Foundation
import Testing
@testable import XcrewCore

/// Pins `ps` and `lsof` as this Mac's own tools print them (docs/findings.md, *MobileBuildMCP's profiles*): a
/// change to `etime`, `comm` or `lsof -Fn` turns this red instead of the restart check quietly skipping.
@Suite struct ProcessListTests {
    @Test func thisProcessReadsBackWithItsParentAgeProgramAndFolder() async throws {
        let runner = SystemCommandRunner()
        let id = ProcessInfo.processInfo.processIdentifier
        let list = await ProcessList.load(using: runner)
        let me = try #require(list.processes.first { $0.id == id })
        #expect(me.parent == getppid())
        #expect(me.elapsed >= 0)
        #expect(!me.program.isEmpty && !me.program.contains("/"))
        #expect(list.ancestors(of: id).first?.id == getppid())
        let folders = await ConfigLoadedCheck.folders(of: [me], using: runner)
        #expect(folders[id] == ProjectLayout.canonical(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)))
    }

    @Test func elapsedTimesReadInEveryForm() {
        #expect(ProcessList.seconds("00:07") == 7)
        #expect(ProcessList.seconds("01:02:03") == 3723)
        #expect(ProcessList.seconds("2-01:00:00") == 176_400)
        #expect(ProcessList.seconds("soon") == nil)
    }

    /// MobileBuildMCP's server, as Homebrew starts it, with or without flags after `mcp`.
    @Test func aMobileBuildMCPServerIsKnownByItsCommand() {
        let server = "/opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/build/cli.js mcp"
        func process(_ command: String) -> ProcessList.Process { .init(id: 1, parent: 0, elapsed: 0, command: command) }
        #expect(ProcessList.isMobileBuildMCPServer(process(server)))
        #expect(ProcessList.isMobileBuildMCPServer(process(server + " --socket /tmp/x.sock")))
        #expect(!ProcessList.isMobileBuildMCPServer(process("/opt/homebrew/bin/mobilebuildmcp --version")))
    }
}
