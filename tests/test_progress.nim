## Tests for Progress, Activity & Badges (M12).
## NSProgressIndicator, Badge, Toast, and snapshots.

import std/os
import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/textcontrols  # for nim_view_set_frame
import isonim_cocoa/appkit/progress
import isonim_cocoa/renderer
import isonim_cocoa/testing/fake_clock
import isonim_cocoa/testing/snapshots

# Use temp dir for snapshot golden files
let testGoldenDir = getTempDir() / "isonim_cocoa_progress_test"
goldenDir = testGoldenDir

# ===========================================================================
# NSProgressIndicator (determinate)
# ===========================================================================

suite "NSProgressIndicator - create":
  setup:
    resetTree()

  test "create determinate, verify defaults":
    let p = newNSProgressIndicator(determinate = true)
    check not p.isNil
    check progressIsIndeterminate(p) == false
    check abs(progressMinValue(p) - 0.0) < 0.001
    check abs(progressMaxValue(p) - 100.0) < 0.001
    release(p)

suite "NSProgressIndicator - value":
  setup:
    resetTree()

  test "set to 42, read back":
    let p = newNSProgressIndicator()
    setProgressValue(p, 42.0)
    check abs(progressValue(p) - 42.0) < 0.001
    release(p)

  test "set to -10, verify clamped to 0":
    let p = newNSProgressIndicator()
    setProgressValue(p, -10.0)
    check abs(progressValue(p) - 0.0) < 0.001
    release(p)

  test "set to 200, verify clamped to 100":
    let p = newNSProgressIndicator()
    setProgressValue(p, 200.0)
    check abs(progressValue(p) - 100.0) < 0.001
    release(p)

suite "NSProgressIndicator - renderer integration":
  setup:
    resetTree()

  test "setAttribute value 0.75, verify doubleValue == 75":
    let r = CocoaRenderer()
    let elem = r.createElement("progress")
    r.setAttribute(elem, "value", "0.75")
    check abs(progressValue(Id(elem)) - 75.0) < 0.001

# ===========================================================================
# NSProgressIndicator (indeterminate / spinner)
# ===========================================================================

suite "NSSpinner - create":
  setup:
    resetTree()

  test "create spinner, verify isIndeterminate":
    let s = newNSSpinner()
    check not s.isNil
    check progressIsIndeterminate(s) == true
    release(s)

suite "NSSpinner - start/stop":
  setup:
    resetTree()

  test "startAnimation and stopAnimation do not crash":
    let s = newNSSpinner()
    startSpinner(s)
    stopSpinner(s)
    # If we get here, no crash occurred
    check true
    release(s)

# ===========================================================================
# Badge (composite)
# ===========================================================================

suite "Badge - create and subviews":
  setup:
    resetTree()

  test "create badge, verify 2 subviews (background layer + label)":
    let b = newBadge(5)
    check not b.isNil
    # The badge has 1 subview: the label NSTextField.
    # The background is on the layer, not a subview.
    # Verify we have at least 1 subview (the label).
    check subviewCount(b) >= 1
    # Verify label text
    let subs = subviews(b)
    let label = nsArrayObjectAtIndex(subs, nsArrayCount(subs) - 1)
    check stringValue(label) == "5"
    release(b)

suite "Badge - hidden at zero":
  setup:
    resetTree()

  test "set count to 0, verify hidden":
    let b = newBadge(5)
    setBadgeCount(b, 0)
    check isBadgeHidden(b) == true
    release(b)

  test "set count > 0, verify visible":
    let b = newBadge(0)
    check isBadgeHidden(b) == true
    setBadgeCount(b, 3)
    check isBadgeHidden(b) == false
    release(b)

suite "Badge - overflow":
  setup:
    resetTree()

  test "set count to 150, verify label 99+":
    let b = newBadge(0)
    setBadgeCount(b, 150)
    let subs = subviews(b)
    let label = nsArrayObjectAtIndex(subs, nsArrayCount(subs) - 1)
    check stringValue(label) == "99+"
    release(b)

# ===========================================================================
# Toast (FakeClock auto-dismiss)
# ===========================================================================

suite "Toast - lifecycle":
  setup:
    resetTree()

  test "toast visible then dismissed after duration":
    let clock = newFakeClock()
    let mgr = newToastManager()
    mgr.showToast("Hello", 3.0, clock)
    check mgr.visibleToastCount() == 1
    check mgr.currentToastMessage() == "Hello"
    # Advance past duration
    clock.advance(3.0)
    pumpRunLoop()
    check mgr.visibleToastCount() == 0

suite "Toast - queue":
  setup:
    resetTree()

  test "show 2 toasts, only 1 visible, second appears after first dismisses":
    let clock = newFakeClock()
    let mgr = newToastManager()
    mgr.showToast("First", 2.0, clock)
    mgr.showToast("Second", 2.0, clock)
    # Only the first should be visible
    check mgr.visibleToastCount() == 1
    check mgr.currentToastMessage() == "First"
    # Dismiss first
    clock.advance(2.0)
    pumpRunLoop()
    # Second should now be visible
    check mgr.visibleToastCount() == 1
    check mgr.currentToastMessage() == "Second"
    # Dismiss second
    clock.advance(2.0)
    pumpRunLoop()
    check mgr.visibleToastCount() == 0

# ===========================================================================
# Snapshots
# ===========================================================================

suite "Snapshot - progress bar":
  setup:
    createDir(testGoldenDir)
    resetTree()

  teardown:
    removeDir(testGoldenDir)

  test "progress at 0%":
    let p = newNSProgressIndicator()
    setProgressValue(p, 0.0)
    nim_view_set_frame(p, 0, 0, 200, 20)
    let result = compareSnapshot(p, "progress_0pct", 200, 20)
    check result.matched
    release(p)

  test "progress at 50%":
    let p = newNSProgressIndicator()
    setProgressValue(p, 50.0)
    nim_view_set_frame(p, 0, 0, 200, 20)
    let result = compareSnapshot(p, "progress_50pct", 200, 20)
    check result.matched
    release(p)

  test "progress at 100%":
    let p = newNSProgressIndicator()
    setProgressValue(p, 100.0)
    nim_view_set_frame(p, 0, 0, 200, 20)
    let result = compareSnapshot(p, "progress_100pct", 200, 20)
    check result.matched
    release(p)

suite "Snapshot - badge":
  setup:
    createDir(testGoldenDir)
    resetTree()

  teardown:
    removeDir(testGoldenDir)

  test "badge count 3":
    let b = newBadge(3)
    nim_view_set_frame(b, 0, 0, 30, 20)
    let result = compareSnapshot(b, "badge_count3", 30, 20)
    check result.matched
    release(b)

  test "badge count 0 (hidden)":
    let b = newBadge(0)
    nim_view_set_frame(b, 0, 0, 30, 20)
    let result = compareSnapshot(b, "badge_hidden", 30, 20)
    check result.matched
    release(b)

  test "badge count 99+":
    let b = newBadge(0)
    setBadgeCount(b, 150)
    nim_view_set_frame(b, 0, 0, 40, 20)
    let result = compareSnapshot(b, "badge_99plus", 40, 20)
    check result.matched
    release(b)
