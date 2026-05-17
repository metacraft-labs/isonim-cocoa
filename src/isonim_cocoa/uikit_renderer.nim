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
    explicitWidth: bool    # true once a non-zero width style is pushed
    explicitHeight: bool   # true once a non-zero height style is pushed
    intrinsicWidth: float  # last text-measured width (0 = none)
    intrinsicHeight: float # last text-measured height (0 = none)

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
# Text-intrinsic sizing
# ===========================================================================

proc refreshTextIntrinsicSize*(r: UIKitRenderer; elem: UIKitElement) =
  ## Re-measure a label / text / button view and push the resulting
  ## intrinsic size into the Yoga layout engine as `min-width` and
  ## `min-height` constraints. Without this, Yoga has no measure
  ## callback for UILabel and resolves every text view to 0x0, which
  ## then gets skipped by the iOS `applyLayout` frame-flush loop
  ## (which requires width > 0 and height > 0). The result on the
  ## device is invisible text — the bug Wave J left behind for the
  ## settings demo.
  ##
  ## We push `min-width` / `min-height` (rather than fixed `width` /
  ## `height`) so user-supplied explicit sizes still win. Cross-axis
  ## stretch (Yoga's default `align-items: stretch`) keeps labels
  ## filling their parent column horizontally even when the measured
  ## width is small.
  if r.engine == nil: return
  let inf = uiInfo(elem)
  if inf == nil: return
  if inf.kind notin {uekLabel, uekText, uekButton}: return
  # Generous upper bound so wrapping doesn't kick in during measure;
  # parent flex will still constrain the painted frame.
  let measured =
    case inf.kind
    of uekLabel, uekText: uiLabelSizeThatFits(Id(elem), 10000.0, 10000.0)
    of uekButton: uiButtonSizeThatFits(Id(elem), 10000.0, 10000.0)
    else: CGSize(width: 0, height: 0)
  let w = float(measured.width)
  let h = float(measured.height)
  inf.intrinsicWidth = w
  inf.intrinsicHeight = h
  let handle = cast[int64](cast[pointer](elem))
  if not inf.explicitWidth and w > 0:
    r.engine.setLayoutStyle(handle, "min-width", $w)
  if not inf.explicitHeight and h > 0:
    r.engine.setLayoutStyle(handle, "min-height", $h)

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
    if inf != nil and inf.kind == uekSegmented:
      # For UISegmentedControl, route background-color to the selected
      # segment's tint colour (-setSelectedSegmentTintColor:). The
      # control's own track colour is system-managed and styling it
      # directly creates the opposite of what the iOS HIG expects;
      # what readers actually want when they say "background colour of
      # the segmented" is the lifted pill behind the active option,
      # which under iOS dark mode needs an explicit darker fill so it
      # stands out against the white track on the demo's light surface.
      if resolved != "" and resolved != "transparent":
        let (r, g, b, a) = parseHexColor(resolved)
        uiSegmentedControlSetSelectedTintColor(view, r, g, b, a)
    elif resolved != "" and resolved != "transparent":
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
    r.refreshTextIntrinsicSize(node)
  elif inf != nil and inf.kind == uekInput:
    uiTextFieldSetText(Id(node), text)
  elif inf != nil and inf.kind == uekButton:
    uiButtonSetTitle(Id(node), text)
    r.refreshTextIntrinsicSize(node)

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

proc parseDimensionFast(value: string): float =
  ## Strip ``px`` / ``dp`` units and parse the remainder as a float,
  ## returning 0 for anything non-numeric. Same fast-path guard as
  ## `layout_engine.parseLayoutFloat` so the ARM64 release-build
  ## ValueError leak that motivated Wave J's `parseLayoutFloat`
  ## refactor cannot bite the renderer either.
  let stripped = value.replace("px", "").replace("dp", "").strip()
  if stripped.len == 0: return 0.0
  let first = stripped[0]
  if first notin {'0'..'9', '-', '+', '.'}: return 0.0
  try: parseFloat(stripped) except ValueError: 0.0

proc setStyle*(r: UIKitRenderer; node: UIKitElement; prop, value: string) =
  applyUIStyle(node, prop, value)
  if r.engine != nil:
    r.engine.setLayoutStyle(cast[int64](cast[pointer](node)), prop, value)
  # Track whether the leaf has pushed an explicit width / height. The
  # text-intrinsic measure pass only seeds `min-width` / `min-height`
  # when the leaf hasn't already set a hard size, so explicit sizing
  # (e.g. the number-stepper buttons' 40x40 frame) always wins.
  let inf = uiInfo(node)
  if inf != nil:
    case prop
    of "width":
      if parseDimensionFast(value) > 0: inf.explicitWidth = true
    of "height":
      if parseDimensionFast(value) > 0: inf.explicitHeight = true
    of "font-size", "font-weight":
      # The new font may have changed the text's natural size; remeasure.
      r.refreshTextIntrinsicSize(node)
    else:
      discard

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

proc childCount*(r: UIKitRenderer; node: UIKitElement): int =
  ## Number of children currently parented under `node`. Required by
  ## the settings_app shell's `createRenderEffect` for the inline
  ## accordion bookkeeping (mirror of `CocoaRenderer.childCount`).
  let inf = uiInfo(node)
  if inf != nil: inf.children.len
  else: 0

proc nthChild*(r: UIKitRenderer; node: UIKitElement; index: int): UIKitElement =
  ## Return the nth child of a node, or a nil sentinel when out of
  ## bounds. Used by the settings shell + `choiceLeaf` to walk the
  ## select-options sub-tree (mirror of `CocoaRenderer.nthChild`).
  let inf = uiInfo(node)
  if inf != nil and index >= 0 and index < inf.children.len:
    inf.children[index]
  else:
    UIKitElement(Id(nil))

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
