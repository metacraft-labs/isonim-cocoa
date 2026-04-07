## Tests for visual snapshot infrastructure.

import std/[os, strutils]
import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/renderer
import isonim_cocoa/testing/snapshots

# Use a temp directory for test golden files
let testGoldenDir = getTempDir() / "isonim_cocoa_snapshot_test"
goldenDir = testGoldenDir

suite "Snapshot - PNG Capture":
  setup:
    createDir(testGoldenDir)

  teardown:
    removeDir(testGoldenDir)

  test "capture NSView produces non-empty PNG":
    let view = allocInit("NSView")
    setWantsLayer(view)
    let png = captureViewToPng(view, 100, 50)
    check png.len > 0
    # PNG magic bytes: 0x89 P N G
    check png[0] == 0x89'u8
    check png[1] == 0x50'u8  # 'P'
    check png[2] == 0x4E'u8  # 'N'
    check png[3] == 0x47'u8  # 'G'
    release(view)

  test "capture NSTextField with text":
    let label = newNSLabel("Hello Snapshot")
    let png = captureViewToPng(Id(label), 200, 30)
    check png.len > 0
    check png[0] == 0x89'u8
    release(Id(label))

  test "capture NSButton":
    let btn = newNSButton("Click Me")
    let png = captureViewToPng(Id(btn), 150, 40)
    check png.len > 0
    check png[0] == 0x89'u8
    release(Id(btn))

suite "Snapshot - File I/O":
  setup:
    createDir(testGoldenDir)

  teardown:
    removeDir(testGoldenDir)

  test "save and load PNG round-trip":
    let data = @[0x89'u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    let path = testGoldenDir / "test.png"
    savePng(data, path)
    check fileExists(path)
    let loaded = loadPng(path)
    check loaded == data

  test "loadPng returns empty for missing file":
    let loaded = loadPng(testGoldenDir / "nonexistent.png")
    check loaded.len == 0

suite "Snapshot - Comparison":
  test "identical data matches":
    let data = @[1'u8, 2, 3, 4, 5]
    let result = comparePngBytes(data, data)
    check result.matched
    check result.diffPixels == 0

  test "different data fails":
    let a = @[1'u8, 2, 3, 4, 5]
    let b = @[1'u8, 2, 9, 4, 5]
    let result = comparePngBytes(a, b, tolerance = 0.0)
    check not result.matched
    check result.diffPixels == 1

  test "tolerance allows small differences":
    let a = @[1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    let b = @[1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 99]  # 1/10 = 10% diff
    let result = comparePngBytes(a, b, tolerance = 0.15)
    check result.matched

  test "tolerance rejects large differences":
    let a = @[1'u8, 2, 3, 4, 5]
    let b = @[9'u8, 9, 9, 9, 9]  # 100% different
    let result = comparePngBytes(a, b, tolerance = 0.01)
    check not result.matched

  test "empty expected = no golden file":
    let a = @[1'u8, 2, 3]
    let result = comparePngBytes(a, @[])
    check not result.matched
    check result.message.contains("No golden file")

suite "Snapshot - High-Level API":
  setup:
    createDir(testGoldenDir)

  teardown:
    removeDir(testGoldenDir)

  test "compareSnapshot creates golden on first run":
    let view = allocInit("NSView")
    setWantsLayer(view)
    let result = compareSnapshot(view, "first_run", 100, 50)
    check result.matched
    check result.message.contains("created")
    check fileExists(snapshotPath("first_run"))
    release(view)

  test "compareSnapshot matches on second run":
    let view = allocInit("NSView")
    setWantsLayer(view)
    # First run creates golden
    discard compareSnapshot(view, "second_run", 100, 50)
    # Second run compares
    let result = compareSnapshot(view, "second_run", 100, 50)
    check result.matched
    release(view)

  test "renderer element snapshot":
    resetTree()
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    r.setTextContent(btn, "Test Button")
    let result = compareSnapshot(Id(btn), "renderer_button", 150, 40)
    check result.matched  # first run = creates golden
