#!/bin/sh
# Fails when the installed Claude Code words the notice for a result it saved to a file so that xcrew
# no longer reads the result back: the notice is built from the executable's own template.
# scripts/saved-notice.sh <Claude Code's executable>
set -eu
cd "$(dirname "$0")/.."
folder=$(mktemp -d)
saved="$folder/tool-results/mcp-test_sim-1.txt"
mkdir "$folder/tool-results"
cp Tests/XcrewCoreTests/Fixtures/Reports/mobileTestsPassed.txt "$saved"
# The first `${…}` is the saved file, the rest its format. Exits 2 when the words are there but no template.
status=0
notice=$(SAVED="$saved" perl -0777 -ne '
  if (/(Output has been saved to \$\{[^}]*\}[^`]*)`/) {
    my ($t, $n) = ($1, 0); $t =~ s/\$\{[^}]*\}/$n++ ? "JSON" : $ENV{SAVED}/ge;
    print "Error: result (121,948 characters) exceeds maximum allowed tokens. $t"; exit 0
  }
  exit(/Output has been saved to/ ? 2 : 1)' "$1") || status=$?
case $status in
  0) ;;
  2) echo "Claude Code's executable has the words 'Output has been saved to' but no template with them as text, so this check can't read the notice: rework scripts/saved-notice.sh" >&2; exit 1 ;;
  *) echo "Claude Code's executable has no 'Output has been saved to \${…}' notice: find how it words a saved result now and update Report.savedPath to match" >&2; exit 1 ;;
esac
printf '%s' "$notice" | bin/xcrew report --server MobileBuildMCP --kind test | grep -qF "the full result is in $saved" && exit 0
echo "xcrew didn't read back a result saved under Claude Code's notice, which now reads \"$notice\": update Report.savedPath to match" >&2
exit 1
