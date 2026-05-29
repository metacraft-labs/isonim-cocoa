## EPP-M4 round-trip test: feed a known CALayer-backed NSView tree
## through ``captureViewMetal`` and assert the resulting RGBA buffer
## reflects the rendered raster (specifically: dimensions match, alpha
## is opaque, channel-relationship match for a saturated-colour
## background fill that no swizzle confusion can accidentally
## reproduce).
##
## Gated entirely ``when defined(macosx)``. On Linux the test body
## skips with ``check true``; EPP-M4 is macOS-only by design — the
## metal helper is gated to macOS in
## ``isonim_cocoa/appkit/capture_metal.nim`` and the Linux body of
## that module unconditionally returns "unavailable".

import std/unittest

when defined(macosx):
  import isonim_cocoa/objc_runtime
  import isonim_cocoa/renderer
  import isonim_cocoa/appkit/capture_metal as cocoa_metal_capture
  import isonim_cocoa/appkit/capture as cocoa_appkit_capture

  suite "EPP-M4: Metal-backed Cocoa capture round-trip":

    test "Metal device is available on this macOS host":
      ## Smoke-test the helper's availability probe so any CI lane
      ## that runs without a Metal device (cmd-line LLM VM, headless
      ## sandboxed CI) prints a clear "host has no Metal device"
      ## failure instead of a confusing all-zeros raster downstream.
      check cocoa_metal_capture.isMetalCaptureAvailable()

    test "captureViewMetal returns a buffer of the right length":
      ## Drive the EPP-M1-baseline raspberry-background smoke tree and
      ## assert the same invariants RS-M5's AppKit test enforces:
      ## payload length matches width*height*4 and every alpha byte
      ## is opaque.
      if not cocoa_metal_capture.isMetalCaptureAvailable():
        skip()
      else:
        resetTree()
        resetCallbacks()
        let r = CocoaRenderer()
        let root = r.createElement("div")
        r.setAttribute(root, "class", "metal-capture-smoke")
        r.setStyle(root, "background-color", "#c83264")  # raspberry

        let width = 320
        let height = 240
        let bytes = cocoa_metal_capture.captureViewMetal(Id(root),
                                                         width, height)
        check bytes.len == width * height * 4

        # Every alpha byte must be opaque. The Metal helper's hybrid
        # AppKit-drawing-plus-Metal-upload path inherits the
        # ``hasAlpha:YES`` invariant from
        # ``bitmapImageRepForCachingDisplayInRect:`` and round-trips
        # the bytes through an ``MTLPixelFormatRGBA8Unorm`` texture
        # without colour-space conversion.
        var allOpaque = true
        var idx = 3
        while idx < bytes.len:
          if bytes[idx] != 0xFF'u8:
            allOpaque = false
            break
          idx += 4
        check allOpaque

    test "captured raspberry tree dominates the red channel":
      ## End-to-end semantic assertion: the raspberry-background div
      ## must produce a raster where the red channel dominates green
      ## and blue across the bulk of pixels. Same shape as RS-M5's
      ## ``red dominant`` check but driven through the Metal helper.
      if not cocoa_metal_capture.isMetalCaptureAvailable():
        skip()
      else:
        resetTree()
        resetCallbacks()
        let r = CocoaRenderer()
        let root = r.createElement("div")
        r.setAttribute(root, "class", "metal-capture-raspberry")
        r.setStyle(root, "background-color", "#c83264")

        let width = 200
        let height = 150
        let bytes = cocoa_metal_capture.captureViewMetal(Id(root),
                                                         width, height)
        check bytes.len == width * height * 4

        var redDominant = 0
        for i in 0 ..< (width * height):
          let off = i * 4
          let pr = int(bytes[off])
          let pg = int(bytes[off + 1])
          let pb = int(bytes[off + 2])
          if pr > pg + 50 and pr > pb + 50 and pb > pg + 20:
            inc redDominant
        # Same threshold the RS-M5 AppKit test uses — at least half
        # the captured raster matches the raspberry channel-relationship
        # signature.
        check redDominant > (width * height) div 2

    test "Metal and AppKit paths produce byte-identical buffers":
      ## EPP-M4 contract: the hybrid Metal path is a strict superset
      ## of the AppKit path — it routes through the GPU's storage but
      ## doesn't perform a colour-space conversion or anti-aliasing
      ## delta. The two paths must produce byte-identical output so a
      ## launcher that fails over from Metal to AppKit mid-stream
      ## doesn't flash a different raster at the browser.
      if not cocoa_metal_capture.isMetalCaptureAvailable():
        skip()
      else:
        resetTree()
        resetCallbacks()
        let r = CocoaRenderer()
        let root = r.createElement("div")
        r.setAttribute(root, "class", "metal-vs-appkit")
        r.setStyle(root, "background-color", "#3264c8")  # cobalt

        let width = 128
        let height = 96
        let metalBytes = cocoa_metal_capture.captureViewMetal(Id(root),
                                                              width,
                                                              height)
        let appkitBytes = cocoa_appkit_capture.captureViewRgba(Id(root),
                                                               width,
                                                               height)
        check metalBytes.len == appkitBytes.len
        check metalBytes.len == width * height * 4
        # Byte-identical buffers — the GPU round-trip in
        # captureViewMetal is a no-op pixel transform until a future
        # sub-agent grows GPU post-processing into the pipeline.
        var diffBytes = 0
        for i in 0 ..< metalBytes.len:
          if metalBytes[i] != appkitBytes[i]:
            inc diffBytes
        check diffBytes == 0

else:
  ## Non-macOS host: EPP-M4 is macOS-only by design.
  suite "EPP-M4: Metal-backed Cocoa capture round-trip":
    test "skipped on non-macOS hosts":
      check true
