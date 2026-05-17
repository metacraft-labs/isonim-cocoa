#!/usr/bin/env bash
# build-nim-ios-settings.sh — Compile the IsoNim settings_app demo to
# an iOS ARM64 static library that the Stream app links against.
#
# Mirrors `build-nim-ios-task.sh` but builds
# `settings_app/main_ios_entry.nim` and emits
# `build/libsettings_app_ios.a` exposing the `isonim_settings_start`
# C-ABI entry point.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

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

NIM_CACHE="nimcache/ios-settings"
OUT_DIR="build"
LIB_NAME="libsettings_app_ios.a"

TARGET="${1:-device}"

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

if [ -L "$SDK" ]; then
  SDK=$(cd "$(dirname "$SDK")" && cd "$(readlink "$SDK")" && pwd)
elif [ ! -d "$SDK" ]; then
  SDK_DIR="$(dirname "$SDK")"
  SDK=$(ls -d "$SDK_DIR"/*.sdk 2>/dev/null | head -1)
fi

if [ ! -d "$SDK" ]; then
  echo "Error: iOS SDK not found at $SDK"
  exit 1
fi

CLANG="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
CLANGPP="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
AR="/usr/bin/ar"

echo "==> Target: $TARGET ($CLANG_TARGET)"
echo "    SDK: $SDK"
echo "    Clang: $CLANG"

mkdir -p "$OUT_DIR"

echo "==> Compiling Nim (settings_app/main_ios_entry.nim) to C..."

nim c \
  --compileOnly \
  --app:staticlib \
  --noMain \
  --nimcache:"$NIM_CACHE" \
  --os:macosx \
  --cpu:arm64 \
  --mm:orc \
  -d:ios \
  -d:release \
  --opt:size \
  --passC:"-DIOS_TARGET" \
  --path:"src" \
  --path:"../isonim/src" \
  --path:"../isonim-examples" \
  --path:"../isonim-render-serve/src" \
  --path:"../nim-everywhere/src" \
  ../isonim-examples/settings_app/main_ios_entry.nim

echo "==> Nim -> C done."

echo "==> Compiling C/C++ for iOS ($CLANG_TARGET)..."

JSON="$NIM_CACHE/libmain_ios_entry.json"

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

    if src.endswith('.cpp'):
        compiler = clangpp
    else:
        compiler = clang

    parts = cmd.split()
    out_file = None
    for i, p in enumerate(parts):
        if p == '-o' and i + 1 < len(parts):
            out_file = parts[i + 1]
            break

    if not out_file:
        continue

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

echo "==> Archiving..."

OBJ_FILES=$(find "$NIM_CACHE" -name "*.o" | sort)
OBJ_COUNT=$(echo "$OBJ_FILES" | wc -l | tr -d ' ')

if [ "$OBJ_COUNT" -eq 0 ]; then
  echo "Error: No .o files found in $NIM_CACHE"
  exit 1
fi

$AR rcs "$OUT_DIR/$LIB_NAME" $OBJ_FILES

echo "==> Built: $OUT_DIR/$LIB_NAME ($OBJ_COUNT object files)"
file "$OUT_DIR/$LIB_NAME"
echo "==> Checking for isonim_settings_start symbol:"
nm "$OUT_DIR/$LIB_NAME" 2>/dev/null | grep -i "isonim_settings_start" || echo "    WARNING: isonim_settings_start not found"
