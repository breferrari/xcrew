import Foundation

/// xcrew's mod reported in this session: without it its notes, its tools and the line above the prompt are off, with
/// nothing to say so, as under an mcs older than `minMCSVersion` or before `mcs sync`. A warning, not a failure: the mod
/// reports on its first doctor read, which a doctor run can come before.
struct ModLoadedCheck: Check {
    let id = "xcrew/mod-loaded"
    let title = "xcrew's mod is loaded in this session"
    /// The first mcs that loads a pack's plugin with its hook modules; `techpack.yaml`'s `minMCSVersion` says the same.
    static let minMCSVersion = "2026.10.31"

    func run(_ context: CheckContext) async -> CheckResult {
        guard let session = SessionStamp.session(on: context.machine) else { return .skip("not run from a Claude Code session") }
        guard let stamp = SessionStamp.read(session, on: context.machine) else { return .skip("this session hasn't reported to xcrew") }
        guard stamp.mod == nil else { return .pass("reported in this session") }
        let fix = context.project.isConfiguredByMCS ? "with mcs, update it to \(Self.minMCSVersion) or later and run mcs sync" : "restart Claude Code"
        return .warn("xcrew's mod hasn't reported in this session: it isn't loaded, so its notes, its tools and the line above the prompt are off, or it's still starting and the doctor ran first: \(fix)")
    }
}
