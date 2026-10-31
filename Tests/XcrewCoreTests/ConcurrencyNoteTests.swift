import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The note after a MobileBuildMCP build whose log holds many concurrency diagnostics: their counts, as facts.
@Suite struct ConcurrencyNoteTests {
    /// A build result listing `listed` warnings, whose log under the home holds `diagnostics` concurrency ones: 8 in
    /// `Kit`, the rest in `Feature`, by their task headers.
    func report(listed: Int, diagnostics: Int) async -> Report {
        let project = Project.temporary()
        let home = project.root.appending(path: "home")
        var log = "SwiftCompile normal arm64 /p/Kit/Kit.swift (in target 'Kit' from project 'App')\n"
        for line in 1...diagnostics {
            if line == 9 { log += "SwiftCompile normal arm64 /p/Feature/Feature.swift (in target 'Feature' from project 'App')\n" }
            let file = line <= 8 ? "/p/Kit/Kit.swift" : "/p/Feature/Feature.swift"
            let group = line % 3 == 0 ? "RegionIsolation::SendingRisksDataRace" : "MutableGlobalVariable"
            log += "\(file):\(line):1: warning: diagnostic \(line) [#\(group)]\n"
        }
        project.write(log, to: "home/logs/build.log")
        let warnings = (1...listed).map { "  ⚠ diagnostic \($0)\n    /p/Kit/Kit.swift:\($0)\n" }.joined(separator: "\n")
        let text = "\n🔨 Build\n\nWarnings (\(listed)):\n\n\(warnings)\n✅ Build succeeded. (⏱️ 3.4s)\n  └ Files:\n     └── ~/logs/build.log — Build Logs\n"
        let machine = Machine(environment: [:], home: home, runner: FakeRunner(), applications: project.root.appending(path: "Applications"))
        return await Report.make(kind: .build, output: ToolOutput(text: text, server: .mobileBuildMCP), home: home.path, runner: FakeRunner(), project: project, machine: machine)
    }

    @Test func aBuildWithManyGivesTheirCountsAsFacts() async {
        let summary = await report(listed: 12, diagnostics: 12).concurrency
        #expect(summary?.count == 12)
        #expect(summary?.note == "xcrew: this build's log has 12 Swift concurrency diagnostics in 2 modules, most of them MutableGlobalVariable (8) and SendingRisksDataRace (4). `xcrew concurrency` lists them by compiler group and module.")
    }

    /// A result listing many warnings, of which the log's concurrency ones are fewer than ten.
    @Test func aBuildWithFewerThanTenHasNone() async {
        #expect(await report(listed: 12, diagnostics: 9).concurrency == nil)
    }

    /// The result lists every warning once: one listing fewer than ten can't have ten concurrency ones, so its log isn't read.
    @Test func aResultListingFewerThanTenLeavesTheLogUnread() async {
        #expect(await report(listed: 9, diagnostics: 12).concurrency == nil)
    }
}
