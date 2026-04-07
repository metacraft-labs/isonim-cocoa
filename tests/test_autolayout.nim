## Tests for Auto Layout integration (M3).

import unittest
import std/[times]
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/autolayout
import isonim_cocoa/renderer
import isonim_cocoa/testing/snapshots

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc approxEq(a, b: cdouble; tolerance: cdouble = 1.0): bool =
  ## Check if two doubles are approximately equal within tolerance.
  abs(a - b) <= tolerance

proc newContainerView(width, height: cdouble): Id =
  ## Create a root container with a fixed frame for layout testing.
  let view = allocInit("NSView")
  setWantsLayer(view)
  setFrame(view, 0, 0, width, height)
  view

proc newStackContainer(width, height: cdouble; horizontal: bool = false): Id =
  ## Create an NSStackView root container with a fixed frame.
  let stack = newNSStackView(if horizontal: 0 else: 1)
  setWantsLayer(stack)
  setFrame(stack, 0, 0, width, height)
  stack

# ===========================================================================
# Test suites
# ===========================================================================

suite "Auto Layout - Constraint Creation":
  setup:
    resetTree()

  test "width constraint created with correct constant":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "width", "100px")

    let c = getConstraint(Id(view), "width")
    check not c.isNil
    check approxEq(constraintConstant(c), 100.0)

  test "height constraint created with correct constant":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "height", "50px")

    let c = getConstraint(Id(view), "height")
    check not c.isNil
    check approxEq(constraintConstant(c), 50.0)

  test "constraint is active after creation":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "width", "100px")

    let c = getConstraint(Id(view), "width")
    check isActive(c)

suite "Auto Layout - Constraint-Driven Frames":
  setup:
    resetTree()

  test "child with width and height constraints":
    let parent = newContainerView(300, 200)
    let child = allocInit("NSView")
    setWantsLayer(child)
    disableAutoresizingMask(child)
    addSubview(parent, child)

    let wc = constraintEqualToConstant(widthAnchor(child), 100.0)
    setActive(wc, true)
    let hc = constraintEqualToConstant(heightAnchor(child), 50.0)
    setActive(hc, true)

    layoutSubtreeIfNeeded(parent)

    let f = frame(child)
    check approxEq(f.size.width, 100.0)
    check approxEq(f.size.height, 50.0)

  test "child via renderer setStyle":
    let parent = newContainerView(300, 200)
    let r = CocoaRenderer()
    let child = r.createElement("div")
    disableAutoresizingMask(Id(child))
    addSubview(parent, Id(child))

    r.setStyle(child, "width", "120px")
    r.setStyle(child, "height", "80px")

    layoutSubtreeIfNeeded(parent)

    let f = frame(Id(child))
    check approxEq(f.size.width, 120.0)
    check approxEq(f.size.height, 80.0)

suite "Auto Layout - Flex Layout":
  setup:
    resetTree()

  test "three children in row with gap":
    let stack = newStackContainer(330, 100, horizontal = true)
    setSpacing(stack, 10.0)
    setDistribution(stack, 5)  # fill

    var children: array[3, Id]
    for i in 0..2:
      children[i] = allocInit("NSView")
      setWantsLayer(children[i])
      disableAutoresizingMask(children[i])
      addArrangedSubview(stack, children[i])

    # Equal-width constraints (simulates flex: 1 for each child)
    for i in 1..2:
      let c = constraintEqualToAnchor(widthAnchor(children[i]), widthAnchor(children[0]))
      setActive(c, true)

    layoutSubtreeIfNeeded(stack)

    # 330px - 2*10px gap = 310px / 3 ~= 103.3px each
    let expectedWidth = (330.0 - 20.0) / 3.0
    for i in 0..2:
      let f = frame(children[i])
      check approxEq(f.size.width, expectedWidth, 2.0)

  test "flex children get roughly equal widths":
    let stack = newStackContainer(300, 100, horizontal = true)
    setDistribution(stack, 5)  # fill
    setSpacing(stack, 0.0)

    var children: array[3, Id]
    for i in 0..2:
      children[i] = allocInit("NSView")
      setWantsLayer(children[i])
      disableAutoresizingMask(children[i])
      addArrangedSubview(stack, children[i])

    # Equal-width constraints (simulates flex: 1 for each child)
    for i in 1..2:
      let c = constraintEqualToAnchor(widthAnchor(children[i]), widthAnchor(children[0]))
      setActive(c, true)

    layoutSubtreeIfNeeded(stack)

    for i in 0..2:
      let f = frame(children[i])
      check approxEq(f.size.width, 100.0, 2.0)

suite "Auto Layout - Padding":
  setup:
    resetTree()

  test "stack view with padding offsets child":
    let stack = newStackContainer(200, 200, horizontal = false)
    setEdgeInsets(stack, 20, 20, 20, 20)
    setDistribution(stack, 5)  # fill

    let child = allocInit("NSView")
    setWantsLayer(child)
    disableAutoresizingMask(child)
    addArrangedSubview(stack, child)

    layoutSubtreeIfNeeded(stack)

    let f = frame(child)
    # Child should be inset by padding
    check approxEq(f.origin.x, 20.0, 2.0)
    # Width should be parent width - left padding - right padding
    check approxEq(f.size.width, 160.0, 2.0)

suite "Auto Layout - Alignment":
  setup:
    resetTree()

  test "NSStackView center alignment":
    let stack = newStackContainer(300, 200, horizontal = false)
    setAlignment(stack, 9)  # NSLayoutFormatAlignAllCenterX

    let child = allocInit("NSView")
    setWantsLayer(child)
    disableAutoresizingMask(child)
    let wc = constraintEqualToConstant(widthAnchor(child), 100.0)
    setActive(wc, true)
    let hc = constraintEqualToConstant(heightAnchor(child), 50.0)
    setActive(hc, true)
    addArrangedSubview(stack, child)

    layoutSubtreeIfNeeded(stack)

    let f = frame(child)
    # With center alignment, child should be centered: (300-100)/2 = 100
    check approxEq(f.origin.x, 100.0, 2.0)
    check approxEq(f.size.width, 100.0, 2.0)

suite "Auto Layout - Constraint Update":
  setup:
    resetTree()

  test "changing width updates constraint and frame":
    let parent = newContainerView(300, 200)
    let r = CocoaRenderer()
    let child = r.createElement("div")
    disableAutoresizingMask(Id(child))
    addSubview(parent, Id(child))

    r.setStyle(child, "width", "100px")
    r.setStyle(child, "height", "50px")
    layoutSubtreeIfNeeded(parent)

    let f1 = frame(Id(child))
    check approxEq(f1.size.width, 100.0)

    # Update width
    r.setStyle(child, "width", "200px")
    layoutSubtreeIfNeeded(parent)

    let f2 = frame(Id(child))
    check approxEq(f2.size.width, 200.0)

  test "constraint constant is updated":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "width", "100px")

    let c1 = getConstraint(Id(view), "width")
    check approxEq(constraintConstant(c1), 100.0)

    r.setStyle(view, "width", "200px")

    let c2 = getConstraint(Id(view), "width")
    check approxEq(constraintConstant(c2), 200.0)

suite "Auto Layout - Constraint Deactivation":
  setup:
    resetTree()

  test "removing a constraint deactivates it":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "width", "100px")

    let c = getConstraint(Id(view), "width")
    check isActive(c)

    removeConstraint(Id(view), "width")
    check not isActive(c)

  test "clearConstraints deactivates all":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "width", "100px")
    r.setStyle(view, "height", "50px")

    let cw = getConstraint(Id(view), "width")
    let ch = getConstraint(Id(view), "height")
    check isActive(cw)
    check isActive(ch)

    clearConstraints(Id(view))
    check not isActive(cw)
    check not isActive(ch)

suite "Auto Layout - Performance":
  setup:
    resetTree()

  test "200 views with constraints layout quickly":
    let parent = newContainerView(1000, 5000)
    var children: seq[Id]

    for i in 0..<200:
      let child = allocInit("NSView")
      setWantsLayer(child)
      disableAutoresizingMask(child)
      addSubview(parent, child)
      let wc = constraintEqualToConstant(widthAnchor(child), 80.0)
      setActive(wc, true)
      let hc = constraintEqualToConstant(heightAnchor(child), 20.0)
      setActive(hc, true)
      children.add(child)

    let start = cpuTime()
    layoutSubtreeIfNeeded(parent)
    let elapsed = (cpuTime() - start) * 1000  # milliseconds

    check elapsed < 50.0

    # Verify at least one child got laid out
    let f = frame(children[0])
    check approxEq(f.size.width, 80.0)
    check approxEq(f.size.height, 20.0)

suite "Auto Layout - Snapshot: Flex Row":
  setup:
    resetTree()

  test "three equal-width children in a row":
    let stack = newStackContainer(300, 100, horizontal = true)
    setDistribution(stack, 3)  # fillEqually
    setSpacing(stack, 0.0)

    for i in 0..2:
      let child = allocInit("NSView")
      setWantsLayer(child)
      disableAutoresizingMask(child)
      addArrangedSubview(stack, child)

    layoutSubtreeIfNeeded(stack)

    let snap = compareSnapshot(stack, "autolayout_flex_row",
                                width = 300, height = 100,
                                tolerance = 0.05)
    check snap.matched

suite "Auto Layout - Snapshot: Nested Layout":
  setup:
    resetTree()

  test "header + sidebar + content layout":
    # Outer vertical stack: header on top, body below
    let outer = newStackContainer(400, 300, horizontal = false)
    setDistribution(outer, 5)  # fill
    setSpacing(outer, 0.0)

    # Header: fixed height
    let header = allocInit("NSView")
    setWantsLayer(header)
    disableAutoresizingMask(header)
    let hc = constraintEqualToConstant(heightAnchor(header), 50.0)
    setActive(hc, true)
    addArrangedSubview(outer, header)

    # Body: horizontal stack with sidebar + content
    let body = newStackContainer(400, 250, horizontal = true)
    disableAutoresizingMask(Id(body))
    setDistribution(body, 5)  # fill
    setSpacing(body, 0.0)

    # Sidebar: fixed width
    let sidebar = allocInit("NSView")
    setWantsLayer(sidebar)
    disableAutoresizingMask(sidebar)
    let swc = constraintEqualToConstant(widthAnchor(sidebar), 100.0)
    setActive(swc, true)
    addArrangedSubview(body, sidebar)

    # Content: fills remaining space
    let content = allocInit("NSView")
    setWantsLayer(content)
    disableAutoresizingMask(content)
    addArrangedSubview(body, content)

    addArrangedSubview(outer, Id(body))

    layoutSubtreeIfNeeded(outer)

    let snap = compareSnapshot(outer, "autolayout_nested_layout",
                                width = 400, height = 300,
                                tolerance = 0.05)
    check snap.matched
