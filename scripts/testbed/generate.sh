#!/bin/sh
# Regenerates the test bed's forms: one app (Tests/Testbed/base) expressed as each project form, at the
# repository root and under ios/. Runs on a Mac with Xcode 27.2 or later, Tuist and XcodeGen
# (brew install tuist xcodegen); CI never runs it, it reads what this wrote.
# scripts/testbed/generate.sh [--build]   --build also builds each form for testing, to prove it's real
set -eu
cd "$(dirname "$0")/../.."
testbed=Tests/Testbed
base=$testbed/base
build=${1:-}
xcode=$(xcodebuild -version | head -1 | sed 's/Xcode //')
tuist_version=$(tuist version | tail -1)
xcodegen_version=$(xcodegen version | sed 's/Version: //')

sources() {
  mkdir -p "$1"
  cp -R "$base/App" "$base/AppTests" "$1/"
}

xcodegen_spec() {
  cat > "$1/project.yml" <<EOF
name: App
options:
  bundleIdPrefix: dev.xcrew.testbed
  deploymentTarget:
    iOS: "18.0"
  defaultSourceDirectoryType: $2
targets:
  App:
    type: application
    platform: iOS
    sources: [App]
    settings:
      GENERATE_INFOPLIST_FILE: YES
  AppTests:
    type: bundle.unit-test
    platform: iOS
    sources: [AppTests]
    dependencies:
      - target: App
    settings:
      GENERATE_INFOPLIST_FILE: YES
schemes:
  App:
    build:
      targets:
        App: all
    test:
      targets: [AppTests]
EOF
}

tuist_manifests() {
  cat > "$1/Tuist.swift" <<'EOF'
import ProjectDescription

let tuist = Tuist()
EOF
  cat > "$1/Project.swift" <<'EOF'
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(name: "App", destinations: .iOS, product: .app, bundleId: "dev.xcrew.testbed.App", deploymentTargets: .iOS("18.0"), infoPlist: .default, sources: ["App/**"]),
        .target(name: "AppTests", destinations: .iOS, product: .unitTests, bundleId: "dev.xcrew.testbed.AppTests", deploymentTargets: .iOS("18.0"), infoPlist: .default, sources: ["AppTests/**"], dependencies: [.target(name: "App")]),
    ]
)
EOF
}

# The JSON form, built with Xcode's own `xcodeproj` tool. Build phases come before `group include`: included into a
# target without phases, a synchronized folder's files are all recorded as exclusions (docs/findings.md).
json_project() {
  (
    cd "$1"
    xcrun xcodeproj init App.xcodeproj > /dev/null
    x() { xcrun xcodeproj "$@" -P App.xcodeproj > /dev/null; }
    x target add App --product-type application
    x target add AppTests --product-type unit-test-bundle
    for target in App AppTests; do
      for kind in sources frameworks resources; do x target phase add --target "$target" "$kind"; done
    done
    x group add App --filesystem-path App
    x group add AppTests --filesystem-path AppTests
    x group include --group App --target App
    x group include --group AppTests --target AppTests
    x target add-dependency AppTests App
    x setting set SDKROOT iphoneos
    x setting set IPHONEOS_DEPLOYMENT_TARGET 18.0
    x setting set SWIFT_VERSION 5.0
    x setting set TARGETED_DEVICE_FAMILY 1,2
    x setting set ALWAYS_SEARCH_USER_PATHS NO
    x setting set ENABLE_TESTABILITY YES
    x setting set PRODUCT_BUNDLE_IDENTIFIER dev.xcrew.testbed.App --target App
    x setting set PRODUCT_BUNDLE_IDENTIFIER dev.xcrew.testbed.AppTests --target AppTests
    # shellcheck disable=SC2016 # Xcode expands these, not the shell.
    x setting set TEST_HOST '$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App' --target AppTests
    # shellcheck disable=SC2016
    x setting set BUNDLE_LOADER '$(TEST_HOST)' --target AppTests
  )
}

xcodegen_project() {
  xcodegen_spec "$1" "$2"
  xcodegen generate --quiet --spec "$1/project.yml" --project "$1"
}

fixture_json() {
  generator=$3
  version=""
  case $generator in
    tuist) version=$tuist_version ;;
    xcodegen) version=$xcodegen_version ;;
  esac
  cat > "$1/fixture.json" <<EOF
{
  "definition": "$2",
  "generator": "$generator",
  "generatorVersion": "$version",
  "layout": "$4",
  "xcode": "$xcode"
}
EOF
}

form() {
  name=$1 layout=$2 suffix="" folder=""
  if [ "$layout" = ios ]; then suffix=-ios folder=/ios; fi
  fixture=$testbed/forms/$name$suffix
  # The expectation is written by hand, not generated: it outlives the fixture's regeneration.
  expectation=$(cat "$fixture/expect.xcrew.json" 2>/dev/null || true)
  rm -rf "$fixture"
  project=$fixture$folder
  sources "$project"
  case $name in
    classic)
      xcodegen_project "$project" group
      rm "$project/project.yml"
      fixture_json "$fixture" pbxproj-groups none "$layout" ;;
    folders)
      xcodegen_project "$project" syncedFolder
      rm "$project/project.yml"
      grep -q PBXFileSystemSynchronizedRootGroup "$project/App.xcodeproj/project.pbxproj"
      fixture_json "$fixture" pbxproj-folders none "$layout" ;;
    json)
      json_project "$project"
      # `xcodeproj` writes no scheme: the JSON form shares the one XcodeGen wrote for the classic form.
      mkdir -p "$project/App.xcodeproj/xcshareddata/xcschemes"
      cp "$testbed/forms/classic$suffix$folder/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme" "$project/App.xcodeproj/xcshareddata/xcschemes/"
      fixture_json "$fixture" json none "$layout" ;;
    xcodegen)
      xcodegen_project "$project" group
      fixture_json "$fixture" pbxproj-groups xcodegen "$layout" ;;
    tuist)
      tuist_manifests "$project"
      (cd "$project" && tuist generate --no-open > /dev/null)
      # Tuist's own convenience scheme runs `tuist generate` from the absolute path it was made in.
      rm "$project/App.xcworkspace/xcshareddata/xcschemes/Generate Project.xcscheme"
      fixture_json "$fixture" pbxproj-groups tuist "$layout" ;;
    tuist-ungenerated)
      tuist_manifests "$project"
      fixture_json "$fixture" none tuist "$layout" ;;
  esac
  if [ "$name" != tuist-ungenerated ]; then
    if [ -d "$project/App.xcworkspace" ]; then
      container=App.xcworkspace flag=-workspace
    else
      container=App.xcodeproj flag=-project
    fi
    (cd "$project" && xcodebuild -list "$flag" "$container" > /dev/null)
    if [ "$build" = --build ]; then
      derived=$(mktemp -d)
      (cd "$project" && xcodebuild build-for-testing "$flag" "$container" -scheme App -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO -quiet)
      test -x "$derived/Build/Products/Debug-iphonesimulator/App.app/App"
      rm -rf "$derived"
    fi
  fi
  if [ -n "$expectation" ]; then printf '%s\n' "$expectation" > "$fixture/expect.xcrew.json"; fi
  # Opening or building a project writes the user's own state, under their name: never part of a fixture.
  find "$fixture" -name xcuserdata -prune -exec rm -rf {} +
  echo "$fixture"
}

for name in classic folders json xcodegen tuist tuist-ungenerated; do
  for layout in root ios; do form "$name" "$layout"; done
done
