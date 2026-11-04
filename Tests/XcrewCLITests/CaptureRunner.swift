import Foundation
import XcrewCore
import XcrewTestSupport

/// xcresulttool as it answered about one capture's result bundle, from the files the test bed keeps beside it: the
/// bundle's tests and summary, each test's details and activities by the id each names, and for `export attachments`
/// what the capture's lookups recorded (its attachments where they answered one) or its crash log. Anything else isn't
/// found. Each answer is the file's bytes, so the same capture always answers the same.
struct CaptureRunner: CommandRunning {
    let responses: [String: CommandResult]
    let bundle: String
    let attachments: URL?
    let exportingAttachments: Set<String>
    let crashLog: URL?
    /// For a capture kept as a folder of xcresulttool's answers, the folder every export copies whole.
    let exportingAll: URL?

    /// The capture `name` in `folder`, its result bundle at `bundle`.
    init(_ name: String, in folder: URL, bundle: String) throws {
        func text(_ file: String) throws -> String { try String(contentsOf: folder.appending(path: file), encoding: .utf8) }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var responses: [String: CommandResult] = [:]
        for (kind, file) in [("tests", "\(name).tests.json"), ("summary", "\(name).summary.json")] where files.contains(file) {
            responses["xcrun xcresulttool get test-results \(kind) --path \(bundle) --compact"] = .init(status: 0, stdout: try text(file))
        }
        for (prefix, command) in [("\(name).details.", "test-details"), ("\(name).activities.", "activities")] {
            for file in files.sorted() where file.hasPrefix(prefix) && file.hasSuffix(".json") {
                let answer = try text(file)
                let named = (try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])?["testIdentifier"] as? String
                let id = named.flatMap { $0.contains("/") ? $0 : nil }
                    ?? file.dropFirst(prefix.count).dropLast(".json".count).replacingOccurrences(of: ".", with: "/") + "()"
                responses["xcrun xcresulttool get test-results \(command) --test-id \(id) --path \(bundle) --compact"] = .init(status: 0, stdout: answer)
            }
        }
        self.responses = responses
        self.bundle = bundle
        let attached = folder.appending(path: "\(name)-attachments")
        attachments = FileManager.default.fileExists(atPath: attached.path) ? attached : nil
        let lookups = (try? JSONSerialization.jsonObject(with: Data(text("\(name).lookups.json").utf8))) as? [String: [String: Any]] ?? [:]
        exportingAttachments = Set(lookups.compactMap { id, answered in ((answered["export attachments"] as? Int) ?? 0) > 0 ? id : nil })
        crashLog = ["\(name).crash.ips", "\(name).ips"].map { folder.appending(path: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        exportingAll = nil
    }

    /// A capture kept as a folder of xcresulttool's answers, as the UI-test and snapshot captures are: `tests.json`, each
    /// test's `details-<test>.json` and `activities-<test>.json`, and its attachments, which every export copies whole.
    init(folder: URL, bundle: String) throws {
        func text(_ file: String) throws -> String { try String(contentsOf: folder.appending(path: file), encoding: .utf8) }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var responses: [String: CommandResult] = [:]
        if files.contains("tests.json") { responses["xcrun xcresulttool get test-results tests --path \(bundle) --compact"] = .init(status: 0, stdout: try text("tests.json")) }
        for (prefix, command) in [("details-", "test-details"), ("activities-", "activities")] {
            for file in files.sorted() where file.hasPrefix(prefix) && file.hasSuffix(".json") {
                let answer = try text(file)
                guard let id = (try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])?["testIdentifier"] as? String else { continue }
                responses["xcrun xcresulttool get test-results \(command) --test-id \(id) --path \(bundle) --compact"] = .init(status: 0, stdout: answer)
            }
        }
        self.responses = responses
        self.bundle = bundle
        attachments = nil
        exportingAttachments = []
        crashLog = nil
        exportingAll = folder
    }

    func which(_ name: String) -> String? { nil }

    func run(_ argv: [String], stdin: Data?) async -> CommandResult {
        if let answer = responses[argv.joined(separator: " ")] { return answer }
        guard argv.starts(with: ["xcrun", "xcresulttool", "export", "attachments"]), let output = argv.firstIndex(of: "--output-path").map({ argv[$0 + 1] }) else {
            return .init(status: 1)
        }
        let test = argv.firstIndex(of: "--test-id").map { argv[$0 + 1] }
        let manager = FileManager.default
        try? manager.createDirectory(atPath: output, withIntermediateDirectories: true)
        if let attachments, let test, exportingAttachments.contains(test) {
            for file in (try? manager.contentsOfDirectory(atPath: attachments.path)) ?? [] {
                try? manager.copyItem(at: attachments.appending(path: file), to: URL(fileURLWithPath: output).appending(path: file))
            }
        }
        if let crashLog { try? manager.copyItem(at: crashLog, to: URL(fileURLWithPath: output).appending(path: "crash.ips")) }
        if let exportingAll {
            for file in (try? manager.contentsOfDirectory(atPath: exportingAll.path)) ?? [] where !file.hasSuffix(".json") || file == "manifest.json" {
                try? manager.copyItem(at: exportingAll.appending(path: file), to: URL(fileURLWithPath: output).appending(path: file))
            }
        }
        return .init(status: 0)
    }
}
