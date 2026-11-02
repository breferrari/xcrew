import Foundation

/// A test run whose `-only-testing:` names a target its scheme doesn't test, which Xcode refuses with "Tests in the
/// target “X” can’t be run because “X” isn’t a member of the specified test plan or scheme." (Xcode 27.2's XCTHarness,
/// docs/findings.md): the note names a shared scheme that tests the target, as `affected` lists them, the fewest first.
enum OutsideScheme {
    /// The target Xcode's refusal names, its quotes typographic as Xcode writes them or plain, escaped in JSON or not.
    static func target(in text: String) -> String? {
        text.firstMatch(of: /Tests in the target \\?["“](.+?)\\?["”] can['’]t be run because/).map { String($0.1) }
    }

    /// The note for `target`, refused under `scheme` when the run's log named it, from the schemes `project` shares.
    static func note(target: String, scheme: String?, in project: Project) -> String {
        let containers = project.layout(.repository).containers.map { project.root.appending(path: $0) }
        let testing = TestSchemes.testing(in: containers, from: project.root).first { $0.targets.contains(target) && $0.name != scheme }
        let refused = "xcrew: \(scheme.map { "the \($0) scheme" } ?? "this run's scheme") doesn't test \(target), the target `-only-testing:` names, so Xcode ran none."
        guard let other = testing?.name else { return refused + " No shared scheme tests it." }
        let call = String(decoding: (try? JSONEncoder().encode(["scheme": other])) ?? Data(), as: UTF8.self)
        return refused + " The \(other) scheme tests it: `session_set_defaults \(call)` makes \(other) the active profile's scheme."
    }
}
