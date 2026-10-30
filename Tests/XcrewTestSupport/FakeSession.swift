import Foundation
import XcrewCore

/// A Claude Code session as `ps` and `lsof` show it: Claude Code (100), the MobileBuildMCP server it started (200) in a
/// project, `age` old by `ps`'s `etime`, and the doctor asking (300); and other programs running, by id and path.
public enum FakeSession {
    public static let doctor: Int32 = 300
    public static let server = "/opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/build/cli.js mcp"

    public static func responses(serving project: Project?, age: String = "00:30", programs: [Int32: String] = [:]) -> [String: CommandResult] {
        var ps = ["  100     1 01:00:00 /Users/me/.local/bin/claude", "  300   100    00:01 /plugins/xcrew/.build/xcrew doctor --problems --json"]
        var comm = ["  100 /Users/me/.local/bin/claude", "  300 /plugins/xcrew/.build/xcrew"]
        if project != nil {
            ps.append("  200   100 \(age) \(server)")
            comm.append("  200 /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime")
        }
        for (id, path) in programs.sorted(by: { $0.key < $1.key }) {
            ps.append("  \(id)     1    00:10 \(path)")
            comm.append("  \(id) \(path)")
        }
        var responses: [String: CommandResult] = [
            "ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: ps.joined(separator: "\n") + "\n"),
            "ps -axo pid=,comm=": .init(status: 0, stdout: comm.joined(separator: "\n") + "\n"),
        ]
        if let project { responses["lsof -a -p 200 -d cwd -Fn"] = .init(status: 0, stdout: "p200\nfcwd\nn\(project.root.path)\n") }
        return responses
    }
}
