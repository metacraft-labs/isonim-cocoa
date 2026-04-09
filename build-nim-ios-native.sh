#!/usr/bin/env bash
# build-nim-ios-native.sh — Compile Nim native-controls app to iOS ARM64 static library.
#
# Same as build-nim-ios.sh but adds -d:nativeControls and outputs libisonim_native.a.
#
# IMPORTANT: This script uses /usr/bin/ tools explicitly to bypass Nix wrappers
# that don't support iOS cross-compilation.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Find nim if not in PATH
if ! command -v nim &>/dev/null; then
  NIM_PATH=$(find /nix/store -maxdepth 3 -name nim \( -type f -o -type l \) \
    ! -path "*bootstrap*" ! -path "*unwrapped*" 2>/dev/null | head -1)
  if [ -n "$NIM_PATH" ]; then
    export PATH="$(dirname "$NIM_PATH"):$PATH"
    echo "    Found nim: $NIM_PATH"
  else
    echo "Error: nim not found. Install via nix or set PATH." >&2
    exit 1
  fi
fi

NIM_CACHE="nimcache/ios-native"
OUT_DIR="build"
LIB_NAME="libisonim_native.a"

# Parse arguments
TARGET="${1:-device}"  # "device" or "sim"

# Directly construct SDK path to bypass Nix xcrun wrappers
XCODE_DIR="/Applications/Xcode.app/Contents/Developer"

if [ "$TARGET" = "sim" ]; then
  SDK="$XCODE_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
  ARCH=$(uname -m)
  if [ "$ARCH" = "arm64" ]; then
    CLANG_TARGET="arm64-apple-ios17.0-simulator"
  else
    CLANG_TARGET="x86_64-apple-ios17.0-simulator"
  fi
else
  SDK="$XCODE_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
  CLANG_TARGET="arm64-apple-ios17.0"
fi

# Resolve symlinks to get the real SDK path
if [ -L "$SDK" ]; then
  SDK=$(cd "$(dirname "$SDK")" && cd "$(readlink "$SDK")" && pwd)
elif [ ! -d "$SDK" ]; then
  # Try finding versioned SDK
  SDK_DIR="$(dirname "$SDK")"
  SDK=$(ls -d "$SDK_DIR"/*.sdk 2>/dev/null | head -1)
fi

if [ ! -d "$SDK" ]; then
  echo "Error: iOS SDK not found at $SDK"
  echo "Check that Xcode is installed at $XCODE_DIR"
  exit 1
fi

# Use Xcode's own clang, not Nix's
CLANG="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
CLANGPP="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
AR="/usr/bin/ar"

echo "==> Target: $TARGET ($CLANG_TARGET)"
echo "    SDK: $SDK"
echo "    Clang: $CLANG"

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# Step 1: Nim -> C/C++
# ---------------------------------------------------------------------------
echo "==> Compiling Nim to C (native controls)..."

nim c \
  --compileOnly \
  --app:staticlib \
  --noMain \
  --nimcache:"$NIM_CACHE" \
  --os:macosx \
  --cpu:arm64 \
  -d:ios \
  -d:nativeControls \
  -d:release \
  --opt:size \
  --passC:"-DIOS_TARGET" \
  src/isonim_cocoa/app_entry_native.nim

echo "==> Nim -> C done."

# ---------------------------------------------------------------------------
# Step 2: Parse JSON manifest and compile each file with iOS SDK clang
# ---------------------------------------------------------------------------
echo "==> Compiling C/C++ for iOS ($CLANG_TARGET)..."

JSON="$NIM_CACHE/libapp_entry_native.json"

# Use python3 to extract compile commands and generate a shell script
python3 - "$JSON" "$CLANG_TARGET" "$SDK" "$CLANG" "$CLANGPP" <<'PYEOF' > "$NIM_CACHE/compile_ios.sh"
import json, sys, os, shlex

json_path = sys.argv[1]
clang_target = sys.argv[2]
sdk = sys.argv[3]
clang = sys.argv[4]
clangpp = sys.argv[5]

with open(json_path) as f:
    data = json.load(f)

print("#!/bin/bash")
print("set -e")

for entry in data.get('compile', []):
    src = entry[0]
    cmd = entry[1]

    # Determine compiler
    if src.endswith('.cpp'):
        compiler = clangpp
    else:
        compiler = clang

    # Extract the output file (-o flag)
    parts = cmd.split()
    out_file = None
    for i, p in enumerate(parts):
        if p == '-o' and i + 1 < len(parts):
            out_file = parts[i + 1]
            break

    if not out_file:
        continue

    # Collect relevant flags (skip the original compiler and -c)
    flags = []
    for p in parts:
        if p.startswith('-I') or p.startswith('-D') or p.startswith('-std=') or \
           p in ('-funsigned-char', '-w', '-fPIC', '-Os', '-O2', '-pthread') or \
           p.startswith('-ferror-limit'):
            flags.append(p)

    flag_str = ' '.join(flags)
    src_q = shlex.quote(src)
    out_q = shlex.quote(out_file)
    print(f'echo "    Compiling: {os.path.basename(src)}"')
    print(f'{shlex.quote(compiler)} -c -target {clang_target} -isysroot {shlex.quote(sdk)} {flag_str} {src_q} -o {out_q}')

PYEOF

bash "$NIM_CACHE/compile_ios.sh"

echo "==> C/C++ compilation done."

# ---------------------------------------------------------------------------
# Step 3: Archive into .a
# ---------------------------------------------------------------------------
echo "==> Archiving..."

# Collect all .o files from the nimcache
OBJ_FILES=$(find "$NIM_CACHE" -name "*.o" | sort)
OBJ_COUNT=$(echo "$OBJ_FILES" | wc -l | tr -d ' ')

if [ "$OBJ_COUNT" -eq 0 ]; then
  echo "Error: No .o files found in $NIM_CACHE"
  exit 1
fi

$AR rcs "$OUT_DIR/$LIB_NAME" $OBJ_FILES

echo "==> Built: $OUT_DIR/$LIB_NAME ($OBJ_COUNT object files)"
file "$OUT_DIR/$LIB_NAME"
echo "==> Checking for isonim_native_start symbol:"
nm "$OUT_DIR/$LIB_NAME" 2>/dev/null | grep -i "isonim_native_start" || echo "    WARNING: isonim_native_start not found"
