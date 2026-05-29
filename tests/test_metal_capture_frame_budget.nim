## EPP-M4 per-frame budget test: capture 100 frames through
## ``captureViewMetal`` and assert the median per-frame budget stays
## below the 10 ms ceiling EPP-M4 promises on macOS ARM64.
##
## Gated entirely ``when defined(macosx)``. On Linux the test body
## skips with ``check true`` — EPP-M4 is macOS-only by design.
##
## ## Bring-up caveat
##
## The EPP-M1 audit (§ 1.3) predicted a pure ``CARenderer`` +
## ``MTLTexture`` path would land at 5-15 ms / frame on M1. Bring-up
## uncovered that CARenderer does not paint the CALayer hierarchy of
## a headless NSView in a unit-test binary that has no
## NSApplication / NSWindow attached, so EPP-M4 ships a *hybrid*
## Metal-backed path: AppKit's
## ``bitmapImageRepForCachingDisplayInRect:`` produces the raster,
## the bytes round-trip through an ``MTLPixelFormatRGBA8Unorm``
## texture, and the canonical RGBA bytes come out the other side.
## See ``isonim_cocoa/testing/capture_metal.m`` § "Architecture
## decision (post-bring-up)" for the full rationale.
##
## What this means for the budget test: the per-frame time is bounded
## by AppKit's drawing pass, not by Metal. For small / medium trees
## (which is what we capture here — a small ``<div>`` with a
## background colour) the budget is comfortably under 10 ms. For
## very heavy trees (the EX-M5 task_app demo with several hundred
## NSViews) the budget tracks the EPP-M1 audit's 10-40 ms
## observation; future work is a pure-CARenderer path post EPP-M5.

import std/[times, unittest, algorithm, monotimes, strutils]

when defined(macosx):
  import isonim_cocoa/objc_runtime
  import isonim_cocoa/renderer
  import isonim_cocoa/appkit/capture_metal as cocoa_metal_capture

  const
    FrameCount  = 100
    Width       = 320
    Height      = 240
    BudgetMs    = 10.0

  suite "EPP-M4: Metal capture per-frame budget":

    test "median per-frame budget stays below 10 ms":
      if not cocoa_metal_capture.isMetalCaptureAvailable():
        skip()
      else:
        resetTree()
        resetCallbacks()
        let r = CocoaRenderer()
        let root = r.createElement("div")
        r.setAttribute(root, "class", "metal-budget-bench")
        r.setStyle(root, "background-color", "#3264c8")

        # Warm-up: the first capture pays the device-init +
        # command-queue allocation cost (~hundreds of microseconds).
        # We don't want that to skew the steady-state percentile.
        discard cocoa_metal_capture.captureViewMetal(Id(root),
                                                     Width, Height)

        var perFrameMs = newSeq[float](FrameCount)
        for i in 0 ..< FrameCount:
          let start = getMonoTime()
          let bytes = cocoa_metal_capture.captureViewMetal(Id(root),
                                                           Width, Height)
          let elapsed = getMonoTime() - start
          perFrameMs[i] = elapsed.inMicroseconds.float / 1000.0
          check bytes.len == Width * Height * 4

        perFrameMs.sort()
        let median = perFrameMs[FrameCount div 2]
        # Print the percentile distribution so a future regression
        # has a clear before/after baseline in the test output.
        echo "EPP-M4 budget: ",
          " p50=", median.formatFloat(ffDecimal, 2), " ms",
          " p90=", perFrameMs[(FrameCount * 9) div 10].formatFloat(ffDecimal, 2), " ms",
          " p99=", perFrameMs[(FrameCount * 99) div 100].formatFloat(ffDecimal, 2), " ms",
          " min=", perFrameMs[0].formatFloat(ffDecimal, 2), " ms",
          " max=", perFrameMs[FrameCount - 1].formatFloat(ffDecimal, 2), " ms"

        check median < BudgetMs

else:
  ## Non-macOS host: EPP-M4 is macOS-only by design.
  suite "EPP-M4: Metal capture per-frame budget":
    test "skipped on non-macOS hosts":
      check true
