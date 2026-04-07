## Reactive scheduler — bridges IsoNim's reactive system to the AppKit main thread.
##
## Provides `scheduleOnMainThread` and `scheduleBatch` which queue Nim
## closures for execution. In production these would use dispatch_async
## to the main queue; for testing we maintain a Nim-side queue drained
## by `flushPendingCallbacks` (avoids C block syntax).

import std/deques
import isonim_cocoa/testing/fake_clock

# ---------------------------------------------------------------------------
# Pending callback queue
# ---------------------------------------------------------------------------

var pendingCallbacks: Deque[proc()]
var activeClock: FakeClock = nil

proc setActiveClock*(clock: FakeClock) =
  ## When set, `scheduleOnMainThread` delegates to the FakeClock
  ## (scheduling at current time + 0 delay) instead of the real queue.
  activeClock = clock

proc clearActiveClock*() =
  activeClock = nil

proc scheduleOnMainThread*(callback: proc()) =
  ## Queue a callback for execution on the main thread.
  ## When a FakeClock is active, schedules via the clock (fires on next advance).
  ## Otherwise, adds to the pending queue drained by `flushPendingCallbacks`.
  if activeClock != nil:
    discard activeClock.schedule(0.0, callback)
  else:
    pendingCallbacks.addLast(callback)

proc scheduleBatch*(updates: seq[proc()]) =
  ## Queue multiple updates as a single batch. All run in one drain pass.
  if activeClock != nil:
    for u in updates:
      discard activeClock.schedule(0.0, u)
  else:
    for u in updates:
      pendingCallbacks.addLast(u)

proc flushPendingCallbacks*() =
  ## Drain and execute all queued callbacks. Safe to call from tests.
  ## Processes callbacks that were queued at the time of the call;
  ## callbacks added during execution are processed in the same pass.
  while pendingCallbacks.len > 0:
    let cb = pendingCallbacks.popFirst()
    cb()

proc pendingCallbackCount*(): int =
  ## Number of callbacks waiting in the queue.
  pendingCallbacks.len

proc resetScheduler*() =
  ## Clear the queue and detach any FakeClock (for test isolation).
  pendingCallbacks.clear()
  activeClock = nil
