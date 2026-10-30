import Foundation

public enum Doctor {
    public static let checks: [any Check] = [
        MobileBuildMCPVersionCheck(),
        LegacyBinaryCheck(),
        ProjectConfigCheck(),
        ConfigLoadedCheck(),
        XcodebuildLeftRunningCheck(),
        SimulatorsCheck(),
        WorktreeLeftoversCheck(),
        SimulatorMemoryCheck(),
        StorageBudgetCheck(),
        HeadlessXcodeMCPCheck(),
        XcodeMCPHandshakeCheck(),
        XcodePinCheck(),
        XcodeCICheck(),
        XcodeOpenCheck(),
        ClaudeApprovedCheck(),
        UnsignedAgentsCheck(),
        MacroCopyPhaseCheck(),
        XcrewUpdateCheck(),
    ]

    public static func check(id: String) -> (any Check)? {
        checks.first { $0.id == id }
    }

    public struct Entry: Sendable {
        public let check: any Check
        public let result: CheckResult

        public init(check: any Check, result: CheckResult) {
            self.check = check
            self.result = result
        }
    }

    /// Runs the checks concurrently; entries come back in the checks' order.
    public static func run(_ checks: [any Check] = checks, in context: CheckContext) async -> [Entry] {
        let results = await withTaskGroup(of: (Int, CheckResult).self) { group in
            for (index, check) in checks.enumerated() {
                group.addTask { (index, await check.run(context)) }
            }
            return await group.reduce(into: [Int: CheckResult]()) { $0[$1.0] = $1.1 }
        }
        return checks.indices.map { Entry(check: checks[$0], result: results[$0]!) }
    }

    /// What failed or warned, worst first, so the band can show the first.
    public static func problems(_ entries: [Entry]) -> [Entry] {
        entries.filter { $0.result.status == .fail || $0.result.status == .warn }.sorted { $0.result.status > $1.result.status }
    }

    /// What `doctor --problems` prints: its lines, or a line saying there are none, then the checks whose warning it keeps
    /// off the prompt, so it doesn't contradict the full doctor.
    public static func problemsText(lines: [String], kept: [String] = []) -> [String] {
        let shown = lines.isEmpty ? ["No problems."] : lines
        guard !kept.isEmpty else { return shown }
        return shown + ["Kept off the prompt\(ResultBundle.listed(kept)). `xcrew doctor` shows \(kept.count == 1 ? "it" : "them")."]
    }

    public static func worst(_ entries: [Entry]) -> CheckStatus {
        entries.map(\.result.status).max() ?? .pass
    }
}
