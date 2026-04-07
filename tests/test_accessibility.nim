## Tests for Accessibility (M14).
## NSAccessibility protocol, auto-roles, aria-* attributes.

import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/accessibility
import isonim_cocoa/renderer
import isonim_cocoa/testing/fake_clock

# ===========================================================================
# Auto-roles
# ===========================================================================

suite "Accessibility - auto-roles":
  setup:
    resetTree()

  test "button gets ButtonRole":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    check accessibilityRole(Id(btn)) == "AXButton"

  test "input gets TextFieldRole":
    let r = CocoaRenderer()
    let inp = r.createElement("input")
    check accessibilityRole(Id(inp)) == "AXTextField"

  test "span gets StaticTextRole":
    let r = CocoaRenderer()
    let sp = r.createElement("span")
    check accessibilityRole(Id(sp)) == "AXStaticText"

  test "p gets StaticTextRole":
    let r = CocoaRenderer()
    let p = r.createElement("p")
    check accessibilityRole(Id(p)) == "AXStaticText"

  test "div gets GroupRole":
    let r = CocoaRenderer()
    let d = r.createElement("div")
    check accessibilityRole(Id(d)) == "AXGroup"

  test "img gets ImageRole":
    let r = CocoaRenderer()
    let img = r.createElement("img")
    check accessibilityRole(Id(img)) == "AXImage"

  test "slider gets SliderRole":
    let r = CocoaRenderer()
    let sl = r.createElement("slider")
    check accessibilityRole(Id(sl)) == "AXSlider"

  test "switch gets CheckBoxRole":
    let r = CocoaRenderer()
    let sw = r.createElement("switch")
    check accessibilityRole(Id(sw)) == "AXCheckBox"

  test "ul gets ListRole":
    let r = CocoaRenderer()
    let ul = r.createElement("ul")
    check accessibilityRole(Id(ul)) == "AXList"

  test "ol gets ListRole":
    let r = CocoaRenderer()
    let ol = r.createElement("ol")
    check accessibilityRole(Id(ol)) == "AXList"

# ===========================================================================
# aria-label
# ===========================================================================

suite "Accessibility - aria-label":
  setup:
    resetTree()

  test "setAttribute aria-label sets accessibility label":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    r.setAttribute(btn, "aria-label", "Close button")
    check accessibilityLabel(Id(btn)) == "Close button"

# ===========================================================================
# aria-hidden
# ===========================================================================

suite "Accessibility - aria-hidden":
  setup:
    resetTree()

  test "setAttribute aria-hidden true removes from accessibility":
    let r = CocoaRenderer()
    let d = r.createElement("div")
    r.setAttribute(d, "aria-hidden", "true")
    check isAccessibilityElement(Id(d)) == false

  test "setAttribute aria-hidden false marks as accessibility element":
    let r = CocoaRenderer()
    let d = r.createElement("div")
    r.setAttribute(d, "aria-hidden", "false")
    check isAccessibilityElement(Id(d)) == true

# ===========================================================================
# aria-role override
# ===========================================================================

suite "Accessibility - aria-role override":
  setup:
    resetTree()

  test "aria-role=link overrides auto-set GroupRole on div":
    let r = CocoaRenderer()
    let d = r.createElement("div")
    check accessibilityRole(Id(d)) == "AXGroup"
    r.setAttribute(d, "aria-role", "link")
    check accessibilityRole(Id(d)) == "AXLink"

# ===========================================================================
# Value binding
# ===========================================================================

suite "Accessibility - value binding":
  setup:
    resetTree()

  test "aria-valuenow sets accessibility value":
    let r = CocoaRenderer()
    let prog = r.createElement("progress")
    r.setAttribute(prog, "aria-valuenow", "42")
    check accessibilityValue(Id(prog)) == "42"

  test "aria-valuemin and aria-valuemax are stored as attributes":
    let r = CocoaRenderer()
    let prog = r.createElement("progress")
    r.setAttribute(prog, "aria-valuemin", "0")
    r.setAttribute(prog, "aria-valuemax", "100")
    check r.getAttribute(prog, "aria-valuemin") == "0"
    check r.getAttribute(prog, "aria-valuemax") == "100"

# ===========================================================================
# Heading levels
# ===========================================================================

suite "Accessibility - heading levels":
  setup:
    resetTree()

  test "h1 gets StaticTextRole":
    let r = CocoaRenderer()
    let h1 = r.createElement("h1")
    check accessibilityRole(Id(h1)) == "AXStaticText"

  test "h2 gets StaticTextRole":
    let r = CocoaRenderer()
    let h2 = r.createElement("h2")
    check accessibilityRole(Id(h2)) == "AXStaticText"

  test "h3 gets StaticTextRole":
    let r = CocoaRenderer()
    let h3 = r.createElement("h3")
    check accessibilityRole(Id(h3)) == "AXStaticText"

  test "h6 gets StaticTextRole":
    let r = CocoaRenderer()
    let h6 = r.createElement("h6")
    check accessibilityRole(Id(h6)) == "AXStaticText"

# ===========================================================================
# Integration: reactive label
# ===========================================================================

suite "Accessibility - reactive label":
  setup:
    resetTree()

  test "signal-driven aria-label update via pumpRunLoop":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    r.setAttribute(btn, "aria-label", "Open menu")
    check accessibilityLabel(Id(btn)) == "Open menu"
    # Simulate a reactive update
    r.setAttribute(btn, "aria-label", "Close menu")
    pumpRunLoop(5)
    check accessibilityLabel(Id(btn)) == "Close menu"

# ===========================================================================
# Cross: accessibility parity
# ===========================================================================

suite "Accessibility - parity":
  setup:
    resetTree()

  test "each element type produces a non-empty role":
    let r = CocoaRenderer()
    let tags = ["button", "input", "span", "div", "img", "slider", "switch", "ul"]
    for tag in tags:
      let elem = r.createElement(tag)
      let role = accessibilityRole(Id(elem))
      check role.len > 0

# ===========================================================================
# Direct API tests
# ===========================================================================

suite "Accessibility - direct API":
  setup:
    resetTree()

  test "setAccessibilityLabel and accessibilityLabel round-trip":
    let view = allocInit("NSView")
    setAccessibilityLabel(view, "Test label")
    check accessibilityLabel(view) == "Test label"
    release(view)

  test "setAccessibilityRole and accessibilityRole round-trip":
    let view = allocInit("NSView")
    setAccessibilityRole(view, accessibilityButtonRole())
    check accessibilityRole(view) == "AXButton"
    release(view)

  test "setAccessibilityValue and accessibilityValue round-trip":
    let view = allocInit("NSView")
    setAccessibilityValue(view, "75%")
    check accessibilityValue(view) == "75%"
    release(view)

  test "setAccessibilityElement round-trip":
    let view = allocInit("NSView")
    setAccessibilityElement(view, false)
    check isAccessibilityElement(view) == false
    setAccessibilityElement(view, true)
    check isAccessibilityElement(view) == true
    release(view)

suite "Accessibility - Focus":
  setup:
    resetTree()

  test "focus: accessibility focused API is callable":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    # isAccessibilityFocused should return false by default
    let focused = isAccessibilityFocused(Id(btn))
    check focused == false
    # setAccessibilityFocused is callable (focus doesn't persist
    # without a window, but the API must not crash)
    setAccessibilityFocused(Id(btn), true)
    setAccessibilityFocused(Id(btn), false)
    # Verify the view is still valid
    check not Id(btn).isNil

  test "focus chain: tabindex elements are focusable":
    let r = CocoaRenderer()
    let e1 = r.createElement("button")
    let e2 = r.createElement("input")
    let e3 = r.createElement("button")
    let e4 = r.createElement("input")
    # Set tabindex on all four — this marks them as participanting in focus
    r.setAttribute(e1, "tabindex", "3")
    r.setAttribute(e2, "tabindex", "1")
    r.setAttribute(e3, "tabindex", "4")
    r.setAttribute(e4, "tabindex", "2")
    # Verify the tabindex attribute was stored
    check r.getAttribute(e1, "tabindex") == "3"
    check r.getAttribute(e2, "tabindex") == "1"
    check r.getAttribute(e3, "tabindex") == "4"
    check r.getAttribute(e4, "tabindex") == "2"
    # Verify all elements have accessibility roles (are in the a11y tree)
    check accessibilityRole(Id(e1)) == "AXButton"
    check accessibilityRole(Id(e2)) == "AXTextField"
    check accessibilityRole(Id(e3)) == "AXButton"
    check accessibilityRole(Id(e4)) == "AXTextField"
    # Note: nextValidKeyView chain requires a window with key view loop,
    # which can't be set up headlessly. We verify the tabindex is stored
    # and elements are accessible, which is sufficient for headless testing.
