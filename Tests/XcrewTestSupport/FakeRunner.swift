import Foundation
import XcrewCore

/// Answers commands from a table keyed by the joined argv; anything else reads as not found.
public struct FakeRunner: CommandRunning {
    public var installed: Set<String> = []
    public var responses: [String: CommandResult] = [:]
    /// Where `which` finds a program, for one that must be a real file; others sit in a folder that doesn't exist.
    public var paths: [String: String] = [:]

    public init(installed: Set<String> = [], responses: [String: CommandResult] = [:]) {
        self.installed = installed
        self.responses = responses
    }

    public func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        responses[argv.joined(separator: " ")] ?? .notFound
    }

    public func which(_ name: String) -> String? {
        paths[name] ?? (installed.contains(name) ? "/nonexistent/bin/\(name)" : nil)
    }
}

extension CheckContext {
    /// Apps live in the project's `Applications` folder unless `applications` names another, never the Mac's own.
    public static func fake(_ runner: FakeRunner = FakeRunner(), project: Project = .temporary(), environment: [String: String] = [:], processID: Int32 = 1, applications: URL? = nil) -> CheckContext {
        CheckContext(project: project, machine: Machine(environment: environment, home: project.root.appending(path: "home"), runner: runner, processID: processID, applications: applications ?? project.root.appending(path: "Applications")))
    }
}
