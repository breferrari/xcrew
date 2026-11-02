import Foundation

/// A MobileBuildMCP test run whose `-only-testing:` names targets its scheme doesn't test, which Xcode refuses with
/// "Tests in the target “X” can’t be run because “X” isn’t a member of the specified test plan or scheme." (Xcode 27.2's
/// XCTHarness, docs/findings.md): the note names a shared scheme that runs every one of them by default, the one of
/// fewest targets as `affected` lists them, and the `session_set_defaults` call that makes it the active profile's.
enum OutsideScheme {
    /// The targets Xcode's refusals name, each once, their quotes typographic as Xcode writes them or plain, escaped in
    /// JSON or not.
    static func targets(in text: String) -> [String] {
        var seen: Set<String> = []
        return text.matches(of: /Tests in the target \\?["“](.+?)\\?["”] can['’]t be run because/).map { String($0.1) }.filter { seen.insert($0).inserted }
    }

    /// The note for `targets`, refused under `scheme` when the run's log named it, from the schemes `project` shares.
    static func note(targets: [String], scheme: String?, in project: Project) -> String {
        note(targets: targets, scheme: scheme, other: running(Set(targets), in: project.repositoryContainers))
    }

    /// The note for `targets` refused under `scheme`, with `other`, a shared scheme that runs them all, when one does.
    static func note(targets: [String], scheme: String?, other: String?) -> String {
        let (named, them) = targets.count == 1 ? (targets[0], "it") : (targets.dropLast().joined(separator: ", ") + " and " + (targets.last ?? ""), "them")
        let refused = "xcrew: \(scheme.map { "the \($0) scheme" } ?? "this run's scheme") doesn't test \(named), the target\(targets.count == 1 ? "" : "s") `-only-testing:` names, so Xcode ran none."
        guard let other, let call = LiveDefaults.call(["scheme": other]) else {
            return refused + " xcrew found no shared scheme that runs \(them) by default."
        }
        return refused + " The \(other) scheme tests \(them): `\(call)` makes \(other) the active profile's scheme."
    }

    /// The shared scheme of `containers` and the projects their workspaces list that runs every one of `targets` when no
    /// test plan is named, the one of fewest targets, then by name.
    static func running(_ targets: Set<String>, in containers: [URL]) -> String? {
        TestSchemes.containers(from: containers).flatMap { container in
            TestSchemes.sharedSchemes(of: container).map { scheme in
                (name: scheme.name, runs: Set(TestSchemes.runByDefault(by: scheme.document, in: container).map(\.name)))
            }
        }.filter { targets.isSubset(of: $0.runs) }.min { ($0.runs.count, $0.name) < ($1.runs.count, $1.name) }?.name
    }
}
