import Foundation

import XcrewCore

/// The folders, among those named, that aren't there any more: the mod drops what it stored for a checkout that's gone,
/// as a worktree removed since, at a session's start.
struct GoneCommand: Command {
    let name = "gone"
    let takesWords = true
    let usage = [
        "gone <folder>...   (mod) the folders named that aren't there any more, as JSON",
    ]

    /// The folders found gone, in the order they were named.
    struct Answer: Codable, Equatable {
        let gone: [String]
    }

    /// The folders the system says don't exist, whose parent folder still does, each on a volume that's mounted: a folder
    /// under `/Volumes/<name>` needs that volume among `mounted`, as a drive taken out leaves its folders unreachable but
    /// not gone, and anything else is on the startup volume. A removed worktree leaves the folder that held it, where an
    /// unmounted share's folders go with their mount. A folder that can't be looked at, as one macOS's privacy rules
    /// refuse, isn't gone, nor is a name that isn't an absolute path.
    static func gone(_ folders: [String], mounted: Set<String>, files: any FileReading) -> [String] {
        folders.filter { folder in
            let parent = (folder as NSString).deletingLastPathComponent
            guard folder.hasPrefix("/"), files.isMissing(URL(fileURLWithPath: folder)), mounted.contains(parent) || !files.isMissing(URL(fileURLWithPath: parent)) else { return false }
            let parts = folder.split(separator: "/")
            guard parts.first == "Volumes", parts.count > 1 else { return true }
            return mounted.contains("/Volumes/\(parts[1])")
        }
    }

    /// The mounted volumes' paths, as `FileManager` lists them; none when it can't.
    static var mounted: Set<String> {
        Set((FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []).map(\.path))
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let gone = Self.gone(invocation.arguments.positional, mounted: Self.mounted, files: invocation.context.machine.files)
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(Answer(gone: gone)), as: UTF8.self))
        return 0
    }
}
