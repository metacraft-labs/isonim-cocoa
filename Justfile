# IsoNim-Cocoa — Apple Platform Renderer

set shell := ["bash", "-euo", "pipefail", "-c"]

# Verify dev environment prerequisites
verify-env:
    #!/usr/bin/env bash
    set -e
    echo "Nim:        $(nim --version | head -1)"
    echo "Xcode:      $(xcodebuild -version 2>/dev/null | head -1 || echo 'NOT FOUND — install from App Store')"
    echo "xcrun:      $(xcrun --version 2>/dev/null || echo 'NOT FOUND — run xcode-select --install')"
    echo "clang:      $(clang --version 2>/dev/null | head -1)"
    echo "macOS SDK:  $(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo 'NOT FOUND')"
    echo "iOS SDK:    $(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || echo 'NOT FOUND')"
    echo "Simulators: $(xcrun simctl list devices available 2>/dev/null | grep -c 'iPhone' || echo '0') iPhone simulators available"
    echo "Testing objc_msgSend availability..."
    echo 'proc objc_getClass(name: cstring): pointer {.importc, header: "<objc/runtime.h>".}' > /tmp/test_objc.nim
    echo 'discard objc_getClass("NSObject")' >> /tmp/test_objc.nim
    nim c -r /tmp/test_objc.nim 2>/dev/null && echo "ObjC runtime: OK" || echo "ObjC runtime: FAILED"

# Run ObjC runtime tests (M0)
test-objc:
    nim c -r --nimcache:nimcache/test_objc_runtime tests/test_objc_runtime.nim

# Run renderer tests
test:
    nim c -r --nimcache:nimcache/test_renderer tests/test_renderer.nim

# Run cross-renderer tests (requires isonim core as sibling)
test-cross:
    nim c -r --path:../isonim/src --nimcache:nimcache/test_cross_renderer tests/test_cross_renderer.nim

# Run all tests
test-all: test-objc test test-cross

# Clean build artifacts
clean:
    rm -rf nimcache/ tests/test_objc_runtime tests/test_renderer tests/test_cross_renderer
