import Foundation

/// MobileBuildMCP's storage, as `mobilebuildmcp purge --report --json` enumerates it: each workspace's classes, their
/// sizes and newest file. `--report` deletes nothing and takes no class or age (docs/findings.md, *Disk space*). It walks
/// every file, so it's read only when asked, never on the prompt line.
public struct StorageReport: Sendable, Equatable {
    public struct Workspace: Sendable, Equatable {
        public let key: String
        /// Its folder as MobileBuildMCP writes it, `~` for the home folder.
        public let folder: String
        public let bytes: Int
        /// By MobileBuildMCP's class name: `derivedData`, `logs`, `resultBundles`, `testProducts`, `stateTransients`, `locks`.
        public let classes: [String: StorageClass]
    }

    public struct StorageClass: Sendable, Equatable {
        public let bytes: Int
        public let exists: Bool
        /// When its newest file changed; none when it holds nothing.
        public let newest: Date?
        /// Whether `purge --delete` may delete it (`cleanupEligible`): `locks` never.
        public let isReclaimable: Bool
    }

    /// The classes of a workspace that exist and `purge` may delete, by name, for `--classes`.
    public static func reclaimable(_ workspace: Workspace) -> [String] {
        workspace.classes.filter { $0.value.exists && $0.value.isReclaimable }.keys.sorted()
    }

    public enum Scope: Sendable {
        case all
        case workspace(String)
    }

    public let bytes: Int
    public let workspaces: [Workspace]

    /// How long a report may take: it walks every file of the workspaces it reports.
    static let timeout = Duration.seconds(60)

    init?(json: Data) {
        struct Totals: Decodable { let bytes: Int }
        struct Class: Decodable {
            let bytes: Int
            let exists: Bool
            let latestMtimeMs: Double?
            let cleanupEligible: Bool?
        }
        struct Entry: Decodable {
            let workspaceKey: String
            let path: String
            let totals: Totals
            let classes: [String: Class]
        }
        struct Answer: Decodable {
            let totals: Totals
            let workspaces: [Entry]
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: json) else { return nil }
        bytes = answer.totals.bytes
        workspaces = answer.workspaces.map { entry in
            Workspace(key: entry.workspaceKey, folder: entry.path, bytes: entry.totals.bytes, classes: entry.classes.mapValues { found in
                StorageClass(bytes: found.bytes, exists: found.exists, newest: found.latestMtimeMs.map { Date(timeIntervalSince1970: $0 / 1000) }, isReclaimable: found.cleanupEligible == true)
            })
        }
    }

    /// The report for `scope`; none when MobileBuildMCP couldn't answer, or answered otherwise.
    static func read(_ scope: Scope, using runner: any CommandRunning, timeout: Duration = timeout) async -> StorageReport? {
        let scoped = switch scope {
        case .all: ["--scope", "all"]
        case .workspace(let key): ["--scope", "workspace", "--workspace-key", key]
        }
        let answer = await runner.run(["mobilebuildmcp", "purge", "--report"] + scoped + ["--json"], stdin: nil, timeout: timeout)
        return answer.succeeded ? StorageReport(json: Data(answer.stdout.utf8)) : nil
    }
}
