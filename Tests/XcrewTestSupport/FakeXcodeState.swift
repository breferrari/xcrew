import Foundation
import XcrewCore

/// Xcode's `UserInterfaceState.xcuserstate`, and a session whose MobileBuildMCP server Xcode may host, for the readers
/// that mirror MobileBuildMCP 2.7.1's.
public enum FakeXcodeState {
    /// The archive's shape as MobileBuildMCP's `parseXcuserstate` walks it: `$objects` holds the key names as strings, a
    /// dictionary whose `NS.keys` names `ActiveScheme`, and that key's value a dictionary whose `IDENameString` is the
    /// scheme. Built from the source, not captured.
    public static func archive(scheme: String?, archiver: String = "NSKeyedArchiver", withName: Bool = true) -> Data {
        let objects: [BinaryPropertyList] = [
            .string("$null"),
            .dictionary(["NS.keys": .array([.uid(2)]), "NS.objects": .array([.uid(3)])]),
            .string("ActiveScheme"),
            .dictionary(["NS.keys": .array([.uid(4)]), "NS.objects": .array([.uid(5)])]),
            .string(withName ? "IDENameString" : "IDEContainerPathString"),
            scheme.map(BinaryPropertyList.string) ?? .integer(7),
        ]
        let root: BinaryPropertyList = .dictionary([
            "$archiver": .string(archiver), "$objects": .array(objects), "$top": .dictionary(["root": .uid(1)]), "$version": .integer(100_000),
        ])
        return root.encoded
    }

    /// Where Xcode keeps a container's state for `user`, from the project's root.
    public static func path(of container: String, user: String = "someone") -> String {
        let workspace = container.hasSuffix(".xcworkspace") ? container : "\(container)/project.xcworkspace"
        return "\(workspace)/xcuserdata/\(user).xcuserdatad/UserInterfaceState.xcuserstate"
    }

    /// Writes a state selecting `scheme` for `container` in `project`.
    public static func write(scheme: String, for container: String, in project: Project) throws {
        let url = project.root.appending(path: path(of: container))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try archive(scheme: scheme).write(to: url)
    }
}

extension FakeRunner {
    /// A session (`claude`, pid 20) whose MobileBuildMCP server (30) serves `project`, started by Xcode (10) or by a shell,
    /// with this process as pid 40 and the user `someone`.
    public static func mobileBuildMCP(serving project: Project, underXcode: Bool) -> FakeRunner {
        let root = ProjectLayout.canonicalPath(project.root.path)
        let top = underXcode ? "/Applications/Xcode-27.2.0.app/Contents/MacOS/Xcode" : "/bin/zsh"
        let node = "/opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime"
        return FakeRunner(responses: [
            "ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: "  10     1 01:00 \(top)\n  20    10 01:00 claude\n  30    20 01:00 \(node) /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/build/cli.js mcp\n  40    20 01:00 xcrew project\n"),
            "ps -axo pid=,comm=": .init(status: 0, stdout: "  10 \(top)\n  20 claude\n  30 \(node)\n  40 xcrew\n"),
            "lsof -a -p 30 -d cwd -Fn": .init(status: 0, stdout: "p30\nfcwd\nn\(root)\n"),
            "whoami": .init(status: 0, stdout: "someone\n"),
        ])
    }
}
