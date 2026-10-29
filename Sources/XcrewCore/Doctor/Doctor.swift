import Foundation

public enum Doctor {
    public static let checks: [any Check] = [
        MobileBuildMCPVersionCheck(),
        LegacyBinaryCheck(),
        ProjectConfigCheck(),
        SimulatorsCheck(),
        HeadlessXcodeMCPCheck(),
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

    /// What `doctor --problems` prints: its lines, or a line saying there are none.
    public static func problemsText(lines: [String]) -> [String] {
        lines.isEmpty ? ["No problems."] : lines
    }

    public static func worst(_ entries: [Entry]) -> CheckStatus {
        entries.map(\.result.status).max() ?? .pass
    }
}
