## Tests for CocoaRenderer — RendererBackend implementation (M2).

import unittest
import std/strutils
import isonim_cocoa/objc_runtime
import isonim_cocoa/appkit/views
import isonim_cocoa/renderer

suite "CocoaRenderer - Element Creation":
  setup:
    resetTree()

  test "createElement returns non-nil":
    let r = CocoaRenderer()
    let node = r.createElement("div")
    check not Id(node).isNil

  test "createElement maps div to NSView":
    let r = CocoaRenderer()
    let node = r.createElement("div")
    let c = object_getClass(Id(node))
    check $class_getName(c) == "NSView"

  test "createElement maps button to NSButton":
    let r = CocoaRenderer()
    let node = r.createElement("button")
    let className = $class_getName(object_getClass(Id(node)))
    check className.contains("Button")

  test "createElement maps input to NSTextField":
    let r = CocoaRenderer()
    let node = r.createElement("input")
    let className = $class_getName(object_getClass(Id(node)))
    check className.contains("TextField")

  test "createElement maps span to NSTextField":
    let r = CocoaRenderer()
    let node = r.createElement("span")
    let className = $class_getName(object_getClass(Id(node)))
    check className.contains("TextField")

  test "createElement maps ul to NSStackView":
    let r = CocoaRenderer()
    let node = r.createElement("ul")
    let className = $class_getName(object_getClass(Id(node)))
    check className.contains("StackView")

  test "createTextNode returns label with text":
    let r = CocoaRenderer()
    let node = r.createTextNode("hello")
    check r.textContent(node) == "hello"

suite "CocoaRenderer - Tree Operations":
  setup:
    resetTree()

  test "appendChild":
    let r = CocoaRenderer()
    let parent = r.createElement("div")
    let child = r.createElement("span")
    r.appendChild(parent, child)
    check r.childCount(parent) == 1

  test "appendChild multiple":
    let r = CocoaRenderer()
    let parent = r.createElement("div")
    let c1 = r.createElement("span")
    let c2 = r.createElement("p")
    let c3 = r.createElement("button")
    r.appendChild(parent, c1)
    r.appendChild(parent, c2)
    r.appendChild(parent, c3)
    check r.childCount(parent) == 3

  test "removeChild":
    let r = CocoaRenderer()
    let parent = r.createElement("div")
    let child = r.createElement("span")
    r.appendChild(parent, child)
    check r.childCount(parent) == 1
    r.removeChild(parent, child)
    check r.childCount(parent) == 0

  test "firstChild":
    let r = CocoaRenderer()
    let parent = r.createElement("div")
    let c1 = r.createElement("span")
    let c2 = r.createElement("p")
    r.appendChild(parent, c1)
    r.appendChild(parent, c2)
    check pointer(r.firstChild(parent)) == pointer(c1)

  test "nextSibling":
    let r = CocoaRenderer()
    let parent = r.createElement("div")
    let c1 = r.createElement("span")
    let c2 = r.createElement("p")
    r.appendChild(parent, c1)
    r.appendChild(parent, c2)
    check pointer(r.nextSibling(c1)) == pointer(c2)
    check Id(r.nextSibling(c2)).isNil

  test "parentNode":
    let r = CocoaRenderer()
    let parent = r.createElement("div")
    let child = r.createElement("span")
    r.appendChild(parent, child)
    check pointer(r.parentNode(child)) == pointer(parent)

  test "insertBefore":
    let r = CocoaRenderer()
    let parent = r.createElement("div")
    let c1 = r.createElement("span")
    let c3 = r.createElement("p")
    r.appendChild(parent, c1)
    r.appendChild(parent, c3)

    let c2 = r.createElement("label")
    r.insertBefore(parent, c2, c3)

    check r.childCount(parent) == 3
    check pointer(r.firstChild(parent)) == pointer(c1)
    check pointer(r.nextSibling(c1)) == pointer(c2)
    check pointer(r.nextSibling(c2)) == pointer(c3)

suite "CocoaRenderer - Text Content":
  setup:
    resetTree()

  test "setTextContent on text node":
    let r = CocoaRenderer()
    let node = r.createTextNode("before")
    check r.textContent(node) == "before"
    r.setTextContent(node, "after")
    check r.textContent(node) == "after"

  test "setTextContent on label element":
    let r = CocoaRenderer()
    let node = r.createElement("span")
    r.setTextContent(node, "hello")
    check r.textContent(node) == "hello"

  test "setTextContent on button":
    let r = CocoaRenderer()
    let node = r.createElement("button")
    r.setTextContent(node, "Click Me")
    check r.textContent(node) == "Click Me"

suite "CocoaRenderer - Attributes":
  setup:
    resetTree()

  test "setAttribute disabled":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    r.setAttribute(btn, "disabled", "true")
    check not msgSendBool(Id(btn), sel("isEnabled"))

  test "removeAttribute disabled":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    r.setAttribute(btn, "disabled", "true")
    r.removeAttribute(btn, "disabled")
    check msgSendBool(Id(btn), sel("isEnabled"))

  test "setAttribute hidden":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setAttribute(view, "hidden", "true")
    check isHidden(Id(view))

  test "setAttribute value on input":
    let r = CocoaRenderer()
    let input = r.createElement("input")
    r.setAttribute(input, "value", "test text")
    check r.textContent(input) == "test text"

suite "CocoaRenderer - Styles":
  setup:
    resetTree()

  test "setStyle display none hides view":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "display", "none")
    check isHidden(Id(view))

  test "setStyle display block shows view":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    setHidden(Id(view), true)
    r.setStyle(view, "display", "block")
    check not isHidden(Id(view))

  test "setStyle background-color":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    # Should not crash
    r.setStyle(view, "background-color", "#FF0000")

  test "setStyle font-size":
    let r = CocoaRenderer()
    let label = r.createElement("span")
    r.setStyle(label, "font-size", "18px")
    # Should not crash

  test "setStyle border-radius":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "border-radius", "8px")
    # Should not crash

  test "setStyle opacity":
    let r = CocoaRenderer()
    let view = r.createElement("div")
    r.setStyle(view, "opacity", "0.5")
    # Should not crash

suite "CocoaRenderer - Events":
  setup:
    resetTree()

  test "addEventListener and fireEvent":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    var clicked = false
    r.addEventListener(btn, "click", proc() = clicked = true)
    check not clicked
    r.fireEvent(btn, "click")
    check clicked

  test "multiple event listeners":
    let r = CocoaRenderer()
    let btn = r.createElement("button")
    var count = 0
    r.addEventListener(btn, "click", proc() = inc count)
    r.fireEvent(btn, "click")
    r.fireEvent(btn, "click")
    check count == 2

  test "click on non-button view":
    let r = CocoaRenderer()
    let container = r.createElement("div")
    var clicked = false
    r.addEventListener(container, "click", proc() = clicked = true)
    r.fireEvent(container, "click")
    check clicked

suite "CocoaRenderer - Integration":
  setup:
    resetTree()

  test "build a counter UI":
    let r = CocoaRenderer()
    let container = r.createElement("div")
    let label = r.createTextNode("Count: 0")
    let incBtn = r.createElement("button")
    r.setTextContent(incBtn, "+")

    r.appendChild(container, label)
    r.appendChild(container, incBtn)

    check r.childCount(container) == 2
    check r.textContent(label) == "Count: 0"
    check r.textContent(incBtn) == "+"

    var count = 0
    r.addEventListener(incBtn, "click", proc() =
      inc count
      r.setTextContent(label, "Count: " & $count)
    )

    r.fireEvent(incBtn, "click")
    check r.textContent(label) == "Count: 1"

    r.fireEvent(incBtn, "click")
    r.fireEvent(incBtn, "click")
    check r.textContent(label) == "Count: 3"

  test "build a task list":
    let r = CocoaRenderer()
    let list = r.createElement("ul")

    for i in 1..3:
      let item = r.createElement("li")
      let text = r.createTextNode("Task " & $i)
      r.appendChild(item, text)
      r.appendChild(list, item)

    check r.childCount(list) == 3

    # Remove middle task
    let middle = r.nextSibling(r.firstChild(list))
    r.removeChild(list, middle)
    check r.childCount(list) == 2
