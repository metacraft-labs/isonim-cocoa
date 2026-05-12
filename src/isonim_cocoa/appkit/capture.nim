## AppKit headless capture — render an NSView to a canonical RGBA8888
## row-major byte buffer without requiring a window or event loop.
##
## This is the bytes-only sibling of `isonim_cocoa/testing/snapshots`'s
## PNG capture: instead of round-tripping through PNG (which is wasteful
## when the consumer needs raw pixels), `captureViewRgba` returns the
## already-swizzled pixel buffer directly. The capture path itself is
## identical — `bitmapImageRepForCachingDisplayInRect:` +
## `cacheDisplayInRect:toBitmapImageRep:` — but the format-conversion
## step is moved out of `NSBitmapImageRep representationUsingType:` and
## into a hand-rolled per-row swizzler that respects the rep's
## `bitmapFormat` (alpha-first / little-endian variants).
##
## Used by `isonim-render-serve`'s RS-M5 Cocoa adapter as the
## `bitmapImageRepForCachingDisplayInRect`-driven primary capture path.

import isonim_cocoa/objc_runtime

{.passL: "-framework AppKit".}

{.compile: currentSourcePath()[0..^(len("capture.nim") + 1)] &
           "../testing/capture_rgba.m".}

proc nim_capture_view_rgba(view: Id; width, height: cint;
                            buf: ptr UncheckedArray[byte]): cint
  {.importc, cdecl.}

proc captureViewRgba*(view: Id; width, height: int): seq[byte] =
  ## Render `view` headlessly into a `width * height * 4` byte buffer
  ## in canonical RGBA8888 row-major order. Returns an empty seq if
  ## the underlying AppKit capture failed (nil view, bad dimensions,
  ## unsupported pixel format).
  ##
  ## The view's frame is set to `(0, 0, width, height)` and its
  ## subtree laid out before drawing. On retina hosts the rep
  ## `bitmapImageRepForCachingDisplayInRect:` returns is larger than
  ## the requested `width * height`; we nearest-neighbor downscale to
  ## the wire size so the bridge's `F` packet payload length stays
  ## exactly `width * height * 4`.
  if width <= 0 or height <= 0 or pointer(view) == nil:
    return @[]
  result = newSeq[byte](width * height * 4)
  let ok = nim_capture_view_rgba(view, cint(width), cint(height),
    cast[ptr UncheckedArray[byte]](addr result[0]))
  if ok == 0:
    return @[]
