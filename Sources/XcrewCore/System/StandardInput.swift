import Foundation

/// What xcrew was handed on standard input. Claude Code closes a hook's and the mod's stdin, but a script can leave
/// it open, and reading to end of file would then wait for as long as that caller lives.
public enum StandardInput {
    /// All of the input once the caller closes it, or what arrived within `limit` if it doesn't.
    public static func read(_ handle: FileHandle, within limit: Duration) async -> Data {
        let drain = Drain(handle)
        await drain.ended(by: .now + limit)
        return drain.data
    }
}
