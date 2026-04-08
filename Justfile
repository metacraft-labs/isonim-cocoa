# IsoNim-Cocoa — Apple Platform Renderer

set shell := ["bash", "-euo", "pipefail", "-c"]

# ─────────────────────────────────────────────────────────────────────────────
# Environment
# ─────────────────────────────────────────────────────────────────────────────

# Verify dev environment prerequisites
verify-env:
    #!/usr/bin/env bash
    set -e
    echo "Nim:        $(nim --version | head -1)"
    echo "Xcode:      $(xcodebuild -version 2>/dev/null | head -1 || echo 'NOT FOUND')"
    echo "XcodeGen:   $(xcodegen version 2>/dev/null || echo 'NOT FOUND')"
    echo "ios-deploy: $(ios-deploy --version 2>/dev/null || echo 'NOT FOUND')"
    echo "clang:      $(clang --version 2>/dev/null | head -1)"
    echo "macOS SDK:  $(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo 'NOT FOUND')"
    echo "iOS SDK:    $(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || echo 'NOT FOUND')"
    echo "Simulators: $(xcrun simctl list devices available 2>/dev/null | grep -c 'iPhone' || echo '0') available"
    echo "Devices:    $(xcrun xctrace list devices 2>/dev/null | grep -c 'iPhone (' || echo '0') connected"

# ─────────────────────────────────────────────────────────────────────────────
# Nim tests (headless, no Xcode needed)
# ─────────────────────────────────────────────────────────────────────────────

# Run ObjC runtime tests (M0)
test-objc:
    nim c -r --nimcache:nimcache/test_objc_runtime tests/test_objc_runtime.nim

# Run AppKit view tests (M1)
test-views:
    nim c -r --nimcache:nimcache/test_appkit_views tests/test_appkit_views.nim

# Run renderer tests (M2)
test-renderer:
    nim c -r --nimcache:nimcache/test_renderer tests/test_renderer.nim

# Run test infrastructure tests (FakeClock, snapshots)
test-infra:
    nim c -r --nimcache:nimcache/test_fake_clock tests/test_fake_clock.nim
    nim c -r --nimcache:nimcache/test_snapshots tests/test_snapshots.nim

# Run cross-renderer tests (requires isonim core as sibling)
test-cross:
    nim c -r --path:../isonim/src --nimcache:nimcache/test_cross_renderer tests/test_cross_renderer.nim

# Run all headless Nim tests
test: test-objc test-views test-renderer test-infra

# Run all tests including cross-renderer
test-all: test test-cross

# ─────────────────────────────────────────────────────────────────────────────
# Xcode project (generated via XcodeGen)
# ─────────────────────────────────────────────────────────────────────────────

# Generate Xcode project from project.yml
xcode-generate:
    xcodegen generate

# Build iOS app for simulator (env -i avoids Nix linker pollution)
xcode-build-sim: xcode-generate
    /usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild build \
        -project IsoNimCocoa.xcodeproj \
        -scheme Native \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
        -configuration Debug \
        2>&1 | tail -5

# Run XCTests on iOS Simulator (env -i avoids Nix linker pollution)
xcode-test-sim: xcode-generate
    /usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild test \
        -project IsoNimCocoa.xcodeproj \
        -scheme Native \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
        -configuration Debug \
        2>&1 | grep -E "Test Case|Executed|BUILD"

# ─────────────────────────────────────────────────────────────────────────────
# Device deployment
# ─────────────────────────────────────────────────────────────────────────────

# Build iOS app for device (ARM64, signed)
xcode-build-device: xcode-generate
    /usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild build \
        -project IsoNimCocoa.xcodeproj \
        -scheme Native \
        -destination 'generic/platform=iOS' \
        -configuration Debug \
        CODE_SIGN_IDENTITY="Apple Development" \
        2>&1 | tail -5

# Deploy to connected iPhone via ios-deploy
deploy-device: xcode-build-device
    #!/usr/bin/env bash
    set -euo pipefail
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Tasks Native.app" -path "*/Debug-iphoneos/*" | head -1)
    if [ -z "$APP_PATH" ]; then
      echo "Error: .app not found. Run 'just xcode-build-device' first."
      exit 1
    fi
    echo "Deploying $APP_PATH..."
    ios-deploy --bundle "$APP_PATH"

# Deploy app to connected iPhone (native variant, with team provisioning)
deploy-iphone: xcode-generate
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/bin/env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild build \
        -project IsoNimCocoa.xcodeproj \
        -target IsoNimCocoa-Native \
        -configuration Debug \
        DEVELOPMENT_TEAM=GK3D7BH967 \
        -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates 2>&1 | tail -3
    APP=$(find build -name "Tasks Native.app" -path "*/Debug-iphoneos/*" | head -1)
    echo "Installing $APP..."
    ios-deploy --bundle "$APP" --justlaunch 2>&1 | tail -3
    echo "Done — app should be running on iPhone"

# Deploy native-themed app to iPhone
deploy-native: xcode-generate
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/bin/env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild build \
        -project IsoNimCocoa.xcodeproj \
        -target IsoNimCocoa-Native \
        -configuration Debug \
        DEVELOPMENT_TEAM=GK3D7BH967 \
        -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates 2>&1 | tail -3
    APP=$(find build -name "Tasks Native.app" -path "*/Debug-iphoneos/*" | head -1)
    echo "Installing $APP..."
    ios-deploy --bundle "$APP" --justlaunch 2>&1 | tail -3
    echo "Native app deployed"

# Deploy branded (IsoNim theme) app to iPhone
deploy-branded: xcode-generate
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/bin/env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild build \
        -project IsoNimCocoa.xcodeproj \
        -target IsoNimCocoa-Branded \
        -configuration Debug \
        DEVELOPMENT_TEAM=GK3D7BH967 \
        -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates 2>&1 | tail -3
    APP=$(find build -name "Tasks IsoNim.app" -path "*/Debug-iphoneos/*" | head -1)
    echo "Installing $APP..."
    ios-deploy --bundle "$APP" --justlaunch 2>&1 | tail -3
    echo "Branded app deployed"

# Deploy both variants to iPhone
deploy-both: deploy-native deploy-branded

# Run XCTests on connected device
test-device: xcode-generate
    /usr/bin/env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild test \
        -project IsoNimCocoa.xcodeproj \
        -scheme Native \
        -destination 'platform=iOS,name=iPhone' \
        -configuration Debug \
        DEVELOPMENT_TEAM=GK3D7BH967 \
        -allowProvisioningUpdates \
        2>&1 | grep -E "Test Case|Executed|BUILD"

# ─────────────────────────────────────────────────────────────────────────────
# Visual snapshot management
# ─────────────────────────────────────────────────────────────────────────────

# Update all golden snapshots (run after intentional visual changes)
snapshot-update:
    rm -rf tests/golden/*.png
    nim c -r --nimcache:nimcache/test_snapshots tests/test_snapshots.nim

# ─────────────────────────────────────────────────────────────────────────────
# Clean
# ─────────────────────────────────────────────────────────────────────────────

# Clean all build artifacts
clean:
    rm -rf nimcache/ tests/test_* !tests/test_*.nim IsoNimCocoa.xcodeproj build/

# Clean only Nim build artifacts
clean-nim:
    rm -rf nimcache/
