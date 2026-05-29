## Metal-backed headless capture — render an NSView through CARenderer
## into a Metal texture and read it back as canonical RGBA8888 row-
## major bytes.
##
## EPP-M4. The audit (``isonim/docs/preview-perf-audit-EPP-M1.md``
## § 1.3) identifies a Metal-backed offscreen render via
## ``CARenderer`` + ``CAMetalLayer`` / ``MTLTexture`` as feasible from
## the existing launcher architecture (the headless NSView is already
## layer-backed via ``setWantsLayer:YES`` in
## ``isonim-render-serve/src/isonim_render_serve/adapters/cocoa_adapter.nim``
## line 340-356) and predicts a per-frame budget of 5-15 ms on M1.
##
## This module wraps ``isonim_cocoa/testing/capture_metal.m`` which
## implements the recipe documented in its header.
##
## The Metal capture path is the EPP-M4 default on macOS. When Metal
## is unavailable (older OS, headless VM without a GPU device, certain
## sandbox configurations) ``captureViewMetal`` returns an empty seq
## and callers must fall back to ``capture.captureViewRgba``
## (the AppKit ``cacheDisplayInRect:toBitmapImageRep:`` path).

import isonim_cocoa/objc_runtime

when defined(macosx):
  {.passL: "-framework AppKit -framework Metal -framework QuartzCore".}

  # The ObjC helper uses MRR (manual retain/release): explicit
  # ``[obj retain]`` / ``[obj release]`` calls inside the helper own
  # CARenderer + MTLTexture across the per-call autoreleasepool. Mixing
  # ARC into the workspace's .m files was tried first and rejected:
  # ``passC: "-fobjc-arc"`` is a module-global Nim pragma and breaks the
  # sibling ``isonim_cocoa/appkit/media_helper.m`` (which uses explicit
  # ``[obj release]`` calls) when it lands in the same compile pass.
  {.compile: currentSourcePath()[0..^(len("capture_metal.nim") + 1)] &
             "../testing/capture_metal.m".}

  proc nim_capture_view_metal(view: Id; width, height: cint;
                               buf: ptr UncheckedArray[byte]): cint
    {.importc, cdecl.}

  proc nim_metal_capture_available(): cint {.importc, cdecl.}

  proc isMetalCaptureAvailable*(): bool =
    ## ``true`` when ``MTLCreateSystemDefaultDevice`` returns a non-nil
    ## device on this host. The probe is cheap (Apple caches the system
    ## default device internally after the first hit) so callers can ask
    ## once on launcher boot and pin the capture path for the lifetime
    ## of the bridge connection.
    nim_metal_capture_available() != 0

  proc captureViewMetal*(view: Id; width, height: int): seq[byte] =
    ## Render ``view`` headlessly through a CARenderer-backed
    ## ``MTLTexture`` of ``width × height`` pixels and return the result
    ## in canonical RGBA8888 row-major byte order.
    ##
    ## Returns an empty seq if the helper failed (nil view, bad
    ## dimensions, Metal device unavailable, CARenderer init failure).
    ## In that case callers should fall back to the AppKit
    ## ``captureViewRgba`` path documented in
    ## ``isonim_cocoa/appkit/capture``.
    ##
    ## The Metal device + command queue + texture are cached internally
    ## in the ObjC helper for the lifetime of the process, keyed on
    ## (width, height). Steady-state calls at a fixed capture size pay
    ## zero per-frame GPU allocation cost.
    if width <= 0 or height <= 0 or pointer(view) == nil:
      return @[]
    result = newSeq[byte](width * height * 4)
    let ok = nim_capture_view_metal(view, cint(width), cint(height),
      cast[ptr UncheckedArray[byte]](addr result[0]))
    if ok == 0:
      return @[]

else:
  proc isMetalCaptureAvailable*(): bool = false
    ## EPP-M4 is macOS-only by design. On Linux / other hosts the
    ## probe unconditionally reports unavailable so callers fall
    ## through to the AppKit path (which on Linux is itself a
    ## placeholder; see ``cocoa_adapter.nim``).

  proc captureViewMetal*(view: Id; width, height: int): seq[byte] = @[]
