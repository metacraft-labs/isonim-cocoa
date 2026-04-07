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
import isonim_cocoa/appkit/selectioncontrols
import isonim_cocoa/appkit/dialogs
import isonim_cocoa/appkit/navigation
import isonim_cocoa/appkit/progress
import isonim_cocoa/appkit/media
import isonim_cocoa/appkit/accessibility

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
    ekSwitch     # NSSwitch
    ekSlider     # NSSlider
    ekSelect     # NSPopUpButton
    ekSegmented  # NSSegmentedControl
    ekDatePicker # NSDatePicker
    ekStepper    # NSStepper
    ekModal      # Modal container (Nim-side state machine)
    ekActionSheet # NSMenu-backed action sheet
    ekTabView    # NSTabView
    ekSplitView  # NSSplitView
    ekToolbar    # NSToolbar (Nim-managed items)
    ekDrawer     # NSView with DrawerState
    ekNavStack   # NSView with NavStackState
    ekProgress   # NSProgressIndicator (determinate)
    ekSpinner    # NSProgressIndicator (indeterminate)
    ekBadge      # Composite badge view
    ekWebView    # WKWebView
    ekVideo      # AVPlayer
    ekMapView    # MKMapView

  ElementInfo = object
    kind: ElementKind
    tag: string
    parent: CocoaElement
    children: seq[CocoaElement]
    attributes: Table[string, string]     # attribute name -> value
    eventCallbacks: Table[string, int32]  # event name -> callback ID
    modalState: ModalState                # only used for ekModal
    drawerState: DrawerState              # only used for ekDrawer
    drawerEdge: DrawerEdge                # only used for ekDrawer
    navStackState: NavStackState          # only used for ekNavStack

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

  # Selection controls
  "switch": ekSwitch, "toggle": ekSwitch,
  "slider": ekSlider, "range": ekSlider,
  "select": ekSelect,
  "segmented": ekSegmented,
  "date-picker": ekDatePicker,
  "stepper": ekStepper,

  # Dialogs & modals
  "modal": ekModal,
  "action-sheet": ekActionSheet,

  # Navigation & layout containers
  "tab-view": ekTabView,
  "split-view": ekSplitView,
  "toolbar": ekToolbar,
  "drawer": ekDrawer,
  "nav-stack": ekNavStack,

  # Progress, activity & badges
  "progress": ekProgress,
  "spinner": ekSpinner, "activity-indicator": ekSpinner,
  "badge": ekBadge,

  # Web, media & maps
  "web-view": ekWebView,
  "video": ekVideo,
  "map-view": ekMapView,
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
  of ekSwitch:
    result = CocoaElement(newNSSwitch())
  of ekSlider:
    result = CocoaElement(newNSSlider(0.0, 100.0, 50.0))
  of ekSelect:
    result = CocoaElement(newNSPopUpButton(@[]))
  of ekSegmented:
    result = CocoaElement(newNSSegmentedControl(@[]))
  of ekDatePicker:
    result = CocoaElement(newNSDatePicker())
  of ekStepper:
    result = CocoaElement(newNSStepper(0.0, 100.0, 0.0, 1.0))
  of ekModal:
    # Modal is a plain NSView container; state is tracked Nim-side
    result = CocoaElement(allocInit("NSView"))
    setWantsLayer(Id(result))
    setHidden(Id(result), true)  # hidden by default
  of ekActionSheet:
    # Action sheet backed by an NSMenu
    result = CocoaElement(newNSMenu())
  of ekTabView:
    result = CocoaElement(newNSTabView())
  of ekSplitView:
    result = CocoaElement(newNSSplitView(vertical = true))
  of ekToolbar:
    # Toolbar items are Nim-managed; create a plain NSView as container
    result = CocoaElement(allocInit("NSView"))
    setWantsLayer(Id(result))
  of ekDrawer:
    result = CocoaElement(allocInit("NSView"))
    setWantsLayer(Id(result))
  of ekNavStack:
    result = CocoaElement(allocInit("NSView"))
    setWantsLayer(Id(result))
  of ekProgress:
    result = CocoaElement(newNSProgressIndicator(determinate = true))
  of ekSpinner:
    result = CocoaElement(newNSSpinner())
  of ekBadge:
    result = CocoaElement(newBadge(0))
  of ekWebView:
    result = CocoaElement(newWKWebView(300, 300))
  of ekVideo:
    result = CocoaElement(newAVPlayer())
  of ekMapView:
    result = CocoaElement(newMKMapView())

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

proc newCallbackTarget*(callbackId: int32): Id =
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
    elif inf != nil and inf.kind == ekSlider:
      let v = try: parseFloat(value) except: 0.0
      setSliderValue(view, v)
    elif inf != nil and inf.kind == ekStepper:
      let v = try: parseFloat(value) except: 0.0
      setStepperValue(view, v)
    elif inf != nil and inf.kind == ekProgress:
      let v = try: parseFloat(value) except: 0.0
      # Interpret as fraction 0..1, scale to maxValue
      let maxVal = progressMaxValue(view)
      setProgressValue(view, v * maxVal)
  of "animating":
    if inf != nil and inf.kind == ekSpinner:
      if value == "true":
        startSpinner(view)
      else:
        stopSpinner(view)
  of "count":
    if inf != nil and inf.kind == ekBadge:
      let c = try: parseInt(value) except: 0
      setBadgeCount(view, c)
  of "checked":
    if inf != nil and inf.kind == ekSwitch:
      setSwitchState(view, value == "true" or value == "checked")
  of "min":
    if inf != nil and inf.kind == ekSlider:
      let v = try: parseFloat(value) except: 0.0
      setSliderMin(view, v)
    elif inf != nil and inf.kind == ekStepper:
      let v = try: parseFloat(value) except: 0.0
      msgSendVoid(view, sel("setMinValue:"), v)
  of "max":
    if inf != nil and inf.kind == ekSlider:
      let v = try: parseFloat(value) except: 0.0
      setSliderMax(view, v)
    elif inf != nil and inf.kind == ekStepper:
      let v = try: parseFloat(value) except: 0.0
      msgSendVoid(view, sel("setMaxValue:"), v)
  of "selectedIndex":
    if inf != nil and inf.kind == ekSelect:
      let idx = try: parseInt(value) except: 0
      popUpSelectIndex(view, idx)
    elif inf != nil and inf.kind == ekSegmented:
      let idx = try: parseInt(value) except: 0
      segmentSelect(view, idx)
  of "hidden":
    setHidden(view, true)
  of "visible":
    if inf != nil and inf.kind == ekModal:
      if value == "true":
        inf.modalState = msPresenting
        setHidden(view, false)
      else:
        if inf.modalState == msPresenting:
          inf.modalState = msDismissing
        inf.modalState = msHidden
        setHidden(view, true)
  of "open":
    if inf != nil and inf.kind == ekDrawer:
      if value == "true":
        inf.drawerState = dsOpen
      else:
        inf.drawerState = dsClosed
  of "edge":
    if inf != nil and inf.kind == ekDrawer:
      if value == "right":
        inf.drawerEdge = deRight
      else:
        inf.drawerEdge = deLeft
  of "src":
    if inf != nil:
      if inf.kind == ekWebView:
        webViewLoadURL(view, value)
      elif inf.kind == ekVideo:
        avPlayerSetURL(view, value)
  of "html":
    if inf != nil and inf.kind == ekWebView:
      webViewLoadHTML(view, value)
  of "autoplay":
    if inf != nil and inf.kind == ekVideo:
      if value == "true":
        avPlayerPlay(view)
  of "muted":
    if inf != nil and inf.kind == ekVideo:
      avPlayerSetMuted(view, value == "true")
  of "latitude":
    if inf != nil and inf.kind == ekMapView:
      let lat = try: parseFloat(value) except: 0.0
      let lon = try: parseFloat(inf.attributes.getOrDefault("longitude", "0")) except: 0.0
      mapViewSetCenter(view, lat, lon)
  of "longitude":
    if inf != nil and inf.kind == ekMapView:
      let lat = try: parseFloat(inf.attributes.getOrDefault("latitude", "0")) except: 0.0
      let lon = try: parseFloat(value) except: 0.0
      mapViewSetCenter(view, lat, lon)
  of "mapType":
    if inf != nil and inf.kind == ekMapView:
      let mt = try: parseInt(value) except: 0
      mapViewSetMapType(view, mt)
  of "aria-label":
    setAccessibilityLabel(view, value)
  of "aria-hidden":
    if value == "true":
      setAccessibilityElement(view, false)
    else:
      setAccessibilityElement(view, true)
  of "aria-role":
    let role = case value
      of "button": accessibilityButtonRole()
      of "textfield": accessibilityTextFieldRole()
      of "text", "statictext": accessibilityStaticTextRole()
      of "group": accessibilityGroupRole()
      of "image": accessibilityImageRole()
      of "slider": accessibilitySliderRole()
      of "checkbox": accessibilityCheckBoxRole()
      of "list": accessibilityListRole()
      of "link": accessibilityLinkRole()
      else: toNSString(value)
    setAccessibilityRole(view, role)
  of "aria-valuenow", "aria-valuemin", "aria-valuemax":
    # Store the value; set accessibilityValue to the "now" value as a string
    if name == "aria-valuenow":
      setAccessibilityValue(view, value)
  of "tabindex":
    # Mark the view as focusable via accessibility
    setAccessibilityFocused(view, false)  # ensure it's in the a11y tree
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

proc setAutoAccessibilityRole(view: Id; kind: ElementKind; tag: string) =
  ## Set a default accessibility role based on the element kind.
  case kind
  of ekButton:
    setAccessibilityRole(view, accessibilityButtonRole())
  of ekInput, ekSearch, ekSecureInput, ekTextArea:
    setAccessibilityRole(view, accessibilityTextFieldRole())
  of ekLabel, ekText:
    setAccessibilityRole(view, accessibilityStaticTextRole())
  of ekView:
    setAccessibilityRole(view, accessibilityGroupRole())
  of ekImage:
    setAccessibilityRole(view, accessibilityImageRole())
  of ekSlider:
    setAccessibilityRole(view, accessibilitySliderRole())
  of ekSwitch:
    setAccessibilityRole(view, accessibilityCheckBoxRole())
  of ekStack:
    if tag in ["ul", "ol"]:
      setAccessibilityRole(view, accessibilityListRole())
    else:
      setAccessibilityRole(view, accessibilityGroupRole())
  else:
    discard  # No default role for specialized views

proc createElement*(r: CocoaRenderer; tag: string): CocoaElement =
  let kind = tagMap.getOrDefault(tag, ekView)
  result = createNativeView(kind, tag)
  discard ensureInfo(result, kind, tag)
  setAutoAccessibilityRole(Id(result), kind, tag)

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
  elif inf != nil and inf.kind == ekSlider:
    let v = try: parseFloat(text) except: 0.0
    setSliderValue(Id(node), v)
  elif inf != nil and inf.kind == ekStepper:
    let v = try: parseFloat(text) except: 0.0
    setStepperValue(Id(node), v)

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
    # Selection controls use target-action for change events
    if inf != nil and inf.kind in {ekSwitch, ekSlider, ekSelect, ekSegmented,
                                     ekDatePicker, ekStepper}:
      msgSendVoid(Id(node), sel("setTarget:"), target)
      msgSendVoid(Id(node), sel("setAction:"), Id(sel("callbackAction:")))
    else:
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
  elif inf != nil and inf.kind == ekSlider:
    $sliderValue(Id(node))
  elif inf != nil and inf.kind == ekStepper:
    $stepperValue(Id(node))
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

proc modalState*(r: CocoaRenderer; node: CocoaElement): ModalState =
  ## Get the modal state of a modal element.
  let inf = info(node)
  if inf != nil:
    inf.modalState
  else:
    msHidden

proc drawerState*(r: CocoaRenderer; elem: CocoaElement): DrawerState =
  ## Get the drawer state of a drawer element.
  let inf = info(elem)
  if inf != nil:
    inf.drawerState
  else:
    dsClosed

proc drawerEdge*(r: CocoaRenderer; elem: CocoaElement): DrawerEdge =
  ## Get the drawer edge (left or right).
  let inf = info(elem)
  if inf != nil:
    inf.drawerEdge
  else:
    deLeft

proc navStackPush*(r: CocoaRenderer; elem, view: CocoaElement) =
  ## Push a view onto the nav stack.
  let inf = info(elem)
  if inf != nil:
    inf.navStackState.stack.add(pointer(view))
    if inf.navStackState.onPush != nil:
      inf.navStackState.onPush()

proc navStackPop*(r: CocoaRenderer; elem: CocoaElement): CocoaElement =
  ## Pop the top view off the nav stack and return it.
  let inf = info(elem)
  if inf != nil and inf.navStackState.stack.len > 1:
    let top = inf.navStackState.stack.pop()
    if inf.navStackState.onPop != nil:
      inf.navStackState.onPop()
    CocoaElement(Id(top))
  else:
    CocoaElement(Id(nil))

proc navStackPopToRoot*(r: CocoaRenderer; elem: CocoaElement) =
  ## Pop all views except the root.
  let inf = info(elem)
  if inf != nil and inf.navStackState.stack.len > 1:
    let popCount = inf.navStackState.stack.len - 1
    inf.navStackState.stack.setLen(1)
    for _ in 0..<popCount:
      if inf.navStackState.onPop != nil:
        inf.navStackState.onPop()

proc navStackDepth*(r: CocoaRenderer; elem: CocoaElement): int =
  ## Return the number of views in the nav stack.
  let inf = info(elem)
  if inf != nil:
    inf.navStackState.stack.len
  else:
    0

proc navStackCurrent*(r: CocoaRenderer; elem: CocoaElement): CocoaElement =
  ## Return the top (current) view on the nav stack.
  let inf = info(elem)
  if inf != nil and inf.navStackState.stack.len > 0:
    CocoaElement(Id(inf.navStackState.stack[^1]))
  else:
    CocoaElement(Id(nil))

proc navStackSetOnPush*(r: CocoaRenderer; elem: CocoaElement; cb: proc()) =
  ## Set the onPush callback for a nav stack.
  let inf = info(elem)
  if inf != nil:
    inf.navStackState.onPush = cb

proc navStackSetOnPop*(r: CocoaRenderer; elem: CocoaElement; cb: proc()) =
  ## Set the onPop callback for a nav stack.
  let inf = info(elem)
  if inf != nil:
    inf.navStackState.onPop = cb

proc resetTree*() =
  ## Reset all element tracking (for test isolation).
  elements.clear()
  resetCallbacks()
  resetConstraintTracking()
  resetMenuCallbacks()
  resetToolbarItems()
