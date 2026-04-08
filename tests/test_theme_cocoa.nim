## Tests for theme integration in CocoaRenderer.

import unittest
import isonim/theming/theme
import isonim_cocoa/renderer

suite "CocoaRenderer - Theme resolution":
  setup:
    resetTree()
    setTheme(isoTheme())
    setDarkMode(false)

  teardown:
    setTheme(nativeTheme())
    setDarkMode(false)

  test "resolveStyleValue resolves primary to hex for background-color":
    let v = resolveStyleValue("background-color", "primary")
    check v == "#6366F1"

  test "resolveStyleValue resolves surface to hex for background-color":
    let v = resolveStyleValue("background-color", "surface")
    check v == "#FFFFFF"

  test "resolveStyleValue passes through raw hex":
    let v = resolveStyleValue("background-color", "#FF0000")
    check v == "#FF0000"

  test "resolveStyleValue resolves primary for color prop":
    let v = resolveStyleValue("color", "primary")
    check v == "#6366F1"

  test "resolveStyleValue resolves spacing md for padding":
    let v = resolveStyleValue("padding", "md")
    check v == "16.0"

  test "resolveStyleValue resolves radius lg for border-radius":
    let v = resolveStyleValue("border-radius", "lg")
    check v == "12.0"

  test "resolveStyleValue passes through raw px values":
    let v = resolveStyleValue("padding", "20px")
    check v == "20px"

  test "resolveStyleValue resolves spacing for gap":
    let v = resolveStyleValue("gap", "sm")
    check v == "8.0"

suite "CocoaRenderer - Theme dark mode resolution":
  setup:
    resetTree()
    setTheme(isoTheme())
    setDarkMode(true)

  teardown:
    setTheme(nativeTheme())
    setDarkMode(false)

  test "dark mode resolves primary to dark hex":
    let v = resolveStyleValue("background-color", "primary")
    check v == "#818CF8"

  test "dark mode resolves background to dark hex":
    let v = resolveStyleValue("background-color", "background")
    check v == "#0F172A"

suite "CocoaRenderer - Native mode passthrough":
  setup:
    resetTree()
    setTheme(nativeTheme())
    setDarkMode(false)

  test "native mode passes through unknown color token":
    let v = resolveStyleValue("background-color", "primary")
    check v == "primary"  # no resolution, raw value passes through

  test "native mode passes through raw hex":
    let v = resolveStyleValue("background-color", "#FF0000")
    check v == "#FF0000"

  test "native mode passes through spacing token":
    let v = resolveStyleValue("padding", "md")
    check v == "md"  # no resolution
