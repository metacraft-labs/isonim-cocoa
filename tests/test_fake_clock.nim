## Tests for FakeClock and pumpRunLoop test infrastructure.

import unittest
import isonim_cocoa/testing/fake_clock

suite "FakeClock - Timer Scheduling":
  test "schedule and fire one-shot timer":
    let clock = newFakeClock()
    var fired = false
    discard clock.schedule(1.0, proc() = fired = true)
    check not fired
    clock.advance(0.5)
    check not fired
    clock.advance(0.5)
    check fired

  test "timer fires at exact time":
    let clock = newFakeClock()
    var fired = false
    discard clock.schedule(2.0, proc() = fired = true)
    clock.advance(1.999)
    check not fired
    clock.advance(0.001)
    check fired

  test "multiple timers fire in order":
    let clock = newFakeClock()
    var order: seq[int] = @[]
    discard clock.schedule(3.0, proc() = order.add(3))
    discard clock.schedule(1.0, proc() = order.add(1))
    discard clock.schedule(2.0, proc() = order.add(2))
    clock.advance(5.0)
    check order == @[1, 2, 3]

  test "cancelled timer does not fire":
    let clock = newFakeClock()
    var fired = false
    let id = clock.schedule(1.0, proc() = fired = true)
    clock.cancel(id)
    clock.advance(5.0)
    check not fired

  test "repeating timer fires multiple times":
    let clock = newFakeClock()
    var count = 0
    discard clock.schedule(1.0, (proc() = inc count), interval = 1.0)
    clock.advance(3.5)
    check count == 3  # fires at 1.0, 2.0, 3.0

  test "repeating timer can be cancelled":
    let clock = newFakeClock()
    var count = 0
    let id = clock.schedule(1.0, (proc() = inc count), interval = 1.0)
    clock.advance(2.5)
    check count == 2  # fires at 1.0, 2.0
    clock.cancel(id)
    clock.advance(5.0)
    check count == 2  # no more fires

  test "pendingTimerCount":
    let clock = newFakeClock()
    check clock.pendingTimerCount == 0
    discard clock.schedule(1.0, proc() = discard)
    discard clock.schedule(2.0, proc() = discard)
    check clock.pendingTimerCount == 2
    clock.advance(1.5)
    check clock.pendingTimerCount == 1  # first timer fired (one-shot = cancelled)
    clock.advance(1.0)
    check clock.pendingTimerCount == 0

  test "reset clears all state":
    let clock = newFakeClock()
    discard clock.schedule(1.0, proc() = discard)
    clock.advance(0.5)
    clock.reset()
    check clock.time == 0.0
    check clock.pendingTimerCount == 0

  test "clock time advances correctly":
    let clock = newFakeClock(startTime = 10.0)
    check clock.time == 10.0
    clock.advance(5.0)
    check clock.time == 15.0

  test "timer callback can schedule more timers":
    let clock = newFakeClock()
    var total = 0
    discard clock.schedule(1.0, proc() =
      inc total
      discard clock.schedule(1.0, proc() = inc total)
    )
    clock.advance(1.0)
    check total == 1
    clock.advance(1.0)
    check total == 2

suite "pumpRunLoop":
  test "pumpRunLoop does not crash on empty run loop":
    pumpRunLoop(1)

  test "advanceAndPump fires fake timers and pumps run loop":
    let clock = newFakeClock()
    var timerFired = false
    discard clock.schedule(0.5, proc() = timerFired = true)
    check not timerFired
    clock.advanceAndPump(1.0)
    check timerFired
