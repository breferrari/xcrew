import Foundation

/// A cached module cut short or corrupted in the build's DerivedData, which every later build reads again until it's
/// removed. Two wordings, from the test bed's `captures/environment` (docs/findings.md, *Builds that fail because of
/// the Mac*): Clang's cache gives "malformed or corrupted precompiled file", the SDK's precompiled modules "file '….pcm'
/// is not a valid module file". "missing required module" and "could not build module" follow either, and a module
/// that isn't there gives them too, so they say nothing alone.
struct CorruptModuleCache: MachineCause {
    static let folders = ["ModuleCache.noindex", "SDKExplicitPrecompiledModules"]

    func explanation(of failure: FailureEvidence) async -> String? {
        guard let (quoted, named) = found(in: failure) else { return nil }
        let derivedData = named ?? failure.log().flatMap(BuildLog.derivedData(ofLogAt:))
        return "a module in its DerivedData's module cache is corrupt (\"\(quoted)\"). \(Self.fix(derivedData: derivedData))"
    }

    /// The words that show it, and the DerivedData folder the error names, if it names one.
    func found(in failure: FailureEvidence) -> (quoted: String, derivedData: String?)? {
        if !failure.errors(startingWith: "malformed or corrupted precompiled file").isEmpty {
            return ("malformed or corrupted precompiled file", nil)
        }
        let invalid = failure.errors(startingWith: "file '").lazy.compactMap { $0.message.firstMatch(of: #/^file '(\/[^']+\.pcm)' is not a valid module file/#) }
        guard let module = invalid.first.map({ String($0.1) }) else { return nil }
        let derivedData = Self.folders.lazy.compactMap { folder in module.range(of: "/\(folder)/").map { String(module[..<$0.lowerBound]) } }.first
        return ("\(URL(fileURLWithPath: module).lastPathComponent) is not a valid module file", derivedData)
    }

    /// What to remove: the two folders in the DerivedData, by path when it's known.
    static func fix(derivedData: String?) -> String {
        guard let derivedData else {
            return "Remove \(folders.joined(separator: " and ")) from the DerivedData this build used, then build again"
        }
        return "Remove the cached modules, then build again: rm -rf \(folders.map { quoted("\(derivedData)/\($0)") }.joined(separator: " "))"
    }

    /// A path as one shell word: in single quotes, each one inside it closed, escaped and reopened.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
