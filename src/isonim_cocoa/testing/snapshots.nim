## Visual snapshot testing — render NSViews to PNG and compare against golden files.
##
## Captures the rendered output of an NSView hierarchy to a PNG bitmap
## without requiring a window or event loop. Compares against stored
## golden files with configurable per-pixel tolerance.

import std/[os, strutils, math]
import isonim_cocoa/objc_runtime

{.passL: "-framework AppKit".}

# Compile the ObjC helper that does the actual bitmap capture
{.compile: currentSourcePath()[0..^(len("snapshots.nim") + 1)] & "snapshot_helper.m".}

proc nim_capture_view_png(view: Id; width, height: cint;
                           outBuf: ptr pointer): clong
  {.importc, cdecl.}
  ## Captures `view` once. On success returns the PNG's length and stores a
  ## `malloc`ed copy of it in `outBuf`, which the caller must `free`. On
  ## failure returns 0 and stores nil.

proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}

# Default directory for golden snapshot files
var goldenDir* = "tests/golden"

# Where `compareSnapshot` writes the captured PNG when it does not match its
# golden file, as `<actualDir>/<name>.png`. CI uploads this directory when a
# job fails, so a mismatch on another Mac can be inspected without access to
# that host. Relative to the working directory, like `goldenDir`; the
# Justfile recipes run from the repository root, where `build/` is ignored.
var actualDir* = "build/snapshot-actual"

type
  SnapshotResult* = object
    matched*: bool
    diffPixels*: int
    totalPixels*: int
    diffPercent*: float64
    message*: string

# ---------------------------------------------------------------------------
# Bitmap capture
# ---------------------------------------------------------------------------

proc captureViewToPng*(view: Id; width, height: int): seq[byte] =
  ## Render an NSView to a PNG byte sequence. No window needed. Returns an
  ## empty sequence when the capture fails.
  ##
  ## The view is captured exactly once and the PNG is copied whole. (An
  ## earlier version captured twice, once to learn the length and once to
  ## fill the buffer, and ignored the second length, so two captures of
  ## different sizes would have returned a truncated or padded PNG.)
  var png: pointer = nil
  let len = nim_capture_view_png(view, cint(width), cint(height), addr png)
  if len <= 0 or png == nil:
    if png != nil: cFree(png)
    return @[]
  try:
    result = newSeq[byte](len)
    copyMem(addr result[0], png, len)
  finally:
    cFree(png)

proc captureViewToPng*(view: Id): seq[byte] =
  ## Capture using default 200x100 size.
  captureViewToPng(view, 200, 100)

# ---------------------------------------------------------------------------
# PNG file I/O
# ---------------------------------------------------------------------------

proc savePng*(data: seq[byte]; path: string) =
  createDir(parentDir(path))
  let f = open(path, fmWrite)
  if data.len > 0:
    discard f.writeBytes(data, 0, data.len)
  f.close()

proc loadPng*(path: string): seq[byte] =
  if not fileExists(path):
    return @[]
  let f = open(path, fmRead)
  let size = f.getFileSize()
  result = newSeq[byte](size)
  if size > 0:
    discard f.readBytes(result, 0, int(size))
  f.close()

# ---------------------------------------------------------------------------
# Pixel comparison
# ---------------------------------------------------------------------------

proc comparePngBytes*(actual, expected: seq[byte];
                       tolerance: float64 = 0.0): SnapshotResult =
  if expected.len == 0:
    return SnapshotResult(
      matched: false, message: "No golden file found (first run?)")
  if actual.len == 0:
    return SnapshotResult(
      matched: false, message: "Failed to capture snapshot")

  if actual == expected:
    return SnapshotResult(matched: true, totalPixels: actual.len,
                           message: "Exact match")

  let minLen = min(actual.len, expected.len)
  var diffBytes = abs(actual.len - expected.len)
  for i in 0..<minLen:
    if actual[i] != expected[i]:
      inc diffBytes

  let total = max(actual.len, expected.len)
  let diffPct = if total > 0: diffBytes.float64 / total.float64 else: 0.0

  if diffPct <= tolerance:
    SnapshotResult(matched: true, diffPixels: diffBytes, totalPixels: total,
                    diffPercent: diffPct,
                    message: "Within tolerance (" & formatFloat(diffPct * 100, ffDecimal, 2) & "%)")
  else:
    SnapshotResult(matched: false, diffPixels: diffBytes, totalPixels: total,
                    diffPercent: diffPct,
                    message: "Diff " & formatFloat(diffPct * 100, ffDecimal, 2) &
                             "% exceeds tolerance " & formatFloat(tolerance * 100, ffDecimal, 2) & "%")

# ---------------------------------------------------------------------------
# High-level API
# ---------------------------------------------------------------------------

proc snapshotPath*(name: string): string =
  goldenDir / name & ".png"

proc actualPath*(name: string): string =
  ## Where a mismatching capture of snapshot `name` is written.
  actualDir / name & ".png"

proc compareSnapshot*(view: Id; name: string;
                       width: int = 200; height: int = 100;
                       tolerance: float64 = 0.0): SnapshotResult =
  ## Capture `view` and compare it with the golden file `name`. A missing
  ## golden is created and counts as a match. On a mismatch the capture is
  ## also written to `actualPath(name)` and the message names both files;
  ## the comparison itself is unchanged.
  let actual = captureViewToPng(view, width, height)
  let path = snapshotPath(name)

  if not fileExists(path):
    savePng(actual, path)
    return SnapshotResult(matched: true,
      message: "Golden file created: " & path)

  let expected = loadPng(path)
  result = comparePngBytes(actual, expected, tolerance)
  if not result.matched and actual.len > 0:
    let saved = actualPath(name)
    savePng(actual, saved)
    result.message.add("\n  Golden: " & path & "\n  Actual: " & saved)

proc assertSnapshot*(view: Id; name: string;
                      width: int = 200; height: int = 100;
                      tolerance: float64 = 0.0) =
  let result = compareSnapshot(view, name, width, height, tolerance)
  if not result.matched:
    raise newException(AssertionDefect,
      "Snapshot mismatch for '" & name & "': " & result.message)
