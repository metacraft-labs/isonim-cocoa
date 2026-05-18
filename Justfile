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

# Render all branded scenario snapshots (creates/compares golden files)
test-scenarios:
    nim c -r --nimcache:nimcache/test_scenarios tests/test_scenario_snapshots.nim

# Run all headless Nim tests
test: test-objc test-views test-renderer test-infra

# Run all tests including cross-renderer and scenarios
test-all: test test-cross test-scenarios

# ─────────────────────────────────────────────────────────────────────────────
# Task-app demo (canonical home in isonim-examples since EX-M5)
# ─────────────────────────────────────────────────────────────────────────────

# Build the canonical task-app demo (lives in isonim-examples since
# EX-M5; this recipe just defers to that repo's composition root).
# Cocoa needs no Rust shim — AppKit is linked directly via the
# `{.passL: "-framework AppKit".}` pragmas inside isonim_cocoa.
demo-build:
    nim c --path:../isonim/src --path:../isonim-examples --path:../isonim-cocoa/src --nimcache:nimcache/demo ../isonim-examples/task_app/main_cocoa.nim

# Run the canonical task-app demo (headless mode). Sources live in
# `isonim-examples/task_app/` per the EX-M5 migration.
demo-run:
    nim c -r --path:../isonim/src --path:../isonim-examples --path:../isonim-cocoa/src --nimcache:nimcache/demo ../isonim-examples/task_app/main_cocoa.nim

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

# ─────────────────────────────────────────────────────────────────────────────
# Nim static library (for branded variant)
# ─────────────────────────────────────────────────────────────────────────────

# Build Nim branded app as static library for iOS device (ARM64)
build-nim-ios:
    ./build-nim-ios.sh device

# Build Nim branded app as static library for iOS Simulator
build-nim-sim:
    ./build-nim-ios.sh sim

# Deploy branded (IsoNim theme) app to iPhone
deploy-branded: build-nim-ios xcode-generate
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

# ─────────────────────────────────────────────────────────────────────────────
# Stream variant — IsoNim editor pbIos backend device side
# ─────────────────────────────────────────────────────────────────────────────
#
# The Stream scheme builds a sibling iOS app that boots the Nim branded
# UI *and* publishes an F-packet TCP listener on port 8200, advertised
# over Bonjour as `_isonim-stream._tcp.`. The editor's pbIos launcher
# (host side, work in progress) discovers and connects to it.
#
# Pipeline: build-nim-ios (libisonim_app.a) → xcodegen → xcodebuild
# Stream → devicectl install / launch.

# Stream-specific iPhone identifier (iPhone 14, "iPhone").
# Override on the CLI: `just stream-device=DC8C... deploy-stream`.
stream-device := "688D4B24-9EDF-51E3-B343-F351DE814897"
stream-bundle := "com.metacraft.isonim.cocoa.stream"
stream-port := "8200"

# M-EVP-14 Wave W-4: build the SettingsVM iOS static lib. The
# Stream app's FrameStreamingViewController dispatches into
# `isonim_settings_start` whenever the screenshot tool sets
# `ISONIM_DEMO=settings`; without this recipe the Stream-app
# install path silently ships a stale settings binary and the
# in-editor capture continues to display the previous build's
# tree (round-15 reviewer flagged the missing description tier as
# the symptom — Wave U-5's source-side restoration was correct,
# but `libsettings_app_ios.a` was last rebuilt before the commit
# landed). Wraps the existing `build-nim-ios-settings.sh` script
# so `deploy-stream` always relinks against the freshly built lib.
build-nim-ios-settings:
    ./build-nim-ios-settings.sh device

# M-EVP-14 Wave W-4 sibling: build the TaskAppVM iOS static lib.
build-nim-ios-task:
    ./build-nim-ios-task.sh device

# Build the Stream variant for device (ARM64, signed). Mirrors
# `deploy-branded`'s prelude: Nim → C → static lib → xcodebuild.
#
# Wave W-4 fix: build all three Nim libraries the Stream app's
# view controller may dispatch into (legacy branded, task, settings)
# before xcodebuild so the linker always sees up-to-date object code.
build-stream: build-nim-ios build-nim-ios-task build-nim-ios-settings xcode-generate
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/bin/env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      /usr/bin/xcodebuild build \
        -project IsoNimCocoa.xcodeproj \
        -target IsoNim-Stream \
        -configuration Debug \
        DEVELOPMENT_TEAM=GK3D7BH967 \
        -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates 2>&1 | tail -3
    APP=$(find build -name "IsoNim Stream.app" -path "*/Debug-iphoneos/*" | head -1)
    echo "Built: $APP"

# Install + launch Stream on the connected iPhone via xcrun devicectl
# (the modern replacement for ios-deploy; works with iOS 17+).
deploy-stream: build-stream
    #!/usr/bin/env bash
    set -euo pipefail
    APP=$(find build -name "IsoNim Stream.app" -path "*/Debug-iphoneos/*" | head -1)
    if [ -z "$APP" ]; then
      echo "Error: IsoNim Stream.app not found." >&2
      exit 1
    fi
    DEVICE_ID="{{stream-device}}"
    echo "Installing $APP onto $DEVICE_ID..."
    xcrun devicectl device install app \
      --device "$DEVICE_ID" "$APP" 2>&1 | tail -5
    echo "Launching {{stream-bundle}}..."
    if ! xcrun devicectl device process launch \
        --device "$DEVICE_ID" --terminate-existing \
        {{stream-bundle}} 2>&1 | tail -5; then
      echo "" >&2
      echo "NOTE: launch denied — this is usually the per-bundle trust" >&2
      echo "prompt for a NEW bundle ID. On the iPhone open" >&2
      echo "  Settings > General > VPN & Device Management" >&2
      echo "and trust the developer profile for team GK3D7BH967, then" >&2
      echo "tap the IsoNim Stream icon on the home screen once." >&2
      exit 1
    fi
    echo "Stream app deployed and launched on iPhone."
    echo "Look up the device's IP and try: just test-stream-frame ip=<ip>"

# Smoke test: open TCP to the device on port 8200, read ONE F-packet's
# header, dump width/height/length. Caller supplies the device IP via
# `ip=...` (default `iPhone.local` which works if the Mac and the iPhone
# share the same Wi-Fi). The test exits non-zero if the packet doesn't
# decode cleanly.
test-stream-frame ip="iPhone.local":
    #!/usr/bin/env bash
    set -euo pipefail
    PYTHON=$(command -v python3 || command -v python)
    if [ -z "$PYTHON" ]; then
      echo "Error: python3 not available; needed to decode the F header." >&2
      exit 1
    fi
    HOST="{{ip}}"
    PORT="{{stream-port}}"
    echo "Connecting to $HOST:$PORT..."
    # The script body lives in a temp file because Just normalizes recipe
    # indentation, which would otherwise break Python's significant
    # whitespace inside a HEREDOC.
    SCRIPT=$(mktemp /tmp/test-stream-frame.XXXXXX.py)
    trap 'rm -f "$SCRIPT"' EXIT
    cat >"$SCRIPT" <<'PYEOF'
    import socket, struct, sys
    host, port = sys.argv[1], int(sys.argv[2])
    sock = socket.create_connection((host, port), timeout=15)
    sock.settimeout(15)
    def recv_exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise SystemExit(f"socket closed after {len(buf)}/{n} bytes")
            buf += chunk
        return buf
    hdr = recv_exact(14)
    if hdr[0:1] != b'F':
        raise SystemExit(f"bad tag: {hdr[0:1]!r} (expected b'F')")
    flags = hdr[1]
    width, height, length = struct.unpack('<III', hdr[2:14])
    expected = width * height * 4
    print(f"tag       = 'F'")
    print(f"flags     = {flags:#04x}")
    print(f"width     = {width}")
    print(f"height    = {height}")
    print(f"length    = {length}")
    print(f"w*h*4     = {expected}")
    if flags != 0:
        raise SystemExit(f"unexpected flags {flags:#04x}; expected 0x00")
    if length != expected:
        raise SystemExit(f"length mismatch: header={length} w*h*4={expected}")
    payload = recv_exact(length)
    if length >= 4:
        r, g, b, a = payload[0], payload[1], payload[2], payload[3]
        print(f"px[0,0]   = R={r} G={g} B={b} A={a}")
    print("PASS: first F-packet matches header invariants.")
    PYEOF
    # Strip Just's leading indentation (4 spaces) so Python sees a clean
    # top-level script.
    sed -i.bak 's/^    //' "$SCRIPT"
    "$PYTHON" "$SCRIPT" "$HOST" "$PORT"

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
