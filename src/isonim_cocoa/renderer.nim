## CocoaRenderer — implements IsoNim's RendererBackend backed by AppKit/UIKit.
##
## Maps HTML-like tags to native Cocoa views, CSS-like styles to view
## properties, and events to target-action / gesture recognizer callbacks.
## Uses the ObjC runtime's C ABI directly from Nim — no Rust shim needed.

import std/[tables, strutils]
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/autolayout
import isonim_cocoa/appkit/scrollview
import isonim_cocoa/appkit/tableview
import isonim_cocoa/appkit/textcontrols

export objc_runtime.Id

type
  CocoaRenderer* = object
    ## Renderer backend that creates and manipulates AppKit views.

  CocoaElement* = Id
    ## An element handle is just an ObjC object (NSView subclass).

# ===========================================================================
# Internal element metadata
# ===========================================================================
# We track parent-child relationships and element metadata in Nim-side tables
# since NSView's subview model doesn't map 1:1 to our virtual tree
# (e.g., text nodes need special handling).

type
  ElementKind = enum
    ekView       # NSView container
    ekText       # NSTextField in label mode (text node)
    ekButton     # NSButton
    ekInput      # NSTextField in editable mode
    ekStack      # NSStackView
    ekImage      # NSImageView
    ekScroll     # NSScrollView
    ekVirtualList # NSTableView
    ekLabel      # NSTextField label (for span, p, h1, etc.)
    ekTextArea   # NSTextView (in NSScrollView)
    ekSearch     # NSSearchField
    ekSecureInput # NSSecureTextField

  ElementInfo = object
    kind: ElementKind
    tag: string
    parent: CocoaElement
    children: seq[CocoaElement]
    attributes: Table[string, string]     # attribute name -> value
    eventCallbacks: Table[string, int32]  # event name -> callback ID

var elements: Table[pointer, ElementInfo]

proc info(e: CocoaElement): ptr ElementInfo =
  let p = pointer(e)
  if p in elements:
    addr elements[p]
  else:
    nil

proc ensureInfo(e: CocoaElement; kind: ElementKind; tag: string): ptr ElementInfo =
  let p = pointer(e)
  if p notin elements:
    elements[p] = ElementInfo(kind: kind, tag: tag, parent: CocoaElement(Id(nil)))
  addr elements[p]

# ===========================================================================
# Tag mapping: HTML tags -> AppKit view types
# ===========================================================================

const tagMap = {
  # Generic containers -> NSView
  "div": ekView, "section": ekView, "article": ekView, "main": ekView,
  "aside": ekView, "nav": ekView, "header": ekView, "footer": ekView,
  "form": ekView, "details": ekView, "fieldset": ekView,

  # Text elements -> NSTextField (label mode)
  "span": ekLabel, "p": ekLabel, "label": ekLabel,
  "h1": ekLabel, "h2": ekLabel, "h3": ekLabel,
  "h4": ekLabel, "h5": ekLabel, "h6": ekLabel,

  # Interactive
  "button": ekButton,
  "input": ekInput,

  # Lists -> NSStackView (vertical)
  "ul": ekStack, "ol": ekStack,
  "li": ekView,

  # Media
  "img": ekImage,

  # Scroll & virtualization
  "scroll-view": ekScroll,
  "virtual-list": ekVirtualList,

  # Rich text & search
  "textarea": ekTextArea,
  "search": ekSearch,
}.toTable

proc createNativeView(kind: ElementKind; tag: string): CocoaElement =
  case kind
  of ekView:
    result = CocoaElement(allocInit("NSView"))
    setWantsLayer(Id(result))
  of ekText, ekLabel:
    result = CocoaElement(newNSLabel())
    setWantsLayer(Id(result))
  of ekButton:
    result = CocoaElement(newNSButton())
  of ekInput:
    result = CocoaElement(newNSTextField())
  of ekStack:
    result = CocoaElement(newNSStackView(1))  # vertical by default
    setWantsLayer(Id(result))
  of ekImage:
    result = CocoaElement(newNSImageView())
    setWantsLayer(Id(result))
  of ekScroll:
    result = CocoaElement(newNSScrollView())
  of ekTextArea:
    result = CocoaElement(newNSTextView(300, 100))
    setWantsLayer(Id(result))
  of ekSearch:
    result = CocoaElement(newNSSearchField())
    setWantsLayer(Id(result))
  of ekSecureInput:
    result = CocoaElement(newNSSecureTextField())
    setWantsLayer(Id(result))
  of ekVirtualList:
    # Create a basic NSTableView with no-op datasource; real datasource
    # should be attached via setAttribute or direct API.
    let (table, _) = newNSTableView(
      proc(): int = 0,
      proc(row: int): Id = NilId
    )
    result = CocoaElement(table)

# ===========================================================================
# Event callback bridge
# ===========================================================================

var callbackTable*: Table[int32, proc()]
var nextCallbackId*: int32 = 1

proc registerCallback*(handler: proc()): int32 =
  let id = nextCallbackId
  inc nextCallbackId
  callbackTable[id] = handler
  id

proc removeCallback*(id: int32) =
  callbackTable.del(id)

proc resetCallbacks*() =
  callbackTable.clear()
  nextCallbackId = 1

# Dynamic ObjC class for handling target-action callbacks
var nimCallbackClass: Class

proc callbackAction(self: Id; cmd: Sel) {.cdecl.} =
  ## ObjC method called when a button is clicked or action fires.
  ## Reads the callback ID from the "nimCallbackId" ivar and dispatches.
  var rawId: pointer
  discard object_getInstanceVariable(self, "nimCallbackId".cstring, addr rawId)
  let cbId = cast[int32](cast[int](rawId))
  if cbId in callbackTable:
    callbackTable[cbId]()

proc ensureCallbackClass() =
  if nimCallbackClass.isNil:
    nimCallbackClass = objc_allocateClassPair(cls("NSObject"), "NimCallbackTarget".cstring)
    discard class_addIvar(nimCallbackClass, "nimCallbackId".cstring,
                          csize_t(sizeof(pointer)), uint8(3), "^v".cstring)
    discard class_addMethod(nimCallbackClass, sel("callbackAction:"),
                            cast[Imp](callbackAction), "v@:@".cstring)
    objc_registerClassPair(nimCallbackClass)

proc newCallbackTarget(callbackId: int32): Id =
  ## Create an ObjC object that dispatches to the given callback ID.
  ensureCallbackClass()
  result = msgSend(msgSend(Id(nimCallbackClass), sel("alloc")), sel("init"))
  discard object_setInstanceVariable(result, "nimCallbackId".cstring,
                                      cast[pointer](cast[int](callbackId)))

# ===========================================================================
# Style property mapping
# ===========================================================================

proc applyStyle(elem: CocoaElement; prop, value: string) =
  let view = Id(elem)
  let inf = info(elem)
  let isStack = inf != nil and inf.kind == ekStack
  case prop
  of "display":
    if value == "none":
      setHidden(view, true)
    else:
      setHidden(view, false)
  of "width", "height":
    disableAutoresizingMask(view)
    applyLayoutStyle(view, prop, value, isStack)
  of "padding":
    if isStack:
      applyLayoutStyle(view, prop, value, isStack = true)
  of "align-items":
    if isStack:
      applyLayoutStyle(view, prop, value, isStack = true)
  of "justify-content":
    if isStack:
      applyLayoutStyle(view, prop, value, isStack = true)
  of "gap":
    if isStack:
      applyLayoutStyle(view, prop, value, isStack = true)
  of "background-color":
    setWantsLayer(view)
    let (r, g, b, a) = parseHexColor(value)
    # Create CGColor and set on layer
    let colorSpace = msgSend(Id(cls("NSColorSpace")), sel("sRGBColorSpace"))
    # Use NSColor then get CGColor
    {.emit: """
    id nsColor = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
      (id)objc_getClass("NSColor"),
      sel_registerName("colorWithRed:green:blue:alpha:"),
      `r`, `g`, `b`, `a`);
    id layer = ((id(*)(id, SEL))objc_msgSend)(`view`, sel_registerName("layer"));
    if (layer) {
      void* cgColor = ((void*(*)(id, SEL))objc_msgSend)(nsColor, sel_registerName("CGColor"));
      ((void(*)(id, SEL, void*))objc_msgSend)(layer, sel_registerName("setBackgroundColor:"), cgColor);
    }
    """.}
  of "color":
    if inf != nil and inf.kind in {ekText, ekLabel, ekInput, ekSearch, ekSecureInput}:
      let (r, g, b, a) = parseHexColor(value)
      {.emit: """
      id nsColor = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
        (id)objc_getClass("NSColor"),
        sel_registerName("colorWithRed:green:blue:alpha:"),
        `r`, `g`, `b`, `a`);
      ((void(*)(id, SEL, id))objc_msgSend)(`view`, sel_registerName("setTextColor:"), nsColor);
      """.}
  of "font-size":
    if inf != nil and inf.kind in {ekText, ekLabel, ekInput, ekSearch, ekSecureInput}:
      let size = try: parseFloat(value.replace("px", "").strip()) except: 13.0
      setFontSize(view, size)
  of "flex-direction":
    if isStack:
      let horizontal = value in ["row", "row-reverse"]
      setStackOrientation(view, horizontal)
  of "opacity":
    let alpha = try: parseFloat(value) except: 1.0
    {.emit: """
    ((void(*)(id, SEL, double))objc_msgSend)(`view`, sel_registerName("setAlphaValue:"), `alpha`);
    """.}
  of "border-radius":
    setWantsLayer(view)
    let radius = try: parseFloat(value.replace("px", "").strip()) except: 0.0
    {.emit: """
    id layer = ((id(*)(id, SEL))objc_msgSend)(`view`, sel_registerName("layer"));
    if (layer) {
      ((void(*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setCornerRadius:"), `radius`);
    }
    """.}
  of "overflow":
    if inf != nil and inf.kind == ekScroll:
      case value
      of "hidden":
        setHasVerticalScroller(view, false)
        setHasHorizontalScroller(view, false)
      of "scroll", "auto":
        setHasVerticalScroller(view, true)
        setHasHorizontalScroller(view, true)
      of "scroll-y":
        setHasVerticalScroller(view, true)
        setHasHorizontalScroller(view, false)
      of "scroll-x":
        setHasVerticalScroller(view, false)
        setHasHorizontalScroller(view, true)
      else:
        discard
  else:
    discard  # Unknown style property — ignore

# ===========================================================================
# Attribute mapping
# ===========================================================================

proc applyAttribute(elem: CocoaElement; name, value: string) =
  let view = Id(elem)
  let inf = info(elem)
  case name
  of "disabled":
    setEnabled(view, value != "true" and value != "disabled" and value != "")
  of "placeholder":
    if inf != nil and inf.kind in {ekInput, ekSearch, ekSecureInput}:
      setPlaceholder(view, value)
  of "type":
    if inf != nil and inf.kind == ekInput and value == "password":
      # Convert to secure text field by tracking the type attribute.
      # The actual NSSecureTextField is created if needed.
      inf.kind = ekSecureInput
  of "value":
    if inf != nil and inf.kind in {ekInput, ekLabel, ekText, ekSearch, ekSecureInput}:
      setStringValue(view, value)
  of "hidden":
    setHidden(view, true)
  else:
    discard

proc removeAttributeImpl(elem: CocoaElement; name: string) =
  let view = Id(elem)
  case name
  of "disabled":
    setEnabled(view, true)
  of "hidden":
    setHidden(view, false)
  else:
    discard

# ===========================================================================
# RendererBackend — the 13 required procs
# ===========================================================================

proc createElement*(r: CocoaRenderer; tag: string): CocoaElement =
  let kind = tagMap.getOrDefault(tag, ekView)
  result = createNativeView(kind, tag)
  discard ensureInfo(result, kind, tag)

proc createTextNode*(r: CocoaRenderer; text: string): CocoaElement =
  result = CocoaElement(newNSLabel(text))
  discard ensureInfo(result, ekText, "#text")

proc appendChild*(r: CocoaRenderer; parent, child: CocoaElement) =
  addSubview(Id(parent), Id(child))
  let pi = info(parent)
  let ci = info(child)
  if pi != nil:
    pi.children.add(child)
  if ci != nil:
    ci.parent = parent

proc insertBefore*(r: CocoaRenderer; parent, child, reference: CocoaElement) =
  let pi = info(parent)
  if pi != nil:
    var idx = pi.children.len
    for i, c in pi.children:
      if pointer(c) == pointer(reference):
        idx = i
        break
    pi.children.insert(child, idx)
    let ci = info(child)
    if ci != nil:
      ci.parent = parent
  # Add to NSView hierarchy. We always append to the superview;
  # the Nim-side children seq is the authoritative ordering for
  # firstChild/nextSibling/parentNode traversal. The NSView subview
  # order only matters for visual z-ordering, not logical tree structure.
  addSubview(Id(parent), Id(child))

proc removeChild*(r: CocoaRenderer; parent, child: CocoaElement) =
  removeFromSuperview(Id(child))
  let pi = info(parent)
  if pi != nil:
    for i, c in pi.children:
      if pointer(c) == pointer(child):
        pi.children.delete(i)
        break
  let ci = info(child)
  if ci != nil:
    ci.parent = CocoaElement(Id(nil))

proc setAttribute*(r: CocoaRenderer; node: CocoaElement; name, value: string) =
  let inf = info(node)
  if inf != nil:
    inf.attributes[name] = value
  applyAttribute(node, name, value)

proc removeAttribute*(r: CocoaRenderer; node: CocoaElement; name: string) =
  let inf = info(node)
  if inf != nil:
    inf.attributes.del(name)
  removeAttributeImpl(node, name)

proc getAttribute*(r: CocoaRenderer; node: CocoaElement; name: string): string =
  ## Retrieve a previously-set attribute value by name.
  let inf = info(node)
  if inf != nil and name in inf.attributes:
    inf.attributes[name]
  else:
    ""

proc setTextContent*(r: CocoaRenderer; node: CocoaElement; text: string) =
  let inf = info(node)
  if inf != nil and inf.kind in {ekText, ekLabel, ekInput, ekSearch, ekSecureInput}:
    setStringValue(Id(node), text)
  elif inf != nil and inf.kind == ekButton:
    setButtonTitle(Id(node), text)
  elif inf != nil and inf.kind == ekTextArea:
    let tv = textViewFromScroll(Id(node))
    setTextViewString(tv, text)

proc setStyle*(r: CocoaRenderer; node: CocoaElement; prop, value: string) =
  applyStyle(node, prop, value)

proc addEventListener*(r: CocoaRenderer; node: CocoaElement; event: string;
                        handler: proc()) =
  let callbackId = registerCallback(handler)
  let target = newCallbackTarget(callbackId)
  let inf = info(node)
  if inf != nil:
    inf.eventCallbacks[event] = callbackId

  case event
  of "click":
    if inf != nil and inf.kind == ekButton:
      # NSButton target-action
      msgSendVoid(Id(node), sel("setTarget:"), target)
      msgSendVoid(Id(node), sel("setAction:"), Id(sel("callbackAction:")))
    else:
      # Use NSClickGestureRecognizer for non-button views
      let recognizer = msgSend(Id(cls("NSClickGestureRecognizer")), sel("alloc"))
      let initd = msgSend(recognizer, sel("initWithTarget:action:"),
                           target, Id(sel("callbackAction:")))
      msgSendVoid(Id(node), sel("addGestureRecognizer:"), initd)
  of "input", "change":
    # For NSTextField, delegate-based notification would be needed.
    # For now, store the callback for later integration.
    discard
  else:
    discard

proc firstChild*(r: CocoaRenderer; node: CocoaElement): CocoaElement =
  let inf = info(node)
  if inf != nil and inf.children.len > 0:
    result = inf.children[0]
  else:
    result = CocoaElement(Id(nil))

proc nextSibling*(r: CocoaRenderer; node: CocoaElement): CocoaElement =
  let inf = info(node)
  if inf != nil and not inf.parent.isNil:
    let pi = info(inf.parent)
    if pi != nil:
      for i, c in pi.children:
        if pointer(c) == pointer(node) and i + 1 < pi.children.len:
          return pi.children[i + 1]
  result = CocoaElement(Id(nil))

proc parentNode*(r: CocoaRenderer; node: CocoaElement): CocoaElement =
  let inf = info(node)
  if inf != nil:
    result = inf.parent
  else:
    result = CocoaElement(Id(nil))

# ===========================================================================
# Compile-time conformance check
# ===========================================================================

static:
  var r: CocoaRenderer
  var e: CocoaElement
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

# ===========================================================================
# Testing helpers
# ===========================================================================

proc childCount*(r: CocoaRenderer; node: CocoaElement): int =
  let inf = info(node)
  if inf != nil: inf.children.len
  else: 0

proc textContent*(r: CocoaRenderer; node: CocoaElement): string =
  let inf = info(node)
  if inf != nil and inf.kind in {ekText, ekLabel, ekInput, ekSearch, ekSecureInput}:
    stringValue(Id(node))
  elif inf != nil and inf.kind == ekButton:
    buttonTitle(Id(node))
  elif inf != nil and inf.kind == ekTextArea:
    textViewString(textViewFromScroll(Id(node)))
  else:
    ""

proc treeTextContent*(r: CocoaRenderer; node: CocoaElement): string =
  ## Recursively collect text content from a node and all descendants,
  ## matching MockRenderer's textContent semantics.
  let inf = info(node)
  if inf == nil:
    return ""
  # Leaf text/label nodes with no children: return their string value directly
  if inf.kind in {ekText, ekLabel, ekInput, ekSearch, ekSecureInput} and inf.children.len == 0:
    return stringValue(Id(node))
  if inf.kind == ekTextArea and inf.children.len == 0:
    return textViewString(textViewFromScroll(Id(node)))
  # Buttons with no children: return button title
  if inf.kind == ekButton and inf.children.len == 0:
    return buttonTitle(Id(node))
  # For all nodes with children (including buttons/labels): recurse
  for child in inf.children:
    result.add(r.treeTextContent(child))

proc nthChild*(r: CocoaRenderer; node: CocoaElement; index: int): CocoaElement =
  ## Return the nth child of a node, or nil if out of bounds.
  let inf = info(node)
  if inf != nil and index < inf.children.len:
    inf.children[index]
  else:
    CocoaElement(Id(nil))

proc fireEvent*(r: CocoaRenderer; node: CocoaElement; event: string) =
  ## Simulate an event dispatch (for testing without actual UI interaction).
  let inf = info(node)
  if inf != nil and event in inf.eventCallbacks:
    let cbId = inf.eventCallbacks[event]
    if cbId in callbackTable:
      callbackTable[cbId]()

proc resetTree*() =
  ## Reset all element tracking (for test isolation).
  elements.clear()
  resetCallbacks()
  resetConstraintTracking()
