## UIKitRenderer — implements IsoNim's RendererBackend backed by UIKit.
##
## Maps HTML-like tags to native UIKit views, CSS-like styles to view
## properties, and events to UITapGestureRecognizer callbacks.
## Minimal implementation sufficient for branded_ui.nim.

import std/[tables, strutils, hashes]
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/uikit/views
import isonim/theming/theme
import isonim/layout/layout_engine

export objc_runtime.Id

proc hash*(e: Id): Hash =
  ## Hash for Id (distinct pointer) — needed for reconcileArrays tables.
  hash(cast[pointer](e))

type
  UIKitRenderer* = object
    ## Renderer backend that creates and manipulates UIKit views.
    ## When engine is non-nil, all element operations are also registered
    ## in a parallel Yoga layout tree for flexbox computation.
    engine*: LayoutEngine

  UIKitElement* = Id
    ## An element handle is just an ObjC object (UIView subclass).

# ===========================================================================
# Internal element metadata
# ===========================================================================

type
  UIElementKind = enum
    uekView       # UIView container
    uekLabel      # UILabel (text display)
    uekInput      # UITextField (editable text)
    uekText       # UILabel (text node from createTextNode)
    uekButton     # UIButton (system button)
    uekSwitch     # UISwitch (toggle)
    uekSegmented  # UISegmentedControl

  UIElementInfo = object
    kind: UIElementKind
    tag: string
    parent: UIKitElement
    children: seq[UIKitElement]
    attributes: Table[string, string]
    eventCallbacks: Table[string, int32]
    fontWeight: string     # "bold", "normal", etc.
    fontSize: float        # last set font-size (0 = not set)

var uiElements: Table[pointer, UIElementInfo]

proc uiInfo(e: UIKitElement): ptr UIElementInfo =
  let p = pointer(e)
  if p in uiElements:
    addr uiElements[p]
  else:
    nil

proc ensureUIInfo(e: UIKitElement; kind: UIElementKind; tag: string): ptr UIElementInfo =
  let p = pointer(e)
  if p notin uiElements:
    uiElements[p] = UIElementInfo(kind: kind, tag: tag, parent: UIKitElement(Id(nil)))
  addr uiElements[p]

# ===========================================================================
# Event callback bridge (shared mechanism, separate table from AppKit)
# ===========================================================================

var uiCallbackTable*: Table[int32, proc()]
var uiNextCallbackId*: int32 = 1

proc uiRegisterCallback*(handler: proc()): int32 =
  let id = uiNextCallbackId
  inc uiNextCallbackId
  uiCallbackTable[id] = handler
  id

proc uiResetCallbacks*() =
  uiCallbackTable.clear()
  uiNextCallbackId = 1

# Dynamic ObjC class for handling target-action callbacks (UIKit variant)
var uikitCallbackClass: Class

proc uikitCallbackAction(self: Id; cmd: Sel) {.cdecl.} =
  var rawId: pointer
  discard object_getInstanceVariable(self, "nimCallbackId".cstring, addr rawId)
  let cbId = cast[int32](cast[int](rawId))
  if cbId in uiCallbackTable:
    uiCallbackTable[cbId]()

proc ensureUIKitCallbackClass() =
  if uikitCallbackClass.isNil:
    uikitCallbackClass = objc_allocateClassPair(cls("NSObject"),
      "NimUIKitCallbackTarget".cstring)
    discard class_addIvar(uikitCallbackClass, "nimCallbackId".cstring,
                          csize_t(sizeof(pointer)), uint8(3), "^v".cstring)
    discard class_addMethod(uikitCallbackClass, sel("callbackAction:"),
                            cast[Imp](uikitCallbackAction), "v@:@".cstring)
    objc_registerClassPair(uikitCallbackClass)

proc newUIKitCallbackTarget*(callbackId: int32): Id =
  ensureUIKitCallbackClass()
  result = msgSend(msgSend(Id(uikitCallbackClass), sel("alloc")), sel("init"))
  discard object_setInstanceVariable(result, "nimCallbackId".cstring,
                                      cast[pointer](cast[int](callbackId)))

# ===========================================================================
# Color parsing (duplicated from renderer.nim to avoid AppKit dependency)
# ===========================================================================

proc parseHexColor(hex: string): tuple[r, g, b, a: cdouble] =
  ## Parse a hex color string like "#RRGGBB" or "#RRGGBBAA".
  var h = hex.strip()
  if h.len > 0 and h[0] == '#':
    h = h[1..^1]
  if h.len == 6:
    let r = parseHexInt(h[0..1])
    let g = parseHexInt(h[2..3])
    let b = parseHexInt(h[4..5])
    result = (cdouble(r) / 255.0, cdouble(g) / 255.0, cdouble(b) / 255.0, 1.0)
  elif h.len == 8:
    let r = parseHexInt(h[0..1])
    let g = parseHexInt(h[2..3])
    let b = parseHexInt(h[4..5])
    let a = parseHexInt(h[6..7])
    result = (cdouble(r) / 255.0, cdouble(g) / 255.0, cdouble(b) / 255.0, cdouble(a) / 255.0)
  elif h == "transparent":
    result = (0.0, 0.0, 0.0, 0.0)
  else:
    result = (0.0, 0.0, 0.0, 1.0)

proc resolveStyleValue(prop, value: string): string =
  case prop
  of "background-color", "color", "border-color":
    let themed = themeColor(value)
    if themed != "": themed else: value
  of "padding", "margin", "gap":
    let sp = themeSpacing(value)
    if sp >= 0: $sp else: value
  of "border-radius":
    let r = themeRadius(value)
    if r >= 0: $r else: value
  else:
    value

# ===========================================================================
# Style application
# ===========================================================================

proc applyUIStyle(elem: UIKitElement; prop, value: string) =
  let resolved = resolveStyleValue(prop, value)
  let view = Id(elem)
  let inf = uiInfo(elem)

  case prop
  of "display":
    if value == "none":
      uiSetHidden(view, true)
    else:
      uiSetHidden(view, false)
  of "background-color":
    if resolved != "" and resolved != "transparent":
      let (r, g, b, a) = parseHexColor(resolved)
      uiSetBackgroundColor(view, r, g, b, a)
    elif resolved == "transparent":
      uiSetBackgroundColor(view, 0, 0, 0, 0)
  of "color":
    if inf != nil and inf.kind in {uekLabel, uekText, uekInput}:
      let (r, g, b, a) = parseHexColor(resolved)
      uiSetTextColor(view, r, g, b, a)
    elif inf != nil and inf.kind == uekButton:
      let (r, g, b, a) = parseHexColor(resolved)
      uiButtonSetTitleColor(view, r, g, b, a)
  of "font-size":
    if inf != nil and inf.kind in {uekLabel, uekText, uekInput}:
      let size = try: parseFloat(value.replace("px", "").strip()) except: 17.0
      inf.fontSize = size
      if inf.fontWeight == "bold":
        uiSetBoldFontSize(view, size)
      else:
        uiSetFontSize(view, size)
    elif inf != nil and inf.kind == uekButton:
      let size = try: parseFloat(value.replace("px", "").strip()) except: 17.0
      inf.fontSize = size
      uiButtonSetFontSize(view, size)
  of "font-weight":
    if inf != nil and inf.kind in {uekLabel, uekText, uekInput}:
      inf.fontWeight = value
      if inf.fontSize > 0:
        if value == "bold":
          uiSetBoldFontSize(view, inf.fontSize)
        else:
          uiSetFontSize(view, inf.fontSize)
  of "border-radius":
    let radius = try: parseFloat(resolved.replace("px", "").strip()) except: 0.0
    uiSetCornerRadius(view, radius)
    uiSetClipsToBounds(view, true)
  of "border-color":
    let (r, g, b, a) = parseHexColor(resolved)
    uiSetBorderColor(view, r, g, b, a)
  of "border-width":
    let width = try: parseFloat(value.replace("px", "").strip()) except: 1.0
    uiSetBorderWidth(view, width)
  of "text-align":
    if inf != nil and inf.kind in {uekLabel, uekText}:
      let align: cint = case value
        of "center": 1
        of "right": 2
        of "justified": 3
        else: 0  # left
      uiSetTextAlignment(view, align)
  of "opacity":
    let alpha = try: parseFloat(value) except: 1.0
    uiSetAlpha(view, alpha)
  else:
    discard  # Layout properties (padding, flex, etc.) handled by Yoga

# ===========================================================================
# RendererBackend implementation
# ===========================================================================

proc createElement*(r: UIKitRenderer; tag: string): UIKitElement =
  case tag
  of "input":
    result = UIKitElement(uiTextFieldNew())
    discard ensureUIInfo(result, uekInput, tag)
  of "button":
    result = UIKitElement(uiButtonNew())
    discard ensureUIInfo(result, uekButton, tag)
  of "switch":
    result = UIKitElement(uiSwitchNew())
    discard ensureUIInfo(result, uekSwitch, tag)
  of "segmented":
    # Create a real UISegmentedControl — segments are set via the "segments" attribute
    result = UIKitElement(uiSegmentedControlNew(@[]))
    discard ensureUIInfo(result, uekSegmented, tag)
  of "span", "p", "label", "h1", "h2", "h3", "h4", "h5", "h6":
    result = UIKitElement(uiLabelNew())
    let inf = ensureUIInfo(result, uekLabel, tag)
    # h1 gets bold large font by default
    if tag == "h1":
      inf.fontSize = 28.0
      inf.fontWeight = "bold"
      uiSetBoldFontSize(Id(result), 28.0)
  else:
    # Everything else is a UIView container
    result = UIKitElement(uiViewNew())
    discard ensureUIInfo(result, uekView, tag)
  # Register in layout engine if present
  if r.engine != nil:
    discard r.engine.registerNode(cast[int64](cast[pointer](result)))

proc createTextNode*(r: UIKitRenderer; text: string): UIKitElement =
  result = UIKitElement(uiLabelNew(text))
  discard ensureUIInfo(result, uekText, "#text")
  if r.engine != nil:
    discard r.engine.registerNode(cast[int64](cast[pointer](result)))

proc appendChild*(r: UIKitRenderer; parent, child: UIKitElement) =
  uiAddSubview(Id(parent), Id(child))
  let pi = uiInfo(parent)
  let ci = uiInfo(child)
  if pi != nil:
    pi.children.add(child)
  if ci != nil:
    ci.parent = parent
  if r.engine != nil:
    r.engine.addChild(cast[int64](cast[pointer](parent)),
                       cast[int64](cast[pointer](child)))

proc insertBefore*(r: UIKitRenderer; parent, child, reference: UIKitElement) =
  let pi = uiInfo(parent)
  if pi != nil:
    var idx = pi.children.len
    for i, c in pi.children:
      if pointer(c) == pointer(reference):
        idx = i
        break
    pi.children.insert(child, idx)
    let ci = uiInfo(child)
    if ci != nil:
      ci.parent = parent
  uiAddSubview(Id(parent), Id(child))
  if r.engine != nil:
    r.engine.insertChildBefore(cast[int64](cast[pointer](parent)),
                                cast[int64](cast[pointer](child)),
                                cast[int64](cast[pointer](reference)))

proc removeChild*(r: UIKitRenderer; parent, child: UIKitElement) =
  uiRemoveFromSuperview(Id(child))
  let pi = uiInfo(parent)
  if pi != nil:
    for i, c in pi.children:
      if pointer(c) == pointer(child):
        pi.children.delete(i)
        break
  let ci = uiInfo(child)
  if ci != nil:
    ci.parent = UIKitElement(Id(nil))
  if r.engine != nil:
    r.engine.removeChild(cast[int64](cast[pointer](parent)),
                          cast[int64](cast[pointer](child)))

proc setAttribute*(r: UIKitRenderer; node: UIKitElement; name, value: string) =
  let inf = uiInfo(node)
  if inf != nil:
    inf.attributes[name] = value
  case name
  of "placeholder":
    if inf != nil and inf.kind == uekInput:
      uiSetPlaceholder(Id(node), value)
  of "value":
    if inf != nil and inf.kind == uekInput:
      uiTextFieldSetText(Id(node), value)
    elif inf != nil and inf.kind in {uekLabel, uekText}:
      uiLabelSetText(Id(node), value)
  of "checked":
    if inf != nil and inf.kind == uekSwitch:
      uiSwitchSetOn(Id(node), value == "true")
  of "enabled":
    if inf != nil and inf.kind == uekButton:
      uiButtonSetEnabled(Id(node), value != "false")
  of "selected":
    discard  # Visual selection state handled by style
  of "segments":
    if inf != nil and inf.kind == uekSegmented:
      # Comma-separated segment labels
      var items: seq[string]
      for s in value.split(","):
        items.add(s.strip())
      uiSegmentedControlSetSegments(Id(node), items)
  of "selectedIndex":
    if inf != nil and inf.kind == uekSegmented:
      let idx = try: parseInt(value) except: 0
      uiSegmentedControlSetSelectedIndex(Id(node), cint(idx))
  else:
    discard

proc removeAttribute*(r: UIKitRenderer; node: UIKitElement; name: string) =
  let inf = uiInfo(node)
  if inf != nil:
    inf.attributes.del(name)

proc getAttribute*(r: UIKitRenderer; node: UIKitElement; name: string): string =
  let inf = uiInfo(node)
  if inf != nil and inf.kind == uekSegmented and name == "selectedIndex":
    return $uiSegmentedControlGetSelectedIndex(Id(node))
  if inf != nil and name in inf.attributes:
    inf.attributes[name]
  else:
    ""

proc setTextContent*(r: UIKitRenderer; node: UIKitElement; text: string) =
  let inf = uiInfo(node)
  if inf != nil and inf.kind in {uekLabel, uekText}:
    uiLabelSetText(Id(node), text)
  elif inf != nil and inf.kind == uekInput:
    uiTextFieldSetText(Id(node), text)
  elif inf != nil and inf.kind == uekButton:
    uiButtonSetTitle(Id(node), text)

proc textContent*(r: UIKitRenderer; node: UIKitElement): string =
  let inf = uiInfo(node)
  if inf != nil and inf.kind in {uekLabel, uekText}:
    uiLabelGetText(Id(node))
  elif inf != nil and inf.kind == uekInput:
    uiTextFieldGetText(Id(node))
  elif inf != nil and inf.kind == uekButton:
    uiButtonGetTitle(Id(node))
  else:
    ""

proc setStyle*(r: UIKitRenderer; node: UIKitElement; prop, value: string) =
  applyUIStyle(node, prop, value)
  if r.engine != nil:
    r.engine.setLayoutStyle(cast[int64](cast[pointer](node)), prop, value)

proc addEventListener*(r: UIKitRenderer; node: UIKitElement; event: string;
                        handler: proc()) =
  let callbackId = uiRegisterCallback(handler)
  let target = newUIKitCallbackTarget(callbackId)
  let inf = uiInfo(node)
  if inf != nil:
    inf.eventCallbacks[event] = callbackId

  case event
  of "click":
    if inf != nil and inf.kind == uekButton:
      # UIButton uses target-action (TouchUpInside)
      uiButtonAddTarget(Id(node), target, sel("callbackAction:"))
    elif inf != nil and inf.kind == uekSwitch:
      # UISwitch uses target-action (ValueChanged)
      uiSwitchAddTarget(Id(node), target, sel("callbackAction:"))
    elif inf != nil and inf.kind == uekSegmented:
      # UISegmentedControl uses target-action (ValueChanged)
      uiSegmentedControlAddTarget(Id(node), target, sel("callbackAction:"))
    else:
      # UITapGestureRecognizer for generic views
      uiAddTapGesture(Id(node), target, sel("callbackAction:"))
  else:
    discard

proc firstChild*(r: UIKitRenderer; node: UIKitElement): UIKitElement =
  let inf = uiInfo(node)
  if inf != nil and inf.children.len > 0:
    result = inf.children[0]
  else:
    result = UIKitElement(Id(nil))

proc nextSibling*(r: UIKitRenderer; node: UIKitElement): UIKitElement =
  let inf = uiInfo(node)
  if inf != nil and not inf.parent.isNil:
    let pi = uiInfo(inf.parent)
    if pi != nil:
      for i, c in pi.children:
        if pointer(c) == pointer(node) and i + 1 < pi.children.len:
          return pi.children[i + 1]
  result = UIKitElement(Id(nil))

proc parentNode*(r: UIKitRenderer; node: UIKitElement): UIKitElement =
  let inf = uiInfo(node)
  if inf != nil:
    result = inf.parent
  else:
    result = UIKitElement(Id(nil))

# ===========================================================================
# Testing / lifecycle helpers
# ===========================================================================

proc resetUITree*() =
  ## Reset all element tracking.
  uiElements.clear()
  uiResetCallbacks()

proc fireEvent*(r: UIKitRenderer; node: UIKitElement; event: string) =
  ## Simulate an event dispatch (for testing).
  let inf = uiInfo(node)
  if inf != nil and event in inf.eventCallbacks:
    let cbId = inf.eventCallbacks[event]
    if cbId in uiCallbackTable:
      uiCallbackTable[cbId]()

# ===========================================================================
# Compile-time conformance check
# ===========================================================================

static:
  var r: UIKitRenderer
  var e: UIKitElement
  assert compiles(r.createElement(""))
  assert compiles(r.createTextNode(""))
  assert compiles(r.appendChild(e, e))
  assert compiles(r.insertBefore(e, e, e))
  assert compiles(r.removeChild(e, e))
  assert compiles(r.setAttribute(e, "", ""))
  assert compiles(r.removeAttribute(e, ""))
  assert compiles(r.setTextContent(e, ""))
  assert compiles(r.setStyle(e, "", ""))
  assert compiles(r.addEventListener(e, "", proc() = discard))
  assert compiles(r.firstChild(e))
  assert compiles(r.nextSibling(e))
  assert compiles(r.parentNode(e))
