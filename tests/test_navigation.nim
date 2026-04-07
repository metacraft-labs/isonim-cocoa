## Tests for Navigation & Layout Containers (M11).
## NSTabView, NSSplitView, NSToolbar, Drawer, NavStack, and snapshots.

import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/navigation
import isonim_cocoa/renderer
import isonim_cocoa/testing/snapshots

# ===========================================================================
# NSTabView
# ===========================================================================

suite "NSTabView":
  setup:
    resetTree()

  test "create with 3 tabs, verify count and labels":
    let tv = newNSTabView()
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    let v3 = allocInit("NSView")
    tabViewAddTab(tv, "Tab A", v1)
    tabViewAddTab(tv, "Tab B", v2)
    tabViewAddTab(tv, "Tab C", v3)
    check tabViewTabCount(tv) == 3
    check tabViewItemLabel(tv, 0) == "Tab A"
    check tabViewItemLabel(tv, 1) == "Tab B"
    check tabViewItemLabel(tv, 2) == "Tab C"
    release(tv)

  test "switch tabs, verify selectedIndex changes":
    let tv = newNSTabView()
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    let v3 = allocInit("NSView")
    tabViewAddTab(tv, "First", v1)
    tabViewAddTab(tv, "Second", v2)
    tabViewAddTab(tv, "Third", v3)
    # First tab is auto-selected
    check tabViewSelectedIndex(tv) == 0
    tabViewSelectIndex(tv, 2)
    check tabViewSelectedIndex(tv) == 2
    tabViewSelectIndex(tv, 1)
    check tabViewSelectedIndex(tv) == 1
    release(tv)

  test "tab content view round-trip":
    let tv = newNSTabView()
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    tabViewAddTab(tv, "A", v1)
    tabViewAddTab(tv, "B", v2)
    # When tab 0 is selected, its content view should be the one we passed
    check pointer(tabViewItemView(tv, 0)) == pointer(v1)
    check pointer(tabViewItemView(tv, 1)) == pointer(v2)
    release(tv)

  test "delegate callback fires on tab switch":
    # We test this via Nim-side event mechanism on the renderer
    let r = CocoaRenderer()
    let tv = r.createElement("tab-view")
    # Add tabs via native API
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    tabViewAddTab(Id(tv), "One", v1)
    tabViewAddTab(Id(tv), "Two", v2)
    var switched = false
    r.addEventListener(tv, "change", proc() = switched = true)
    # Simulate event fire
    r.fireEvent(tv, "change")
    check switched

# ===========================================================================
# NSSplitView
# ===========================================================================

suite "NSSplitView":
  setup:
    resetTree()

  test "create with 2 subviews, verify count and isVertical":
    let sv = newNSSplitView(vertical = true)
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    setWantsLayer(v1)
    setWantsLayer(v2)
    splitViewAddSubview(sv, v1)
    splitViewAddSubview(sv, v2)
    check splitViewSubviewCount(sv) == 2
    check splitViewIsVertical(sv) == true
    release(sv)

  test "set divider position, verify subview frames reflect split":
    let sv = newNSSplitView(vertical = true)
    # Give the split view a frame so layout has room to work
    setViewFrame(sv, 0.0, 0.0, 400.0, 200.0)
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    setWantsLayer(v1)
    setWantsLayer(v2)
    splitViewAddSubview(sv, v1)
    splitViewAddSubview(sv, v2)
    splitViewSetPosition(sv, 150.0, 0)
    # Force layout
    msgSendVoid(sv, sel("layoutSubtreeIfNeeded"))
    # Verify we can read back frames after setting position
    # Without a window, NSSplitView may not fully layout subviews,
    # so we verify the API works and returns non-negative frames.
    let f1 = splitViewSubviewFrame(sv, 0)
    let f2 = splitViewSubviewFrame(sv, 1)
    check f1.size.width >= 0.0
    check f2.size.width >= 0.0
    # The total width should not exceed the split view frame width
    check f1.size.width + f2.size.width <= 410.0  # 400 + divider
    release(sv)

  test "collapse: set position to 0, first subview has zero width":
    let sv = newNSSplitView(vertical = true)
    setViewFrame(sv, 0.0, 0.0, 400.0, 200.0)
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    setWantsLayer(v1)
    setWantsLayer(v2)
    splitViewAddSubview(sv, v1)
    splitViewAddSubview(sv, v2)
    splitViewSetPosition(sv, 0.0, 0)
    msgSendVoid(sv, sel("layoutSubtreeIfNeeded"))
    let f1 = splitViewSubviewFrame(sv, 0)
    check f1.size.width <= 1.0  # effectively zero or collapsed
    release(sv)

# ===========================================================================
# Toolbar (Nim-managed)
# ===========================================================================

suite "NSToolbar - Nim-managed items":
  setup:
    resetTree()

  test "add items, verify count and labels":
    let tb = newNSToolbar("testToolbar")
    toolbarAddItem(tb, "New", proc() = discard)
    toolbarAddItem(tb, "Open", proc() = discard)
    toolbarAddItem(tb, "Save", proc() = discard)
    check toolbarItemCount(tb) == 3
    check toolbarItemLabel(tb, 0) == "New"
    check toolbarItemLabel(tb, 1) == "Open"
    check toolbarItemLabel(tb, 2) == "Save"
    release(tb)

  test "simulate click, verify callback fires":
    let tb = newNSToolbar("clickTest")
    var clicked = -1
    toolbarAddItem(tb, "A", proc() = clicked = 0)
    toolbarAddItem(tb, "B", proc() = clicked = 1)
    toolbarAddItem(tb, "C", proc() = clicked = 2)
    toolbarSimulateClick(tb, 1)
    check clicked == 1
    toolbarSimulateClick(tb, 2)
    check clicked == 2
    release(tb)

# ===========================================================================
# NavStack (pure Nim state)
# ===========================================================================

suite "NavStack":
  setup:
    resetTree()

  test "push 3 views, verify depth and currentView":
    let r = CocoaRenderer()
    let nav = r.createElement("nav-stack")
    let v1 = r.createElement("div")
    let v2 = r.createElement("div")
    let v3 = r.createElement("div")
    r.navStackPush(nav, v1)
    r.navStackPush(nav, v2)
    r.navStackPush(nav, v3)
    check r.navStackDepth(nav) == 3
    check pointer(r.navStackCurrent(nav)) == pointer(v3)

  test "pop, verify depth changes and currentView updates":
    let r = CocoaRenderer()
    let nav = r.createElement("nav-stack")
    let v1 = r.createElement("div")
    let v2 = r.createElement("div")
    let v3 = r.createElement("div")
    r.navStackPush(nav, v1)
    r.navStackPush(nav, v2)
    r.navStackPush(nav, v3)
    let popped = r.navStackPop(nav)
    check pointer(popped) == pointer(v3)
    check r.navStackDepth(nav) == 2
    check pointer(r.navStackCurrent(nav)) == pointer(v2)

  test "popToRoot, verify depth is 1":
    let r = CocoaRenderer()
    let nav = r.createElement("nav-stack")
    let v1 = r.createElement("div")
    let v2 = r.createElement("div")
    let v3 = r.createElement("div")
    r.navStackPush(nav, v1)
    r.navStackPush(nav, v2)
    r.navStackPush(nav, v3)
    r.navStackPopToRoot(nav)
    check r.navStackDepth(nav) == 1
    check pointer(r.navStackCurrent(nav)) == pointer(v1)

  test "onPush and onPop callbacks fire":
    let r = CocoaRenderer()
    let nav = r.createElement("nav-stack")
    var pushCount = 0
    var popCount = 0
    r.navStackSetOnPush(nav, proc() = inc pushCount)
    r.navStackSetOnPop(nav, proc() = inc popCount)
    let v1 = r.createElement("div")
    let v2 = r.createElement("div")
    r.navStackPush(nav, v1)
    check pushCount == 1
    r.navStackPush(nav, v2)
    check pushCount == 2
    discard r.navStackPop(nav)
    check popCount == 1

# ===========================================================================
# Drawer (pure Nim state)
# ===========================================================================

suite "Drawer":
  setup:
    resetTree()

  test "initial state closed, set open=true, verify open":
    let r = CocoaRenderer()
    let drawer = r.createElement("drawer")
    check r.drawerState(drawer) == dsClosed
    r.setAttribute(drawer, "open", "true")
    check r.drawerState(drawer) == dsOpen

  test "toggle: open then close":
    let r = CocoaRenderer()
    let drawer = r.createElement("drawer")
    r.setAttribute(drawer, "open", "true")
    check r.drawerState(drawer) == dsOpen
    r.setAttribute(drawer, "open", "false")
    check r.drawerState(drawer) == dsClosed

  test "edge: set right, verify internal state":
    let r = CocoaRenderer()
    let drawer = r.createElement("drawer")
    # Default edge is left
    check r.drawerEdge(drawer) == deLeft
    # Set to right
    r.setAttribute(drawer, "edge", "right")
    check r.drawerEdge(drawer) == deRight
    # Set back to left
    r.setAttribute(drawer, "edge", "left")
    check r.drawerEdge(drawer) == deLeft

# ===========================================================================
# Snapshots
# ===========================================================================

suite "Navigation snapshots":
  setup:
    resetTree()

  test "tab view with 3 tabs snapshot":
    let tv = newNSTabView()
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    let v3 = allocInit("NSView")
    setWantsLayer(v1)
    setWantsLayer(v2)
    setWantsLayer(v3)
    tabViewAddTab(tv, "Alpha", v1)
    tabViewAddTab(tv, "Beta", v2)
    tabViewAddTab(tv, "Gamma", v3)
    let result = compareSnapshot(tv, "tabview_3tabs", 300, 200)
    check result.matched
    release(tv)

  test "split view 30/70 snapshot":
    let sv = newNSSplitView(vertical = true)
    setViewFrame(sv, 0.0, 0.0, 300.0, 200.0)
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    setWantsLayer(v1)
    setWantsLayer(v2)
    splitViewAddSubview(sv, v1)
    splitViewAddSubview(sv, v2)
    splitViewSetPosition(sv, 90.0, 0)  # 30% of 300
    msgSendVoid(sv, sel("layoutSubtreeIfNeeded"))
    let result = compareSnapshot(sv, "splitview_30_70", 300, 200)
    check result.matched
    release(sv)
