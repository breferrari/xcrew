# Security

Xcrew runs on your Mac with your permissions: it starts MCP servers, runs Xcode's tools and writes `.mobilebuildmcp/` in your project. Its one network request is `xcrew doctor`'s check for a newer release, against GitHub's API.

Please report a vulnerability privately through [GitHub's security advisories](https://github.com/breferrari/xcrew/security/advisories/new) rather than an issue. Expect an answer within a week.

Xcrew also checks that Xcode's `IDEAllowUnauthenticatedAgents` is off: with it on, any unsigned process on the Mac can drive Xcode's tools.
