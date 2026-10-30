import Foundation

/// An installed Xcode: where it is, its version and its build.
public struct XcodeInstall: Sendable, Equatable {
    public let path: String
    public let version: String
    public let build: String
}
