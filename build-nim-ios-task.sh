#!/usr/bin/env bash
# build-nim-ios-task.sh — Compile the IsoNim task_app demo to an iOS
# ARM64 static library that the Stream app links against.
#
# Mirrors `build-nim-ios.sh` for the branded scene but builds
# `task_app/main_ios.nim` (the M-EVP-14 iOS port of the seeded
# task_app demo) and emits `build/libtask_app_ios.a` exposing the
# `isonim_task_start` C-ABI entry point.
#
# Why a separate script: `build-nim-ios.sh` is the load-bearing path
# for the legacy Branded scheme and adding `--path:../isonim-examples`
# + the seeded composition root to that script would risk regressing
# it. The two libs co-exist; the Stream app's `OTHER_LDFLAGS` lists
# both.
#
# IMPORTANT: This script uses /usr/bin/ tools explicitly to bypass
# Nix wrappers that don't support iOS cross-compilation.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Find nim if not in PATH.
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

NIM_CACHE="nimcache/ios-task"
OUT_DIR="build"
LIB_NAME="libtask_app_ios.a"

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
  echo "Check that Xcode is installed at $XCODE_DIR"
  exit 1
fi

CLANG="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
CLANGPP="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
AR="/usr/bin/ar"

echo "==> Target: $TARGET ($CLANG_TARGET)"
echo "    SDK: $SDK"
echo "    Clang: $CLANG"

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# Step 1: Nim -> C
# ---------------------------------------------------------------------------
echo "==> Compiling Nim (task_app/main_ios.nim) to C..."

# Path layout: sibling repos under ~/metacraft/.
# The composition root is `task_app/main_ios.nim` in isonim-examples;
# it pulls in `isonim_cocoa/uikit_renderer` from our own src tree.
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
  ../isonim-examples/task_app/main_ios.nim

echo "==> Nim -> C done."

# ---------------------------------------------------------------------------
# Step 2: Parse JSON manifest and compile each file with iOS SDK clang
# ---------------------------------------------------------------------------
echo "==> Compiling C/C++ for iOS ($CLANG_TARGET)..."

JSON="$NIM_CACHE/libmain_ios.json"

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

# ---------------------------------------------------------------------------
# Step 3: Archive into .a
# ---------------------------------------------------------------------------
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
echo "==> Checking for isonim_task_start symbol:"
nm "$OUT_DIR/$LIB_NAME" 2>/dev/null | grep -i "isonim_task_start" || echo "    WARNING: isonim_task_start not found"
