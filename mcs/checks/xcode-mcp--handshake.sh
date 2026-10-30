#!/bin/sh
# mcs doctor check; the logic is the Swift check of the same id.
exec "$(dirname "$0")/../../bin/xcrew" doctor --check xcode-mcp/handshake
