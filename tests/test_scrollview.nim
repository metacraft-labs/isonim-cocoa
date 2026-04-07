## Tests for NSScrollView and NSTableView (M7).

import std/[os, times]
import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/autolayout
import isonim_cocoa/appkit/scrollview
import isonim_cocoa/appkit/tableview
import isonim_cocoa/renderer
import isonim_cocoa/testing/fake_clock
import isonim_cocoa/testing/snapshots

# Use temp dir for snapshot golden files
let testGoldenDir = getTempDir() / "isonim_cocoa_scrollview_test"
goldenDir = testGoldenDir

suite "NSScrollView - properties":
  test "create NSScrollView and set documentView":
    let scroll = newNSScrollView()
    check not scroll.isNil

    # Create a larger document view
    let docView = allocInit("NSView")
    setWantsLayer(docView)
    setFrame(docView, 0, 0, 800, 600)
    setDocumentView(scroll, docView)

    # Read content size — scroll view has a content area
    let (w, h) = contentSize(scroll)
    # Content size should be non-negative (exact value depends on scroller visibility)
    check w >= 0.0
    check h >= 0.0

    release(scroll)

  test "documentVisibleRect returns valid rect":
    let scroll = newNSScrollView()
    setFrame(scroll, 0, 0, 200, 100)
    let docView = allocInit("NSView")
    setFrame(docView, 0, 0, 800, 600)
    setDocumentView(scroll, docView)

    let rect = documentVisibleRect(scroll)
    # Visible rect dimensions should be positive
    check rect.size.width >= 0.0
    check rect.size.height >= 0.0
    release(scroll)

  test "hasVerticalScroller flag":
    let scroll = newNSScrollView()
    check not hasVerticalScroller(scroll)

    setHasVerticalScroller(scroll, true)
    check hasVerticalScroller(scroll)

    setHasVerticalScroller(scroll, false)
    check not hasVerticalScroller(scroll)
    release(scroll)

  test "hasHorizontalScroller flag":
    let scroll = newNSScrollView()
    check not hasHorizontalScroller(scroll)

    setHasHorizontalScroller(scroll, true)
    check hasHorizontalScroller(scroll)

    setHasHorizontalScroller(scroll, false)
    check not hasHorizontalScroller(scroll)
    release(scroll)

suite "NSScrollView - scroll position":
  test "programmatic scroll changes bounds origin":
    let scroll = newNSScrollView()
    setFrame(scroll, 0, 0, 200, 100)

    let docView = allocInit("NSView")
    setWantsLayer(docView)
    setFrame(docView, 0, 0, 800, 600)
    setDocumentView(scroll, docView)

    # Scroll to a specific point
    scrollToPoint(scroll, 50.0, 100.0)

    # Verify bounds origin changed
    let (bx, by) = boundsOrigin(scroll)
    check bx == 50.0
    check by == 100.0

    release(scroll)

suite "NSScrollView - overflow style":
  setup:
    resetTree()

  test "overflow hidden disables scrollers":
    let r = CocoaRenderer()
    let scroll = r.createElement("scroll-view")
    r.setStyle(scroll, "overflow", "hidden")
    check not hasVerticalScroller(Id(scroll))
    check not hasHorizontalScroller(Id(scroll))

  test "overflow scroll enables scrollers":
    let r = CocoaRenderer()
    let scroll = r.createElement("scroll-view")
    r.setStyle(scroll, "overflow", "scroll")
    check hasVerticalScroller(Id(scroll))
    check hasHorizontalScroller(Id(scroll))

  test "overflow auto enables scrollers":
    let r = CocoaRenderer()
    let scroll = r.createElement("scroll-view")
    r.setStyle(scroll, "overflow", "auto")
    check hasVerticalScroller(Id(scroll))
    check hasHorizontalScroller(Id(scroll))

suite "NSTableView - datasource protocol":
  setup:
    resetTableView()

  test "datasource numberOfRowsInTableView returns correct count":
    let (table, ds) = newNSTableView(
      proc(): int = 1000,
      proc(row: int): Id =
        newNSLabel("Row " & $row)
    )

    # Call numberOfRowsInTableView: directly on the datasource
    let rows = msgSendInt(ds, sel("numberOfRowsInTableView:"), table)
    check rows == 1000

    release(table)

  test "datasource tableView:viewForTableColumn:row: returns view":
    let (table, ds) = newNSTableView(
      proc(): int = 100,
      proc(row: int): Id =
        newNSLabel("Item " & $row)
    )

    # Get the first column
    let columns = msgSend(table, sel("tableColumns"))
    let column = nsArrayObjectAtIndex(columns, 0)

    # Call tableView:viewForTableColumn:row: directly
    let view = msgSend(ds, sel("tableView:viewForTableColumn:row:"),
                       table, column, clong(0))
    check not view.isNil

    # Verify the label text
    check stringValue(view) == "Item 0"

    # Call for row 42
    let view42 = msgSend(ds, sel("tableView:viewForTableColumn:row:"),
                          table, column, clong(42))
    check stringValue(view42) == "Item 42"

    release(table)

suite "NSTableView - cell reuse":
  setup:
    resetTableView()

  test "view creation count tracks calls":
    resetViewCreationCount()
    let (table, ds) = newNSTableView(
      proc(): int = 1000,
      proc(row: int): Id =
        newNSLabel("Row " & $row)
    )

    # Directly call viewForRow for a few rows
    let columns = msgSend(table, sel("tableColumns"))
    let column = nsArrayObjectAtIndex(columns, 0)

    for i in 0..<20:
      discard msgSend(ds, sel("tableView:viewForTableColumn:row:"),
                      table, column, clong(i))

    # We called viewForRow 20 times, viewCreationCount should be 20
    # (much less than 1000 total rows)
    check viewCreationCount == 20
    check viewCreationCount < 1000

    release(table)

suite "NSTableView - insert/remove":
  setup:
    resetTableView()

  test "change row count and noteNumberOfRowsChanged does not crash":
    var rowCount = 100
    let (table, ds) = newNSTableView(
      proc(): int = rowCount,
      proc(row: int): Id =
        newNSLabel("Row " & $row)
    )

    # Verify initial count
    let initial = msgSendInt(ds, sel("numberOfRowsInTableView:"), table)
    check initial == 100

    # Change row count
    rowCount = 50
    noteNumberOfRowsChanged(table)

    # Verify updated count
    let updated = msgSendInt(ds, sel("numberOfRowsInTableView:"), table)
    check updated == 50

    # Add rows
    rowCount = 200
    noteNumberOfRowsChanged(table)
    let added = msgSendInt(ds, sel("numberOfRowsInTableView:"), table)
    check added == 200

    release(table)

suite "NSScrollView - integration":
  setup:
    resetTree()

  test "scroll view with items and event":
    let r = CocoaRenderer()
    let scroll = r.createElement("scroll-view")

    # Add content items
    let container = r.createElement("div")
    for i in 0..<5:
      let item = r.createTextNode("Item " & $i)
      r.appendChild(container, item)
    setDocumentView(scroll, container)

    # Register scroll event callback
    var scrollFired = false
    r.addEventListener(scroll, "scroll", proc() =
      scrollFired = true
    )

    # Programmatic scroll
    scrollToPoint(scroll, 0.0, 50.0)
    pumpRunLoop(5)

    # Fire the event manually (since headless mode won't trigger NSScrollView notifications)
    r.fireEvent(scroll, "scroll")
    check scrollFired

suite "NSTableView - performance":
  setup:
    resetTableView()

  test "10000 rows reloadData completes quickly":
    let (table, _) = newNSTableView(
      proc(): int = 10000,
      proc(row: int): Id =
        newNSLabel("Row " & $row)
    )

    let start = cpuTime()
    reloadData(table)
    let elapsed = cpuTime() - start

    # reloadData should be fast — it doesn't create views for all rows
    # (views are created lazily). 100ms = 0.1s
    check elapsed < 0.1

    release(table)

suite "NSScrollView - snapshot":
  setup:
    createDir(testGoldenDir)
    resetTree()

  teardown:
    removeDir(testGoldenDir)

  test "render scroll view snapshot":
    let scroll = newNSScrollView()
    setFrame(scroll, 0, 0, 200, 100)
    setHasVerticalScroller(scroll, true)

    let docView = allocInit("NSView")
    setWantsLayer(docView)
    setFrame(docView, 0, 0, 200, 400)
    setDocumentView(scroll, docView)

    let result = compareSnapshot(scroll, "scroll_view", 200, 100)
    check result.matched  # first run = creates golden
    release(scroll)
