import Foundation

/// CI builds with the Xcode the project does: its pin, else the one builds use here. Only GitHub Actions' workflows are
/// read (docs/findings.md, *Which Xcode*).
struct XcodeCICheck: Check {
    let id = "xcode/ci"
    let title = "CI uses the project's Xcode"

    func run(_ context: CheckContext) async -> CheckResult {
        let named = Xcodes.ci(of: context.project).filter { $0.version != nil }
        guard !named.isEmpty else { return .pass("CI names no Xcode version") }
        let pinned = Xcodes.pin(of: context.project)?.version
        var ours = pinned
        if ours == nil { ours = await Xcodes.forBuilds(of: context.project, on: context.machine)?.version }
        guard let ours else { return .skip("no Xcode is selected here") }
        guard let other = named.first(where: { Xcodes.numbers($0.version ?? "") != Xcodes.numbers(ours) }), let theirs = other.version else {
            return .pass("CI uses Xcode \(ours) too")
        }
        let here = pinned == nil ? "builds here use Xcode \(ours)" : "this project pins Xcode \(ours)"
        return .warn("CI uses Xcode \(theirs) (\(other.file):\(other.line)), but \(here), so results can differ from CI's: move CI to \(ours), or pin \(theirs) in \(Xcodes.pinFile)")
    }
}
