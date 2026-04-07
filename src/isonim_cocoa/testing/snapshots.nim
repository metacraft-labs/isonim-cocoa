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
                           buf: pointer; bufLen: clong): clong
  {.importc, cdecl.}

# Default directory for golden snapshot files
var goldenDir* = "tests/golden"

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
  ## Render an NSView to a PNG byte sequence. No window needed.
  let needed = nim_capture_view_png(view, cint(width), cint(height), nil, 0)
  if needed <= 0:
    return @[]
  result = newSeq[byte](needed)
  discard nim_capture_view_png(view, cint(width), cint(height),
                                addr result[0], needed)

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

proc compareSnapshot*(view: Id; name: string;
                       width: int = 200; height: int = 100;
                       tolerance: float64 = 0.0): SnapshotResult =
  let actual = captureViewToPng(view, width, height)
  let path = snapshotPath(name)

  if not fileExists(path):
    savePng(actual, path)
    return SnapshotResult(matched: true,
      message: "Golden file created: " & path)

  let expected = loadPng(path)
  comparePngBytes(actual, expected, tolerance)

proc assertSnapshot*(view: Id; name: string;
                      width: int = 200; height: int = 100;
                      tolerance: float64 = 0.0) =
  let result = compareSnapshot(view, name, width, height, tolerance)
  if not result.matched:
    let actual = captureViewToPng(view, width, height)
    let actualPath = snapshotPath(name & ".actual")
    savePng(actual, actualPath)
    raise newException(AssertionDefect,
      "Snapshot mismatch for '" & name & "': " & result.message &
      "\n  Golden: " & snapshotPath(name) &
      "\n  Actual: " & actualPath)
