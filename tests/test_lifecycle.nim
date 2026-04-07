## Tests for M4: App Lifecycle & Event Loop Integration.

import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/window
import isonim_cocoa/appkit/lifecycle
import isonim_cocoa/appkit/scheduler
import isonim_cocoa/renderer
import isonim_cocoa/testing/fake_clock

# Ensure NSApplication exists (needed for delegate protocols to resolve)
discard sharedApplication()

suite "Lifecycle - App Delegate Creation":
  setup:
    resetLifecycle()

  test "NimAppDelegate class is created":
    let cls = ensureAppDelegateClass()
    check not cls.isNil
    check $class_getName(cls) == "NimAppDelegate"

  test "responds to applicationDidFinishLaunching:":
    discard ensureAppDelegateClass()
    let inst = newAppDelegate()
    check msgSendBool(inst, sel("respondsToSelector:"),
                      sel("applicationDidFinishLaunching:"))

  test "responds to applicationDidBecomeActive:":
    let inst = newAppDelegate()
    check msgSendBool(inst, sel("respondsToSelector:"),
                      sel("applicationDidBecomeActive:"))

  test "responds to applicationWillResignActive:":
    let inst = newAppDelegate()
    check msgSendBool(inst, sel("respondsToSelector:"),
                      sel("applicationWillResignActive:"))

  test "responds to applicationWillTerminate:":
    let inst = newAppDelegate()
    check msgSendBool(inst, sel("respondsToSelector:"),
                      sel("applicationWillTerminate:"))

suite "Lifecycle - Lifecycle Order":
  setup:
    resetLifecycle()

  test "delegate methods fire in correct order":
    var order: seq[string] = @[]
    registerAppCallback("didFinishLaunching", proc() = order.add("didFinishLaunching"))
    registerAppCallback("didBecomeActive", proc() = order.add("didBecomeActive"))
    registerAppCallback("willTerminate", proc() = order.add("willTerminate"))

    let delegate = newAppDelegate()
    # Simulate calling delegate methods in sequence
    msgSendVoid(delegate, sel("applicationDidFinishLaunching:"), NilId)
    msgSendVoid(delegate, sel("applicationDidBecomeActive:"), NilId)
    msgSendVoid(delegate, sel("applicationWillTerminate:"), NilId)

    check order.len == 3
    check order[0] == "didFinishLaunching"
    check order[1] == "didBecomeActive"
    check order[2] == "willTerminate"

  test "willResignActive fires":
    var fired = false
    registerAppCallback("willResignActive", proc() = fired = true)

    let delegate = newAppDelegate()
    msgSendVoid(delegate, sel("applicationWillResignActive:"), NilId)
    check fired

suite "Lifecycle - Window Delegate":
  setup:
    resetLifecycle()

  test "NimWindowDelegate class is created":
    let cls = ensureWindowDelegateClass()
    check not cls.isNil
    check $class_getName(cls) == "NimWindowDelegate"

  test "responds to windowDidResize:":
    let win = newNSWindow(0, 0, 400, 300)
    let delegate = newWindowDelegate(win)
    check msgSendBool(delegate, sel("respondsToSelector:"),
                      sel("windowDidResize:"))

  test "responds to windowWillClose:":
    let win = newNSWindow(0, 0, 400, 300)
    let delegate = newWindowDelegate(win)
    check msgSendBool(delegate, sel("respondsToSelector:"),
                      sel("windowWillClose:"))

  test "windowDidResize callback fires":
    let win = newNSWindow(0, 0, 400, 300)
    var resized = false
    registerWindowCallback(win, "didResize", proc() = resized = true)

    let delegate = newWindowDelegate(win)
    setWindowDelegate(win, delegate)
    # Simulate the delegate call
    msgSendVoid(delegate, sel("windowDidResize:"), NilId)
    check resized

  test "windowWillClose callback fires":
    let win = newNSWindow(0, 0, 400, 300)
    var closed = false
    registerWindowCallback(win, "willClose", proc() = closed = true)

    let delegate = newWindowDelegate(win)
    setWindowDelegate(win, delegate)
    msgSendVoid(delegate, sel("windowWillClose:"), NilId)
    check closed

  test "windowDidBecomeKey and windowDidResignKey":
    let win = newNSWindow(0, 0, 400, 300)
    var events: seq[string] = @[]
    registerWindowCallback(win, "didBecomeKey", proc() = events.add("becameKey"))
    registerWindowCallback(win, "didResignKey", proc() = events.add("resignedKey"))

    let delegate = newWindowDelegate(win)
    setWindowDelegate(win, delegate)
    msgSendVoid(delegate, sel("windowDidBecomeKey:"), NilId)
    msgSendVoid(delegate, sel("windowDidResignKey:"), NilId)
    check events == @["becameKey", "resignedKey"]

suite "Lifecycle - Reactive View Update":
  setup:
    resetLifecycle()
    resetTree()
    resetScheduler()

  test "signal-like variable updates view via scheduler":
    let r = CocoaRenderer()
    let label = r.createElement("span")
    r.setTextContent(label, "initial")

    # Simulate a reactive signal: changing a variable schedules a view update
    var signalValue = "initial"
    proc updateSignal(newVal: string) =
      signalValue = newVal
      let capturedVal = newVal
      let capturedLabel = label
      scheduleOnMainThread(proc() =
        r.setTextContent(capturedLabel, capturedVal)
      )

    updateSignal("updated")
    # View not yet updated (callback is queued)
    check r.textContent(label) == "initial"

    # Drain the queue
    flushPendingCallbacks()
    pumpRunLoop()
    check r.textContent(label) == "updated"

suite "Lifecycle - Batch Updates":
  setup:
    resetLifecycle()
    resetTree()
    resetScheduler()

  test "batch 10 updates via scheduleBatch":
    let r = CocoaRenderer()
    var labels: seq[CocoaElement] = @[]
    for i in 0..<10:
      let lbl = r.createElement("span")
      r.setTextContent(lbl, "old")
      labels.add(lbl)

    proc makeUpdateCb(rr: CocoaRenderer; lbl: CocoaElement; newVal: string): proc() =
      result = proc() =
        rr.setTextContent(lbl, newVal)

    var updates: seq[proc()] = @[]
    for i in 0..<10:
      updates.add(makeUpdateCb(r, labels[i], "new-" & $i))

    scheduleBatch(updates)
    # Nothing applied yet
    for lbl in labels:
      check r.textContent(lbl) == "old"

    flushPendingCallbacks()
    pumpRunLoop()

    for i in 0..<10:
      check r.textContent(labels[i]) == "new-" & $i

suite "Lifecycle - Timer-Driven Update":
  setup:
    resetLifecycle()
    resetTree()
    resetScheduler()

  test "FakeClock-driven scheduled callback updates view":
    let clock = newFakeClock()
    setActiveClock(clock)

    let r = CocoaRenderer()
    let label = r.createElement("span")
    r.setTextContent(label, "waiting")

    # Schedule a callback at t=1s
    discard clock.schedule(1.0, proc() =
      r.setTextContent(label, "timer fired")
    )

    # Not yet
    check r.textContent(label) == "waiting"

    # Advance to t=1s
    clock.advance(1.0)
    pumpRunLoop()
    check r.textContent(label) == "timer fired"

    clearActiveClock()

  test "scheduleOnMainThread uses FakeClock when active":
    let clock = newFakeClock()
    setActiveClock(clock)

    var executed = false
    scheduleOnMainThread(proc() = executed = true)

    # Callback is scheduled at t=0 via clock, needs advance
    check not executed
    clock.advance(0.0)
    check executed

    clearActiveClock()
