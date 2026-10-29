import Foundation

/// What xcrew was handed on standard input. Claude Code closes a hook's and the mod's stdin, but a script can leave
/// it open, and reading to end of file would then wait for as long as that caller lives.
public enum StandardInput {
    /// How long stdin may stay open with nothing new arriving before xcrew stops reading it and goes on.
    public static let idleLimit = Duration.seconds(2)
    /// What xcrew says on stderr when it stops reading an input its caller never closed.
    public static let cutNote = "xcrew: stopped reading standard input once nothing more arrived; close it when you're done writing\n"

    /// All of the input once the caller closes it, or what arrived before it went quiet for `limit`; `isComplete` says
    /// which. A file is read to its end at once, since only a pipe or a terminal can be left open.
    public static func read(_ handle: FileHandle, idleFor limit: Duration) async -> (data: Data, isComplete: Bool) {
        if isRegularFile(handle) { return ((try? handle.readToEnd()) ?? Data(), true) }
        let drain = Drain(handle)
        let isComplete = await drain.ended(idleFor: limit)
        return (drain.data, isComplete)
    }

    /// The file system's type for the handle's descriptor, read through `/dev/fd` (docs/findings.md).
    static func isRegularFile(_ handle: FileHandle) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: "/dev/fd/\(handle.fileDescriptor)"))?[.type] as? FileAttributeType) == .typeRegular
    }
}
