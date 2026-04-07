## Progress, Activity & Badge wrappers — NSProgressIndicator, Badge (composite),
## Toast (overlay with FakeClock auto-dismiss).

import std/strutils
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/testing/fake_clock

{.passL: "-framework AppKit".}

# ===========================================================================
# NSProgressIndicator (determinate)
# ===========================================================================

proc newNSProgressIndicator*(determinate: bool = true): Id =
  ## Create an NSProgressIndicator. Determinate by default (bar style).
  result = allocInit("NSProgressIndicator")
  setWantsLayer(result)
  # NSProgressIndicatorStyleBar = 0
  msgSendVoidInt(result, sel("setStyle:"), cint(0))
  msgSendVoidBool(result, sel("setIndeterminate:"), not determinate)
  msgSendVoid(result, sel("setMinValue:"), cdouble(0.0))
  msgSendVoid(result, sel("setMaxValue:"), cdouble(100.0))
  msgSendVoid(result, sel("setDoubleValue:"), cdouble(0.0))

proc progressValue*(p: Id): cdouble =
  ## Read the current doubleValue of the progress indicator.
  msgSendFloat(p, sel("doubleValue"))

proc progressMinValue*(p: Id): cdouble =
  ## Read minValue.
  msgSendFloat(p, sel("minValue"))

proc progressMaxValue*(p: Id): cdouble =
  ## Read maxValue.
  msgSendFloat(p, sel("maxValue"))

proc setProgressValue*(p: Id; v: cdouble) =
  ## Set progress value, clamping to [minValue, maxValue].
  let lo = progressMinValue(p)
  let hi = progressMaxValue(p)
  var clamped = v
  if clamped < lo: clamped = lo
  if clamped > hi: clamped = hi
  msgSendVoid(p, sel("setDoubleValue:"), clamped)

proc progressIsIndeterminate*(p: Id): bool =
  ## Returns true if the progress indicator is in indeterminate mode.
  msgSendBool(p, sel("isIndeterminate"))

proc setProgressMin*(p: Id; v: cdouble) =
  ## Set the minimum value.
  msgSendVoid(p, sel("setMinValue:"), v)

proc setProgressMax*(p: Id; v: cdouble) =
  ## Set the maximum value.
  msgSendVoid(p, sel("setMaxValue:"), v)

# ===========================================================================
# NSProgressIndicator (indeterminate / spinner)
# ===========================================================================

proc newNSSpinner*(): Id =
  ## Create an indeterminate NSProgressIndicator (spinning style).
  result = allocInit("NSProgressIndicator")
  setWantsLayer(result)
  # NSProgressIndicatorStyleSpinning = 1
  msgSendVoidInt(result, sel("setStyle:"), cint(1))
  msgSendVoidBool(result, sel("setIndeterminate:"), true)

proc startSpinner*(p: Id) =
  ## Start the spinner animation (startAnimation:nil).
  msgSendVoid(p, sel("startAnimation:"), NilId)

proc stopSpinner*(p: Id) =
  ## Stop the spinner animation (stopAnimation:nil).
  msgSendVoid(p, sel("stopAnimation:"), NilId)

# ===========================================================================
# Badge (composite: NSView with rounded-rect background + NSTextField label)
# ===========================================================================

proc newBadge*(count: int = 0): Id =
  ## Create a badge view: an NSView container with a background layer and
  ## an NSTextField label child. Hidden when count == 0.
  result = allocInit("NSView")
  setWantsLayer(result)

  # Set rounded corner radius on the layer
  {.emit: """
  id layer = ((id(*)(id, SEL))objc_msgSend)((id)`result`, sel_registerName("layer"));
  if (layer) {
    ((void(*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setCornerRadius:"), 9.0);
    // Red background
    id nsColor = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
      (id)objc_getClass("NSColor"),
      sel_registerName("colorWithRed:green:blue:alpha:"),
      1.0, 0.2, 0.2, 1.0);
    void* cgColor = ((void*(*)(id, SEL))objc_msgSend)(nsColor, sel_registerName("CGColor"));
    ((void(*)(id, SEL, void*))objc_msgSend)(layer, sel_registerName("setBackgroundColor:"), cgColor);
  }
  """.}

  # Create a label for the count text
  let label = newNSLabel("")
  setFontSize(label, 11.0)
  # White text color
  {.emit: """
  id whiteColor = ((id(*)(id, SEL))objc_msgSend)(
    (id)objc_getClass("NSColor"), sel_registerName("whiteColor"));
  ((void(*)(id, SEL, id))objc_msgSend)((id)`label`, sel_registerName("setTextColor:"), whiteColor);
  """.}
  addSubview(result, label)

  # Set initial count
  if count == 0:
    setHidden(result, true)
  else:
    let text = if count > 99: "99+" else: $count
    setStringValue(label, text)

proc setBadgeCount*(badge: Id; count: int) =
  ## Update the badge count. Hides the badge at 0, shows "99+" above 99.
  if count <= 0:
    setHidden(badge, true)
    # Update label to "0"
    let subs = subviews(badge)
    if not subs.isNil and nsArrayCount(subs) > 0:
      let label = nsArrayObjectAtIndex(subs, nsArrayCount(subs) - 1)
      setStringValue(label, "0")
  else:
    setHidden(badge, false)
    let text = if count > 99: "99+" else: $count
    let subs = subviews(badge)
    if not subs.isNil and nsArrayCount(subs) > 0:
      let label = nsArrayObjectAtIndex(subs, nsArrayCount(subs) - 1)
      setStringValue(label, text)

proc badgeCount*(badge: Id): int =
  ## Read back the badge count from the label text.
  let subs = subviews(badge)
  if subs.isNil or nsArrayCount(subs) == 0:
    return 0
  let label = nsArrayObjectAtIndex(subs, nsArrayCount(subs) - 1)
  let text = stringValue(label)
  if text == "99+":
    return 100  # convention: 99+ means >= 100
  try:
    result = parseInt(text)
  except ValueError:
    result = 0

proc isBadgeHidden*(badge: Id): bool =
  ## Returns true if the badge is hidden (count == 0).
  isHidden(badge)

# ===========================================================================
# Toast (overlay view with FakeClock auto-dismiss)
# ===========================================================================

type
  ToastEntry = object
    view: Id
    message: string
    duration: cdouble
    dismissed: bool

  ToastManager* = ref object
    queue: seq[ToastEntry]
    clock: FakeClock

proc newToastManager*(): ToastManager =
  ToastManager(queue: @[])

proc visibleToastCount*(mgr: ToastManager): int =
  ## Number of currently visible (non-hidden) toasts.
  for entry in mgr.queue:
    if not isHidden(entry.view):
      inc result

proc currentToastMessage*(mgr: ToastManager): string =
  ## Message of the front-most visible toast, or "" if none.
  for entry in mgr.queue:
    if not isHidden(entry.view):
      return entry.message
  return ""

proc scheduleDismiss(mgr: ToastManager; entryIdx: int; clock: FakeClock)

proc showNextQueued(mgr: ToastManager; afterIdx: int; clock: FakeClock) =
  ## Show the next queued (non-dismissed) toast after afterIdx and schedule its dismiss.
  for i in (afterIdx + 1)..<mgr.queue.len:
    if not mgr.queue[i].dismissed:
      setHidden(mgr.queue[i].view, false)
      mgr.scheduleDismiss(i, clock)
      break

proc scheduleDismiss(mgr: ToastManager; entryIdx: int; clock: FakeClock) =
  let dur = mgr.queue[entryIdx].duration
  discard clock.schedule(dur, proc() =
    if entryIdx < mgr.queue.len and not mgr.queue[entryIdx].dismissed:
      mgr.queue[entryIdx].dismissed = true
      setHidden(mgr.queue[entryIdx].view, true)
      mgr.showNextQueued(entryIdx, clock)
  )

proc showToast*(mgr: ToastManager; message: string; duration: cdouble;
                clock: FakeClock) =
  ## Create a toast overlay, schedule auto-dismiss via FakeClock.
  ## Only one toast is visible at a time; later toasts queue behind.
  ## The dismiss timer for queued toasts starts only when they become visible.
  let view = allocInit("NSView")
  setWantsLayer(view)

  # Add a label
  let label = newNSLabel(message)
  addSubview(view, label)

  let isFirst = mgr.visibleToastCount() == 0

  if not isFirst:
    setHidden(view, true)

  let entryIdx = mgr.queue.len
  mgr.queue.add(ToastEntry(view: view, message: message, duration: duration,
                            dismissed: false))
  mgr.clock = clock

  # Only schedule dismiss for the immediately visible toast.
  # Queued toasts get their timer when they become visible.
  if isFirst:
    mgr.scheduleDismiss(entryIdx, clock)
