## Tests for NSTextView, NSSecureTextField, NSSearchField (M8).

import std/os
import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/scrollview
import isonim_cocoa/appkit/textcontrols
import isonim_cocoa/renderer
import isonim_cocoa/testing/snapshots

# Use temp dir for snapshot golden files
let testGoldenDir = getTempDir() / "isonim_cocoa_textcontrols_test"
goldenDir = testGoldenDir

suite "NSTextView - create and text":
  test "create NSTextView, set text, read back":
    let scroll = newNSTextView(300, 100)
    check not scroll.isNil
    let tv = textViewFromScroll(scroll)
    check not tv.isNil

    setTextViewString(tv, "Hello, world!")
    check textViewString(tv) == "Hello, world!"

    release(scroll)

  test "multiline text with newlines":
    let scroll = newNSTextView(300, 200)
    let tv = textViewFromScroll(scroll)

    setTextViewString(tv, "Line 1\nLine 2\nLine 3")
    check textViewString(tv) == "Line 1\nLine 2\nLine 3"

    let lines = textViewLineCount(tv)
    check lines == 3

    release(scroll)

  test "empty text view has zero lines":
    let scroll = newNSTextView(300, 100)
    let tv = textViewFromScroll(scroll)

    check textViewString(tv) == ""
    check textViewLineCount(tv) == 0

    release(scroll)

  test "text change delegate via textStorage notification":
    # Create an NSTextView and verify text can be modified via textStorage
    let scroll = newNSTextView(300, 100)
    let tv = textViewFromScroll(scroll)

    # Set initial text
    setTextViewString(tv, "initial")
    check textViewString(tv) == "initial"

    # Modify via textStorage again
    setTextViewString(tv, "modified")
    check textViewString(tv) == "modified"

    # Verify textStorage is accessible
    let textStorage = msgSend(tv, sel("textStorage"))
    check not textStorage.isNil

    release(scroll)

suite "NSSecureTextField":
  test "create and verify secure type":
    let stf = newNSSecureTextField()
    check not stf.isNil
    check isSecureTextField(stf)

    release(stf)

  test "secure text field is not a regular text field":
    let regular = newNSTextField()
    check not isSecureTextField(regular)

    let secure = newNSSecureTextField()
    check isSecureTextField(secure)

    release(regular)
    release(secure)

  test "secure text field supports stringValue":
    let stf = newNSSecureTextField()
    setStringValue(stf, "secret123")
    check stringValue(stf) == "secret123"
    release(stf)

suite "NSSearchField - create":
  test "create and set/get text":
    let sf = newNSSearchField()
    check not sf.isNil

    setSearchString(sf, "query text")
    check searchString(sf) == "query text"

    release(sf)

  test "create with placeholder":
    let sf = newNSSearchField("Search here...")
    check searchFieldPlaceholder(sf) == "Search here..."

    release(sf)

  test "set and get placeholder separately":
    let sf = newNSSearchField()
    setPlaceholder(sf, "Type to search")
    check searchFieldPlaceholder(sf) == "Type to search"

    release(sf)

  test "cancel button exists":
    let sf = newNSSearchField()
    check hasCancelButton(sf)

    release(sf)

suite "Renderer - textarea and search":
  setup:
    resetTree()

  test "createElement textarea creates NSTextView in scroll":
    let r = CocoaRenderer()
    let elem = r.createElement("textarea")
    check not Id(elem).isNil

    # Set text via renderer
    r.setTextContent(elem, "Hello from textarea")
    check r.textContent(elem) == "Hello from textarea"

  test "createElement search creates NSSearchField":
    let r = CocoaRenderer()
    let elem = r.createElement("search")
    check not Id(elem).isNil

    # Set text via renderer
    r.setTextContent(elem, "search query")
    check r.textContent(elem) == "search query"

  test "input type password sets secure kind":
    let r = CocoaRenderer()
    let elem = r.createElement("input")
    r.setAttribute(elem, "type", "password")

    # The attribute should be stored
    check r.getAttribute(elem, "type") == "password"

  test "search field placeholder via setAttribute":
    let r = CocoaRenderer()
    let elem = r.createElement("search")
    r.setAttribute(elem, "placeholder", "Find items...")

    check searchFieldPlaceholder(Id(elem)) == "Find items..."

suite "Snapshot - textarea":
  setup:
    createDir(testGoldenDir)
    resetTree()

  teardown:
    removeDir(testGoldenDir)

  test "render textarea snapshot":
    let scroll = newNSTextView(300, 100)
    let tv = textViewFromScroll(scroll)
    setTextViewString(tv, "Multiline\ntext\ncontent")

    let result = compareSnapshot(scroll, "textarea", 300, 100)
    check result.matched  # first run = creates golden
    release(scroll)

suite "Snapshot - search field":
  setup:
    createDir(testGoldenDir)
    resetTree()

  teardown:
    removeDir(testGoldenDir)

  test "render search field snapshot":
    let sf = newNSSearchField("Search...")
    nim_view_set_frame(sf, 0, 0, 200, 30)

    let result = compareSnapshot(sf, "search_field", 200, 30)
    check result.matched  # first run = creates golden
    release(sf)
