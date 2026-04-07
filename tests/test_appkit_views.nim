## Tests for AppKit view bindings (M1).

import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

suite "Foundation - NSString":
  test "round-trip string conversion":
    let ns = toNSString("hello world")
    check not ns.isNil
    check toNimString(ns) == "hello world"
    release(ns)

  test "empty string":
    let ns = toNSString("")
    check not ns.isNil
    check toNimString(ns) == ""
    check nsStringLength(ns) == 0
    release(ns)

  test "unicode string":
    let ns = toNSString("café ☕")
    check not ns.isNil
    check toNimString(ns) == "café ☕"
    release(ns)

suite "Foundation - NSMutableArray":
  test "create empty array":
    let arr = newNSMutableArray()
    check not arr.isNil
    check nsArrayCount(arr) == 0
    release(arr)

  test "add and count":
    let arr = newNSMutableArray()
    let s1 = toNSString("one")
    let s2 = toNSString("two")
    nsArrayAddObject(arr, s1)
    nsArrayAddObject(arr, s2)
    check nsArrayCount(arr) == 2
    release(s1)
    release(s2)
    release(arr)

  test "objectAtIndex":
    let arr = newNSMutableArray()
    let s1 = toNSString("first")
    let s2 = toNSString("second")
    nsArrayAddObject(arr, s1)
    nsArrayAddObject(arr, s2)
    check toNimString(nsArrayObjectAtIndex(arr, 0)) == "first"
    check toNimString(nsArrayObjectAtIndex(arr, 1)) == "second"
    release(s1)
    release(s2)
    release(arr)

  test "removeObjectAtIndex":
    let arr = newNSMutableArray()
    let s1 = toNSString("a")
    let s2 = toNSString("b")
    nsArrayAddObject(arr, s1)
    nsArrayAddObject(arr, s2)
    nsArrayRemoveObjectAtIndex(arr, 0)
    check nsArrayCount(arr) == 1
    check toNimString(nsArrayObjectAtIndex(arr, 0)) == "b"
    release(s1)
    release(s2)
    release(arr)

suite "Foundation - NSMutableDictionary":
  test "create empty dictionary":
    let dict = newNSMutableDictionary()
    check not dict.isNil
    check nsDictCount(dict) == 0
    release(dict)

  test "set and get":
    let dict = newNSMutableDictionary()
    let key = toNSString("name")
    let value = toNSString("IsoNim")
    nsDictSetObject(dict, value, key)
    check nsDictCount(dict) == 1
    let retrieved = nsDictObjectForKey(dict, key)
    check toNimString(retrieved) == "IsoNim"
    release(key)
    release(value)
    release(dict)

suite "Foundation - Color Parsing":
  test "parse #RGB":
    let (r, g, b, a) = parseHexColor("#FFF")
    check r == 1.0
    check g == 1.0
    check b == 1.0
    check a == 1.0

  test "parse #RRGGBB":
    let (r, g, b, a) = parseHexColor("#FF8000")
    check r == 1.0
    check g > 0.49 and g < 0.51
    check b == 0.0
    check a == 1.0

  test "parse #RRGGBBAA":
    let (r, g, b, a) = parseHexColor("#FF000080")
    check r == 1.0
    check g == 0.0
    check b == 0.0
    check a > 0.49 and a < 0.52

suite "AppKit - NSView":
  test "create NSView":
    let view = allocInit("NSView")
    check not view.isNil
    release(view)

  test "addSubview and subviewCount":
    let parent = allocInit("NSView")
    let child1 = allocInit("NSView")
    let child2 = allocInit("NSView")
    addSubview(parent, child1)
    addSubview(parent, child2)
    check subviewCount(parent) == 2
    release(parent)

  test "removeFromSuperview":
    let parent = allocInit("NSView")
    let child = allocInit("NSView")
    addSubview(parent, child)
    check subviewCount(parent) == 1
    removeFromSuperview(child)
    check subviewCount(parent) == 0
    release(parent)

  test "superview":
    let parent = allocInit("NSView")
    let child = allocInit("NSView")
    addSubview(parent, child)
    let sup = superview(child)
    check sup == parent
    release(parent)

  test "setHidden and isHidden":
    let view = allocInit("NSView")
    check not isHidden(view)
    setHidden(view, true)
    check isHidden(view)
    setHidden(view, false)
    check not isHidden(view)
    release(view)

suite "AppKit - NSTextField":
  test "create label":
    let label = newNSLabel("Hello")
    check not label.isNil
    check stringValue(label) == "Hello"
    release(label)

  test "set and get string value":
    let tf = newNSTextField()
    setStringValue(tf, "test value")
    check stringValue(tf) == "test value"
    release(tf)

  test "create editable text field":
    let tf = newNSTextField()
    check not tf.isNil
    release(tf)

suite "AppKit - NSButton":
  test "create button with title":
    let btn = newNSButton("Click Me")
    check not btn.isNil
    check buttonTitle(btn) == "Click Me"
    release(btn)

  test "set button title":
    let btn = newNSButton()
    setButtonTitle(btn, "OK")
    check buttonTitle(btn) == "OK"
    release(btn)

suite "AppKit - NSStackView":
  test "create vertical stack":
    let stack = newNSStackView(1)
    check not stack.isNil
    release(stack)

  test "addArrangedSubview":
    let stack = newNSStackView()
    let v1 = allocInit("NSView")
    let v2 = allocInit("NSView")
    addArrangedSubview(stack, v1)
    addArrangedSubview(stack, v2)
    check arrangedSubviewCount(stack) == 2
    release(stack)

  test "removeArrangedSubview":
    let stack = newNSStackView()
    let v1 = allocInit("NSView")
    addArrangedSubview(stack, v1)
    check arrangedSubviewCount(stack) == 1
    removeArrangedSubview(stack, v1)
    removeFromSuperview(v1)
    check arrangedSubviewCount(stack) == 0
    release(stack)
