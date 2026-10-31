#!/bin/sh
# Fails when the installed Claude Code words a call it moved to the background, or the notification its task ends
# with, so that xcrew no longer reads them: each is built from the executable's own template.
# scripts/background-texts.sh <Claude Code's executable>   the test bed is XCREW_TESTBED, else the clone beside this repository
set -eu
cd "$(dirname "$0")/.."
testbed=${XCREW_TESTBED:-../xcrew-testbed}
# The handle: the template's `${…}` is the task's id.
handle=$(perl -0777 -ne '
  if (/(It was moved to the background as task \$\{[^}]*\}[^`]*)`/) {
    my $t = $1; $t =~ s/\$\{[^}]*\}/canary7/; print "MCP tool \"plugin:xcrew:MobileBuildMCP/build_sim\" is still running after 120s. $t"; exit 0
  }
  exit 1' "$1") || {
  echo "Claude Code's executable has no 'It was moved to the background as task \${…}' handle: xcrew finds a backgrounded call's task by those words, so read the new handle and update Report.backgroundTask and scripts/background-texts.sh" >&2
  exit 1
}
printf '%s' "$handle" | bin/xcrew report --server MobileBuildMCP --kind build | grep -qF '"backgroundTask":"canary7"' || {
  echo "xcrew didn't read the task in Claude Code's handle, which now reads \"$handle\": check Report.backgroundTask against it" >&2
  exit 1
}
# The notification: its tags are constants, and an MCP task's result sits between `<result>` lines.
perl -0777 -ne 'exit !(/="task-notification"/ && /="task-id"/ && /="status"/ && /`\n<result>\n\$\{[^`]*\}\n<\/result>`/)' "$1" || {
  echo "Claude Code's executable no longer builds a task's notification with the task-id and status tags and its result between <result> lines: xcrew reads a backgrounded call's result there, so read the new notification and update TaskNotification and scripts/background-texts.sh" >&2
  exit 1
}
notification=$(printf '<task-notification>\n<task-id>canary7</task-id>\n<status>completed</status>\n<summary>MCP task canary7 (plugin:xcrew:MobileBuildMCP/build_sim) completed.</summary>\n<result>\n%s\n</result>\n</task-notification>' "$(cat "$testbed/captures/field/type-error.txt")")
printf '%s' "$notification" | bin/xcrew report --server MobileBuildMCP --kind build --notification | grep -qF '"ok":false' && exit 0
echo "xcrew didn't read the failed build in a task's notification: check TaskNotification against the notification Claude Code builds" >&2
exit 1
