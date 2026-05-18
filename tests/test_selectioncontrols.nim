## Tests for NSSwitch, NSSlider, NSPopUpButton, NSSegmentedControl,
## NSDatePicker, NSStepper (M9).

import std/os
import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/selectioncontrols
import isonim_cocoa/appkit/textcontrols
import isonim_cocoa/renderer
import isonim_cocoa/testing/snapshots

# Use temp dir for snapshot golden files
let testGoldenDir = getTempDir() / "isonim_cocoa_selcontrols_test"
goldenDir = testGoldenDir

# ===========================================================================
# NSSwitch
# ===========================================================================

suite "NSSwitch - state management":
  test "create, set state on, read back":
    let sw = newNSSwitch()
    check not sw.isNil
    setSwitchState(sw, true)
    check switchState(sw) == true
    release(sw)

  test "toggle off, read back":
    let sw = newNSSwitch()
    setSwitchState(sw, true)
    check switchState(sw) == true
    setSwitchState(sw, false)
    check switchState(sw) == false
    release(sw)

  test "event: change event fires via renderer":
    resetTree()
    let r = CocoaRenderer()
    let elem = r.createElement("switch")
    var fired = false
    r.addEventListener(elem, "change", proc() = fired = true)
    r.fireEvent(elem, "change")
    check fired

# ===========================================================================
# NSSlider
# ===========================================================================

suite "NSSlider - value and range":
  test "create with range, set value, read back":
    let sl = newNSSlider(0.0, 100.0, 42.5)
    check not sl.isNil
    check abs(sliderValue(sl) - 42.5) < 0.001
    release(sl)

  test "min/max enforcement - value clamped":
    let sl = newNSSlider(0.0, 100.0, 50.0)
    setSliderValue(sl, 200.0)
    # NSSlider clamps to max
    check sliderValue(sl) <= 100.0
    setSliderValue(sl, -50.0)
    # NSSlider clamps to min
    check sliderValue(sl) >= 0.0
    release(sl)

  test "min/max getters":
    let sl = newNSSlider(10.0, 90.0, 50.0)
    check abs(sliderMin(sl) - 10.0) < 0.001
    check abs(sliderMax(sl) - 90.0) < 0.001
    release(sl)

  test "event: target-action fires":
    let sl = newNSSlider(0.0, 100.0, 50.0)
    var fired = false
    let cbId = registerCallback(proc() = fired = true)
    let target = newCallbackTarget(cbId)
    msgSendVoid(sl, sel("setTarget:"), target)
    msgSendVoid(sl, sel("setAction:"), Id(sel("callbackAction:")))
    # sendAction:to: triggers the action
    let action = sel("callbackAction:")
    discard msgSendBool(sl, sel("sendAction:to:"), action, target)
    check fired
    release(sl)

# ===========================================================================
# NSPopUpButton
# ===========================================================================

suite "NSPopUpButton - items and selection":
  test "create with items, verify count and selection":
    let btn = newNSPopUpButton(@["Apple", "Banana", "Cherry"])
    check popUpItemCount(btn) == 3
    # First item selected by default
    check popUpSelectedIndex(btn) == 0
    check popUpSelectedTitle(btn) == "Apple"
    # Select index 1
    popUpSelectIndex(btn, 1)
    check popUpSelectedIndex(btn) == 1
    check popUpSelectedTitle(btn) == "Banana"
    release(btn)

  test "event: target-action on selection":
    let btn = newNSPopUpButton(@["A", "B", "C"])
    var fired = false
    let cbId = registerCallback(proc() = fired = true)
    let target = newCallbackTarget(cbId)
    msgSendVoid(btn, sel("setTarget:"), target)
    msgSendVoid(btn, sel("setAction:"), Id(sel("callbackAction:")))
    let action = sel("callbackAction:")
    discard msgSendBool(btn, sel("sendAction:to:"), action, target)
    check fired
    release(btn)

  test "add items, verify count update":
    let btn = newNSPopUpButton(@["One"])
    check popUpItemCount(btn) == 1
    popUpAddItem(btn, "Two")
    popUpAddItem(btn, "Three")
    check popUpItemCount(btn) == 3
    release(btn)

# ===========================================================================
# NSSegmentedControl
# ===========================================================================

suite "NSSegmentedControl - segments":
  test "create with labels, verify round-trip":
    let sc = newNSSegmentedControl(@["Tab A", "Tab B", "Tab C"])
    check segmentCount(sc) == 3
    check segmentLabel(sc, 0) == "Tab A"
    check segmentLabel(sc, 1) == "Tab B"
    check segmentLabel(sc, 2) == "Tab C"
    release(sc)

  test "select segment, verify selectedSegment":
    let sc = newNSSegmentedControl(@["X", "Y", "Z"])
    segmentSelect(sc, 1)
    check segmentSelectedIndex(sc) == 1
    segmentSelect(sc, 2)
    check segmentSelectedIndex(sc) == 2
    release(sc)

  test "event: target-action on segment selection":
    let sc = newNSSegmentedControl(@["A", "B"])
    var fired = false
    let cbId = registerCallback(proc() = fired = true)
    let target = newCallbackTarget(cbId)
    msgSendVoid(sc, sel("setTarget:"), target)
    msgSendVoid(sc, sel("setAction:"), Id(sel("callbackAction:")))
    let action = sel("callbackAction:")
    discard msgSendBool(sc, sel("sendAction:to:"), action, target)
    check fired
    release(sc)

# ===========================================================================
# NSDatePicker
# ===========================================================================

suite "NSDatePicker - date values":
  test "create, set date, read back components":
    let dp = newNSDatePicker()
    check not dp.isNil
    let date = newNSDateFromComponents(2025, 6, 15)
    setDatePickerValue(dp, date)
    let readBack = datePickerValue(dp)
    let (y, m, d) = dateComponents(readBack)
    check y == 2025
    check m == 6
    check d == 15
    release(dp)

  test "min/max date constraints":
    let dp = newNSDatePicker()
    let minDate = newNSDateFromComponents(2024, 1, 1)
    let maxDate = newNSDateFromComponents(2026, 12, 31)
    setDatePickerMinDate(dp, minDate)
    setDatePickerMaxDate(dp, maxDate)
    # Verify the constraints are stored
    let readMin = datePickerMinDate(dp)
    let readMax = datePickerMaxDate(dp)
    check not readMin.isNil
    check not readMax.isNil
    let (minY, _, _) = dateComponents(readMin)
    let (maxY, _, _) = dateComponents(readMax)
    check minY == 2024
    check maxY == 2026
    release(dp)

# ===========================================================================
# NSStepper
# ===========================================================================

suite "NSStepper - value and increment":
  test "create with range and increment, set value, read back":
    let st = newNSStepper(0.0, 10.0, 4.0, 2.0)
    check not st.isNil
    check abs(stepperValue(st) - 4.0) < 0.001
    release(st)

  test "increment value is configured correctly":
    let st = newNSStepper(0.0, 10.0, 4.0, 2.0)
    # Verify the increment property is set to 2.0
    let increment = msgSendFloat(Id(st), sel("increment"))
    check abs(increment - 2.0) < 0.001
    # Simulate increment by directly setting value += increment
    let current = stepperValue(st)
    setStepperValue(st, current + increment)
    check abs(stepperValue(st) - 6.0) < 0.001
    release(st)

  test "value clamps to min/max":
    let st = newNSStepper(0.0, 10.0, 5.0, 1.0)
    setStepperValue(st, 15.0)
    check abs(stepperValue(st) - 10.0) < 0.001  # clamped to max
    setStepperValue(st, -5.0)
    check abs(stepperValue(st) - 0.0) < 0.001   # clamped to min
    release(st)

  test "wrapping behavior":
    let st = newNSStepper(0.0, 10.0, 0.0, 2.0)
    setStepperWraps(st, true)
    check stepperWraps(st) == true
    setStepperWraps(st, false)
    check stepperWraps(st) == false
    release(st)

# ===========================================================================
# Renderer integration
# ===========================================================================

suite "Renderer - selection controls":
  setup:
    resetTree()

  test "createElement switch creates a switch-tagged NSButton":
    # M-EVP-14 Wave V: ``<switch>`` re-routes to ekButton (NSButton)
    # so the layer-fill branch can paint the IsoNim brand indigo —
    # NSSwitch's ``setOnTintColor:`` is a no-op on macOS Sonoma so
    # the historical NSSwitch path can never reach the brand accent.
    let r = CocoaRenderer()
    let elem = r.createElement("switch")
    check not Id(elem).isNil
    # ``checked`` is now tracked via the attribute table on the
    # element (the layer fill flips between accent and muted-dark);
    # round-trip through getAttribute is the supported observation
    # point now that the underlying control is an NSButton.
    r.setAttribute(elem, "checked", "true")
    check r.getAttribute(elem, "checked") == "true"
    r.setAttribute(elem, "checked", "false")
    check r.getAttribute(elem, "checked") == "false"

  test "createElement toggle is alias for switch":
    let r = CocoaRenderer()
    let elem = r.createElement("toggle")
    check not Id(elem).isNil
    r.setAttribute(elem, "checked", "true")
    check r.getAttribute(elem, "checked") == "true"

  test "createElement slider creates NSSlider":
    let r = CocoaRenderer()
    let elem = r.createElement("slider")
    check not Id(elem).isNil
    r.setAttribute(elem, "value", "75.0")
    check abs(sliderValue(Id(elem)) - 75.0) < 0.001

  test "createElement range is alias for slider":
    let r = CocoaRenderer()
    let elem = r.createElement("range")
    check not Id(elem).isNil

  test "createElement select creates NSPopUpButton":
    let r = CocoaRenderer()
    let elem = r.createElement("select")
    check not Id(elem).isNil

  test "createElement segmented creates NSSegmentedControl":
    let r = CocoaRenderer()
    let elem = r.createElement("segmented")
    check not Id(elem).isNil

  test "createElement date-picker creates NSDatePicker":
    let r = CocoaRenderer()
    let elem = r.createElement("date-picker")
    check not Id(elem).isNil

  test "createElement stepper creates NSStepper":
    let r = CocoaRenderer()
    let elem = r.createElement("stepper")
    check not Id(elem).isNil
    r.setAttribute(elem, "value", "5.0")
    check abs(stepperValue(Id(elem)) - 5.0) < 0.001

  test "slider min/max via setAttribute":
    let r = CocoaRenderer()
    let elem = r.createElement("slider")
    r.setAttribute(elem, "min", "10.0")
    r.setAttribute(elem, "max", "200.0")
    check abs(sliderMin(Id(elem)) - 10.0) < 0.001
    check abs(sliderMax(Id(elem)) - 200.0) < 0.001

  test "select selectedIndex via setAttribute":
    let r = CocoaRenderer()
    let elem = r.createElement("select")
    popUpAddItem(Id(elem), "A")
    popUpAddItem(Id(elem), "B")
    popUpAddItem(Id(elem), "C")
    r.setAttribute(elem, "selectedIndex", "2")
    check popUpSelectedIndex(Id(elem)) == 2

# ===========================================================================
# Snapshots
# ===========================================================================

suite "Snapshot - selection controls default state":
  setup:
    createDir(testGoldenDir)
    resetTree()

  teardown:
    removeDir(testGoldenDir)

  test "switch default snapshot":
    let sw = newNSSwitch()
    nim_view_set_frame(sw, 0, 0, 50, 25)
    let result = compareSnapshot(sw, "switch_default", 50, 25)
    check result.matched
    release(sw)

  test "slider default snapshot":
    let sl = newNSSlider(0.0, 100.0, 50.0)
    nim_view_set_frame(sl, 0, 0, 200, 25)
    let result = compareSnapshot(sl, "slider_default", 200, 25)
    check result.matched
    release(sl)

suite "Snapshot - selection controls active state":
  setup:
    createDir(testGoldenDir)
    resetTree()

  teardown:
    removeDir(testGoldenDir)

  test "switch on snapshot":
    let sw = newNSSwitch()
    setSwitchState(sw, true)
    nim_view_set_frame(sw, 0, 0, 50, 25)
    let result = compareSnapshot(sw, "switch_on", 50, 25)
    check result.matched
    release(sw)

  test "slider value snapshot":
    let sl = newNSSlider(0.0, 100.0, 75.0)
    nim_view_set_frame(sl, 0, 0, 200, 25)
    let result = compareSnapshot(sl, "slider_75", 200, 25)
    check result.matched
    release(sl)
