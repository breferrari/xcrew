import Foundation
import Testing

/// Every read of a file in Sources goes through `Machine.files`, or is in a file listed here with why it may read
/// directly: the project's own files, under a root a test owns; a path its input names; or a path below the Machine's
/// home or cache, which a test's Machine makes. The machine's other files, an Xcode, a binary, another checkout, are
/// read through the seam, so a test's Machine stands for the whole Mac (docs/findings.md, *What a test may read*).
struct DirectReadsTests {
    enum Reason: String {
        case project = "a root the test owns"
        case input = "a path its input names"
        case machineFolder = "a path below the Machine's home or cache"
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The seams themselves: the disk's reader, and the runner's own `PATH` lookup.
    static let seams: Set = ["Sources/XcrewCore/System/LocalFiles.swift", "Sources/XcrewCore/System/SystemCommandRunner.swift"]

    static let allowed: [String: Set<Reason>] = [
        "Sources/XcrewCLI/PhaseCommand.swift": [.input],
        "Sources/XcrewCLI/ProjectCommand.swift": [.project],
        "Sources/XcrewCLI/SetupCommand.swift": [.project],
        "Sources/XcrewCore/Affected/ProjectGraph.swift": [.project],
        "Sources/XcrewCore/Concurrency/LogLines.swift": [.input],
        "Sources/XcrewCore/Doctor/Checks/ConfigLoadedCheck.swift": [.project],
        "Sources/XcrewCore/Doctor/Checks/ProjectConfigCheck.swift": [.project],
        "Sources/XcrewCore/Doctor/Checks/SimulatorsCheck.swift": [.project],
        "Sources/XcrewCore/Evidence/EvidencePack.swift": [.input, .machineFolder],
        "Sources/XcrewCore/Graph/ModuleGraph.swift": [.project],
        "Sources/XcrewCore/Hooks/ProjectCard.swift": [.machineFolder],
        "Sources/XcrewCore/Hooks/SessionBriefing.swift": [.project],
        "Sources/XcrewCore/Hooks/SessionStamp.swift": [.machineFolder],
        "Sources/XcrewCore/Look/FailureHierarchy.swift": [.input],
        "Sources/XcrewCore/Look/Look.swift": [.input],
        "Sources/XcrewCore/MobileBuildMCP/ConfigWriter.swift": [.project],
        "Sources/XcrewCore/MobileBuildMCP/MobileBuildMCPStatus.swift": [.machineFolder],
        "Sources/XcrewCore/MobileBuildMCP/SetupChoices.swift": [.project],
        "Sources/XcrewCore/MobileBuildMCP/XcodeSelection.swift": [.project],
        "Sources/XcrewCore/Project/GitExclusion.swift": [.project],
        "Sources/XcrewCore/Project/Project.swift": [.project],
        "Sources/XcrewCore/Project/ProjectLayout.swift": [.project],
        "Sources/XcrewCore/Project/TestSchemes.swift": [.project],
        "Sources/XcrewCore/Project/WorktreeSimulatorRecord.swift": [.project],
        "Sources/XcrewCore/Project/XcodeGenSpec.swift": [.project],
        "Sources/XcrewCore/Reports/ChangedLineCoverage.swift": [.input],
        "Sources/XcrewCore/Reports/FailureImages.swift": [.input, .machineFolder],
        "Sources/XcrewCore/Reports/LogReading.swift": [.input, .machineFolder],
        "Sources/XcrewCore/Reports/Report.swift": [.input],
        "Sources/XcrewCore/Reports/ResultBundle.swift": [.input],
        "Sources/XcrewCore/Reports/RunLog.swift": [.input, .machineFolder],
        "Sources/XcrewCore/Storage/AgedEntries.swift": [.machineFolder],
        "Sources/XcrewCore/Storage/ProjectWorkspaces.swift": [.machineFolder],
        "Sources/XcrewCore/Storage/Space.swift": [.machineFolder],
        "Sources/XcrewCore/System/StandardInput.swift": [.input],
        "Sources/XcrewCore/System/TextFile.swift": [.input],
        "Sources/XcrewCore/Xcode/CIXcodes.swift": [.project],
        "Sources/XcrewCore/Xcode/Xcodes.swift": [.machineFolder],
        "Sources/XcrewCore/XcodeSkills/XcodeSkills.swift": [.project],
    ]

    /// A read of a file, as Foundation offers one.
    static var read: Regex<Substring> { #/(?:Data|String)\(contentsOf|contentsOfFile|contentsOfDirectory|fileExists\(|attributesOfItem|resourceValues\(|enumerator\(at|FileHandle\(forReading|contents\(atPath|destinationOfSymbolicLink|subpathsOfDirectory/# }
    /// A path of the machine's own, named in a line.
    static var machinePath: Regex<Substring> { #/machine\.home|cacheFolder|homeDirectoryForCurrentUser|NSHomeDirectory|"\/Applications|Library\/(?:Caches|Developer)/# }

    /// Each Swift file in Sources with the lines that read a file, numbered from 1.
    static func reads() throws -> [String: [(line: Int, text: String)]] {
        let sources = root.appending(path: "Sources")
        var found: [String: [(Int, String)]] = [:]
        for case let file as URL in FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)! where file.pathExtension == "swift" {
            let path = String(file.path.dropFirst(root.path.count + 1))
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated().filter { $0.element.firstMatch(of: read) != nil }
            if !lines.isEmpty { found[path] = lines.map { ($0.offset + 1, $0.element) } }
        }
        return found
    }

    @Test func everyDirectReadIsInAFileListedWithItsReason() throws {
        let reads = try Self.reads()
        let unlisted = reads.keys.filter { Self.allowed[$0] == nil && !Self.seams.contains($0) }.sorted()
        #expect(unlisted.isEmpty, "reads a file directly, not through Machine.files, and isn't listed with why: \(unlisted.map { "\($0): \(reads[$0]!.map(\.line))" })")
        let stale = Self.allowed.keys.filter { reads[$0] == nil }.sorted()
        #expect(stale.isEmpty, "listed but reads nothing directly: \(stale)")
    }

    /// A file listed for the project's files or its input's never reads a path of the machine's own in the same line.
    @Test func aProjectOrInputReadNamesNoMachinePath() throws {
        let reads = try Self.reads()
        for (file, reasons) in Self.allowed where !reasons.contains(.machineFolder) {
            for read in reads[file] ?? [] where read.text.firstMatch(of: Self.machinePath) != nil {
                Issue.record("\(file):\(read.line) reads a path of the machine's own: \(read.text.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    /// The files whose reads below the Machine's home or cache this check can't follow to the Machine, and why: their
    /// path comes from a value made in another function.
    static let unseen: [String: String] = [:]

    /// A file listed for the Machine's home or cache reads in a function that builds its path from the Machine: one that
    /// names `machine`, `home` or `cacheFolder`, or a folder made from them.
    @Test func aMachineFolderReadBuildsItsPathFromTheMachine() throws {
        let sources = Self.root.appending(path: "Sources")
        let reads = try Self.reads()
        for (file, reasons) in Self.allowed where reasons == [.machineFolder] && Self.unseen[file] == nil {
            let lines = try String(contentsOf: sources.deletingLastPathComponent().appending(path: file), encoding: .utf8).components(separatedBy: "\n")
            for read in reads[file] ?? [] {
                let start = lines[..<read.line].lastIndex { $0.contains("func ") || $0.contains("var ") && $0.contains("{") } ?? 0
                let body = lines[start..<read.line].joined(separator: "\n")
                if body.firstMatch(of: #/machine|home|cacheFolder/#) == nil {
                    Issue.record("\(file):\(read.line) reads below no folder of the Machine's it can see")
                }
            }
        }
    }
}
