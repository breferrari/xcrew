import Foundation

/// The agent skills the installed Xcode ships in its Claude plugin. Copied rather than linked:
/// the source folder is named after the Xcode build and moves with every Xcode update.
public struct XcodeSkills: Sendable {
    public let source: URL

    /// The skills folder of Xcode's plugin, or nil before Xcode 27.
    public static func locate(using runner: any CommandRunning) async -> XcodeSkills? {
        let output = await runner.run("xcrun", "mcpbridge", "run-agent", "plugin", "path", "--plugin-format", "claude")
        guard output.succeeded, let last = output.stdout.split(separator: "\n").last else { return nil }
        let skills = URL(fileURLWithPath: String(last)).appending(path: "skills")
        return FileManager.default.fileExists(atPath: skills.path) ? XcodeSkills(source: skills) : nil
    }

    /// The skills folder of Xcode's plugin on `machine`, or nil before Xcode 27.
    public static func locate(on machine: Machine) async -> XcodeSkills? {
        await locate(using: machine.runner)
    }

    /// Every skill this Xcode ships: a folder holding a `SKILL.md`.
    public var available: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []).sorted().filter {
            FileManager.default.fileExists(atPath: source.appending(path: "\($0)/SKILL.md").path)
        }
    }

    public struct CopyReport: Sendable, Equatable {
        public var copied: [String] = []
        /// Already in the project, so left alone: a team may keep its own skill of the same name.
        public var kept: [String] = []

        public init(copied: [String] = [], kept: [String] = []) {
            self.copied = copied
            self.kept = kept
        }
    }

    /// Copies `names` (all available ones when empty). A skill the project already has is kept
    /// unless `replacing` is set.
    public func copy(_ names: [String] = [], to destination: URL, replacing: Bool = false) throws -> CopyReport {
        let chosen = names.isEmpty ? available : names.filter(available.contains)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var report = CopyReport()
        for name in chosen {
            let target = destination.appending(path: name)
            if FileManager.default.fileExists(atPath: target.path) {
                guard replacing else {
                    report.kept.append(name)
                    continue
                }
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source.appending(path: name), to: target)
            report.copied.append(name)
        }
        return report
    }
}
