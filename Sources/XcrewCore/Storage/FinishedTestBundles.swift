import Foundation

/// The test products a MobileBuildMCP test run builds for itself, in this checkout's workspace, once the run is done.
/// Each `test_*` call that's given no products of its own builds a fresh bundle, runs from it, and marks it done, and
/// MobileBuildMCP keeps it for days. Its result names it, so a later call may run from the one finished last without
/// building; the older ones nothing names again (docs/findings.md, *Disk space*). A `build_*` call's bundle is for a
/// later call to run, and stays.
public enum FinishedTestBundles {
    /// A bundle a test tool made for itself, as MobileBuildMCP 2.7.1 names it (`utils/test-products-path.js`):
    /// `<tool>_<ISO time>_pid<pid>_<8 hex>.xctestproducts`.
    static var name: Regex<Substring> { /^test_[a-z_]+_\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z_pid\d+_[a-f0-9]{8}\.xctestproducts$/ }

    /// Deletes this checkout's finished test-run bundles but the one whose run finished last, by its marker's time, each
    /// with its marker, and says how many went. A bundle that can't be deleted is left for the next time.
    public static func drop(project: Project, home: URL) -> Int {
        let items = RunLog.listed(in: "test-products", project: project.root, home: home, dated: true)
        let finishedAt = Dictionary(items.map { ($0.name, $0.modified) }, uniquingKeysWith: { first, _ in first })
        let finished = items.compactMap { item -> (folder: URL, name: String, at: Date)? in
            // A marker whose time can't be read leaves its bundle out, kept: it may be the run that finished last.
            guard item.name.wholeMatch(of: name) != nil, let at = finishedAt[item.name + ResultBundle.completionMark] ?? nil else { return nil }
            return (item.folder, item.name, at)
        }
        return finished.sorted { $0.at > $1.at }.dropFirst().count { item in
            guard (try? FileManager.default.removeItem(at: item.folder.appending(path: item.name))) != nil else { return false }
            try? FileManager.default.removeItem(at: item.folder.appending(path: item.name + ResultBundle.completionMark))
            return true
        }
    }
}
