## App & Window lifecycle delegates — dynamic ObjC classes that dispatch to Nim closures.
##
## Creates NimAppDelegate (NSApplicationDelegate) and NimWindowDelegate
## (NSWindowDelegate) at runtime using the ObjC runtime's class-creation API.
## Each delegate method looks up a registered Nim closure and calls it.

import std/tables
import isonim_cocoa/objc_runtime

{.passL: "-framework AppKit".}

# ---------------------------------------------------------------------------
# App-level callbacks
# ---------------------------------------------------------------------------

var appCallbacks: Table[string, proc()]

proc registerAppCallback*(event: string; handler: proc()) =
  ## Register a closure for an app lifecycle event.
  ## Supported events: "didFinishLaunching", "didBecomeActive",
  ## "willResignActive", "willTerminate"
  appCallbacks[event] = handler

proc clearAppCallbacks*() =
  appCallbacks.clear()

# ObjC delegate methods — called by the runtime, dispatch to Nim closures.

proc nimAppDidFinishLaunching(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  if "didFinishLaunching" in appCallbacks:
    appCallbacks["didFinishLaunching"]()

proc nimAppDidBecomeActive(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  if "didBecomeActive" in appCallbacks:
    appCallbacks["didBecomeActive"]()

proc nimAppWillResignActive(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  if "willResignActive" in appCallbacks:
    appCallbacks["willResignActive"]()

proc nimAppWillTerminate(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  if "willTerminate" in appCallbacks:
    appCallbacks["willTerminate"]()

# Dynamic class creation

var nimAppDelegateClass*: Class

proc ensureAppDelegateClass*(): Class =
  ## Create (once) and return the NimAppDelegate ObjC class.
  if nimAppDelegateClass.isNil:
    nimAppDelegateClass = objc_allocateClassPair(
      cls("NSObject"), "NimAppDelegate".cstring)

    # Adopt the NSApplicationDelegate protocol
    let proto = objc_getProtocol("NSApplicationDelegate".cstring)
    if not proto.isNil:
      discard class_addProtocol(nimAppDelegateClass, proto)

    # Register delegate methods — type encoding "v@:@" = void(id, SEL, id)
    discard class_addMethod(nimAppDelegateClass,
      sel("applicationDidFinishLaunching:"),
      cast[Imp](nimAppDidFinishLaunching), "v@:@".cstring)

    discard class_addMethod(nimAppDelegateClass,
      sel("applicationDidBecomeActive:"),
      cast[Imp](nimAppDidBecomeActive), "v@:@".cstring)

    discard class_addMethod(nimAppDelegateClass,
      sel("applicationWillResignActive:"),
      cast[Imp](nimAppWillResignActive), "v@:@".cstring)

    discard class_addMethod(nimAppDelegateClass,
      sel("applicationWillTerminate:"),
      cast[Imp](nimAppWillTerminate), "v@:@".cstring)

    objc_registerClassPair(nimAppDelegateClass)
  result = nimAppDelegateClass

proc newAppDelegate*(): Id =
  ## Instantiate a NimAppDelegate.
  let cls = ensureAppDelegateClass()
  result = msgSend(msgSend(Id(cls), sel("alloc")), sel("init"))

# ---------------------------------------------------------------------------
# Window-level callbacks
# ---------------------------------------------------------------------------

# Keyed by (window pointer, event name)
var windowCallbacks: Table[(pointer, string), proc()]

proc registerWindowCallback*(window: Id; event: string; handler: proc()) =
  ## Register a closure for a window lifecycle event.
  ## Supported events: "didResize", "willClose", "didBecomeKey", "didResignKey"
  windowCallbacks[(pointer(window), event)] = handler

proc clearWindowCallbacks*() =
  windowCallbacks.clear()

# We store the window pointer in an ivar so the delegate can look up
# which window's callbacks to fire. However, NSWindowDelegate methods
# receive the NSNotification which contains the window as `object`.
# For simplicity, we store a mapping from delegate instance -> window.

var delegateToWindow: Table[pointer, Id]

proc windowForDelegate(delegate: Id): Id =
  let p = pointer(delegate)
  if p in delegateToWindow:
    delegateToWindow[p]
  else:
    NilId

proc fireWindowEvent(delegate: Id; event: string) =
  let win = windowForDelegate(delegate)
  if not win.isNil:
    let key = (pointer(win), event)
    if key in windowCallbacks:
      windowCallbacks[key]()

proc nimWindowDidResize(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  fireWindowEvent(self, "didResize")

proc nimWindowWillClose(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  fireWindowEvent(self, "willClose")

proc nimWindowDidBecomeKey(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  fireWindowEvent(self, "didBecomeKey")

proc nimWindowDidResignKey(self: Id; cmd: Sel; notification: Id) {.cdecl.} =
  fireWindowEvent(self, "didResignKey")

var nimWindowDelegateClass*: Class

proc ensureWindowDelegateClass*(): Class =
  ## Create (once) and return the NimWindowDelegate ObjC class.
  if nimWindowDelegateClass.isNil:
    nimWindowDelegateClass = objc_allocateClassPair(
      cls("NSObject"), "NimWindowDelegate".cstring)

    let proto = objc_getProtocol("NSWindowDelegate".cstring)
    if not proto.isNil:
      discard class_addProtocol(nimWindowDelegateClass, proto)

    discard class_addMethod(nimWindowDelegateClass,
      sel("windowDidResize:"),
      cast[Imp](nimWindowDidResize), "v@:@".cstring)

    discard class_addMethod(nimWindowDelegateClass,
      sel("windowWillClose:"),
      cast[Imp](nimWindowWillClose), "v@:@".cstring)

    discard class_addMethod(nimWindowDelegateClass,
      sel("windowDidBecomeKey:"),
      cast[Imp](nimWindowDidBecomeKey), "v@:@".cstring)

    discard class_addMethod(nimWindowDelegateClass,
      sel("windowDidResignKey:"),
      cast[Imp](nimWindowDidResignKey), "v@:@".cstring)

    objc_registerClassPair(nimWindowDelegateClass)
  result = nimWindowDelegateClass

proc newWindowDelegate*(window: Id): Id =
  ## Instantiate a NimWindowDelegate and associate it with a window.
  let cls = ensureWindowDelegateClass()
  result = msgSend(msgSend(Id(cls), sel("alloc")), sel("init"))
  delegateToWindow[pointer(result)] = window

proc setWindowDelegate*(window: Id; delegate: Id) =
  ## Set the delegate on an NSWindow.
  msgSendVoid(window, sel("setDelegate:"), delegate)

# ---------------------------------------------------------------------------
# Reset (for test isolation)
# ---------------------------------------------------------------------------

proc resetLifecycle*() =
  ## Clear all registered callbacks (for testing).
  appCallbacks.clear()
  windowCallbacks.clear()
  delegateToWindow.clear()
