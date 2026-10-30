#!/bin/sh
# Fails when the installed Xcode's xccov answers in a shape xcrew no longer reads: the shape isn't documented
# (`man xccov`), so a change shows up here rather than as a changed-line note that's silently empty.
# Tests a one-file package with coverage on, then reads the fresh result bundle through xcrew's own code.
# scripts/coverage-shape.sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources/Shape" "$work/Tests/ShapeTests"
cat > "$work/Package.swift" <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(name: "Shape", targets: [.target(name: "Shape"), .testTarget(name: "ShapeTests", dependencies: ["Shape"])])
EOF
cat > "$work/Sources/Shape/Shape.swift" <<'EOF'
public func sign(of number: Int) -> Int {
    number < 0 ? -1 : 1
}
EOF
cat > "$work/Tests/ShapeTests/ShapeTests.swift" <<'EOF'
import Shape
import Testing

@Test func aPositiveNumberIsPositive() {
    #expect(sign(of: 2) == 1)
}
EOF
scheme=$(cd "$work" && xcodebuild -list -json 2> /dev/null | plutil -extract workspace.schemes.0 raw -o - -)
(cd "$work" && xcodebuild test -scheme "$scheme" -destination platform=macOS -enableCodeCoverage YES -derivedDataPath "$work/derived" -resultBundlePath "$work/Shape.xcresult" -quiet) > "$work/log" 2>&1 \
  || { tail -20 "$work/log" >&2; echo "coverage-shape.sh: the package's tests didn't run with coverage" >&2; exit 1; }
XCREW_COVERAGE_BUNDLE="$work/Shape.xcresult" swift test --filter LiveCoverageShapeTests > "$work/test" 2>&1 \
  || { tail -20 "$work/test" >&2; echo "coverage-shape.sh: xccov's coverage answers no longer read as xcrew expects" >&2; exit 1; }
grep -q "xccovStillAnswersInTheShapeXcrewReads() passed" "$work/test" \
  || { echo "coverage-shape.sh: the shape test didn't run" >&2; exit 1; }
