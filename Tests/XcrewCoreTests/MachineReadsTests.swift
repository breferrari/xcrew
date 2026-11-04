import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The machine's own files are read through `Machine`, so a test's Machine stands for the whole Mac: an Xcode a build log
/// names under `/Applications` is read from the Machine's own applications folder.
struct MachineReadsTests {
    @Test func anXcodeALogNamesIsReadFromTheMachinesApplications() async throws {
        let project = Project.temporary()
        let machine = CheckContext.fake(project: project).machine
        let docs = ConcurrencyGroups.docs(in: machine.applications.appending(path: "Xcode-Fake.app"))
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "# Sendable things (SendableThing)\n\nThey can race.\n".write(to: docs.appending(path: "sendable-thing.md"), atomically: true, encoding: .utf8)
        let log = project.root.appending(path: "build.log")
        try """
            SwiftCompile normal arm64 /p/Kit.swift (in target 'Kit' from project 'App')
                /Applications/Xcode-Fake.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name Kit
            /p/Kit.swift:3:1: warning: a thing [#SendableThing]

            """.write(to: log, atomically: true, encoding: .utf8)
        let report = try await ConcurrencyReport.read(log: log, project: project, machine: machine, readsChanges: false)
        #expect(report.groupsFromDocs)
        #expect(report.groups.map(\.title) == ["Sendable things"])
    }

    /// A test's Machine whose applications are the Mac's own reads none of them: the read fails the test.
    @Test func aTestMachineNeverReadsTheMacsXcode() async throws {
        let project = Project.temporary()
        let real = CheckContext.fake(project: project, applications: URL(fileURLWithPath: "/Applications")).machine
        let log = project.root.appending(path: "build.log")
        try "    /Applications/Xcode-Fake.app/Contents/Developer/usr/bin/swiftc -module-name Kit\n/p/Kit.swift:3:1: warning: a thing [#SendableThing]\n".write(to: log, atomically: true, encoding: .utf8)
        var report: ConcurrencyReport?
        await withKnownIssue("the Mac's own Xcode") {
            report = try await ConcurrencyReport.read(log: log, project: project, machine: real, readsChanges: false)
        }
        #expect(report?.groupsFromDocs == false)
    }
}
