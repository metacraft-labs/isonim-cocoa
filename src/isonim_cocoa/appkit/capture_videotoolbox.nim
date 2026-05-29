## VideoToolbox H.264 encoder — thin Nim wrapper around
## ``isonim_cocoa/testing/capture_videotoolbox.m``.
##
## EPP-M5. The audit (``isonim/docs/preview-perf-audit-EPP-M1.md``
## § 2.1) identified VideoToolbox's ``VTCompressionSession`` as the
## canonical macOS hardware H.264 encoder for the EPP campaign and
## confirmed zero existing bindings in the workspace. This module is
## the Nim-side entry point.
##
## Encoder lifecycle:
##
## * ``newVideoToolboxEncoder(w, h, bitrate)`` allocates a session.
##   The VTCompressionSession is dimension-bound; callers re-create
##   the encoder on every resize.
## * ``encodeFrame(rgba)`` blocks until the encoder's output
##   callback has produced bytes for the current frame and returns
##   the Annex-B NALU sequence plus an ``isKeyframe`` flag.
## * ``destroy(enc)`` invalidates the session and frees the backing
##   memory. Calling ``encodeFrame`` after destroy raises ``Defect``.
##
## On Linux this module compiles to a stub: the type stays defined,
## ``isVideoToolboxAvailable()`` returns false, the constructor
## returns nil, and ``encodeFrame`` raises ``Defect``. The launcher
## composition handles the fallback to the F-packet path so the
## bridge integration code is platform-agnostic.

import isonim_cocoa/objc_runtime

type
  VideoToolboxEncoder* = ref object
    ## Opaque handle around the ObjC-side ``CtVTEncoder`` struct.
    ## The void pointer is owned and freed by ``destroy``.
    ##
    ## EPP-M9 added ``profileIdc`` / ``levelIdc`` — populated at
    ## construction by the dynamic profile/level selector the ObjC
    ## helper now runs (``pickProfileLevelForDims``). These are the
    ## H.264 ProfileIDC / LevelIDC bytes the encoder is actually
    ## producing; the V-packet ``codec_id`` is built from them via
    ## ``packet_video.profileLevelToCodecId`` so the wire-advertised
    ## codec string can never drift from the bytes the encoder emits.
    width*, height*: int
    bitrate*: int
    profileIdc*: int
    levelIdc*: int
    handle: pointer

  VideoToolboxEncodedFrame* = object
    ## One encode result.
    naluBytes*: seq[byte]   ## Annex-B framed, ready for the V packet
    isKeyframe*: bool

when defined(macosx):
  {.passL: "-framework VideoToolbox -framework CoreMedia " &
            "-framework CoreVideo -framework Foundation".}

  {.compile: currentSourcePath()[0..^(len("capture_videotoolbox.nim") + 1)] &
             "../testing/capture_videotoolbox.m".}

  proc nim_videotoolbox_available(): cint {.importc, cdecl.}

  proc vt_encoder_create(width, height, bitrate, gop: cint): pointer
    {.importc, cdecl.}

  proc vt_encoder_encode(handle: pointer; rgba: ptr UncheckedArray[byte];
                          width, height: cint;
                          outBuf: ptr UncheckedArray[byte];
                          outCap: cint;
                          outLen: ptr cint;
                          outIsKeyframe: ptr cint): cint
    {.importc, cdecl.}

  proc vt_encoder_get_extra_data(handle: pointer;
                                  outBuf: ptr UncheckedArray[byte];
                                  outCap: cint;
                                  outLen: ptr cint): cint
    {.importc, cdecl.}

  proc vt_encoder_get_profile_level(handle: pointer;
                                     outProfileIdc, outLevelIdc: ptr cint): cint
    {.importc, cdecl.}

  proc vt_encoder_destroy(handle: pointer) {.importc, cdecl.}

  proc isVideoToolboxAvailable*(): bool =
    ## Probe whether VideoToolbox can create an H.264 encoder on this
    ## host. Internally allocates and destroys a 16×16 throwaway
    ## session; the cost is bounded (~hundreds of microseconds) so
    ## launchers can call this on boot without measurable startup
    ## impact.
    nim_videotoolbox_available() != 0

  proc newVideoToolboxEncoder*(width, height: int;
                                bitrate = 2_000_000;
                                gop = 1): VideoToolboxEncoder =
    ## Construct an encoder. Returns nil if VideoToolbox could not
    ## create the session (no hardware encoder, unsupported
    ## dimensions, sandboxing edge case). Callers must check for nil
    ## before calling ``encodeFrame``.
    if width <= 0 or height <= 0:
      return nil
    let h = vt_encoder_create(cint(width), cint(height),
                              cint(bitrate), cint(gop))
    if h == nil:
      return nil
    # EPP-M9: read back the dynamically-selected profile/level the
    # ObjC helper picked for these dims. The pair drives the V-packet
    # codec_id the launcher advertises to the browser's
    # ``VideoDecoder.configure`` call, so we surface it on the Nim-
    # side handle for the render-serve adapter to consume.
    var pi: cint = 0
    var li: cint = 0
    discard vt_encoder_get_profile_level(h, addr pi, addr li)
    VideoToolboxEncoder(width: width, height: height,
                        bitrate: bitrate,
                        profileIdc: int(pi), levelIdc: int(li),
                        handle: h)

  proc destroy*(enc: VideoToolboxEncoder) =
    if enc == nil or enc.handle == nil: return
    vt_encoder_destroy(enc.handle)
    enc.handle = nil

  proc encodeFrame*(enc: VideoToolboxEncoder;
                     rgba: openArray[byte]): VideoToolboxEncodedFrame =
    ## Encode a single RGBA frame. Returns the Annex-B byte stream
    ## (SPS / PPS prepended on every keyframe per the GOP=1 contract)
    ## plus an ``isKeyframe`` flag.
    ##
    ## Raises ``Defect`` when:
    ##
    ## * the encoder is nil or already destroyed,
    ## * ``rgba.len != width * height * 4``,
    ## * VideoToolbox returns a non-success status (the encoder is
    ##   left in a recoverable state; callers may try again with a
    ##   fresh frame),
    ## * the output buffer overflows the pre-sized 4 MB collection
    ##   buffer (a 2 Mbps stream at 60 FPS lands at ~33 KB / frame;
    ##   the 4 MB ceiling carries 100× headroom for pathological
    ##   keyframes on a large surface).
    if enc == nil or enc.handle == nil:
      raise newException(Defect,
        "VideoToolboxEncoder is nil or already destroyed")
    let expected = enc.width * enc.height * 4
    if rgba.len != expected:
      raise newException(Defect,
        "RGBA buffer length " & $rgba.len & " does not match " &
        "width * height * 4 = " & $expected)

    # 4 MB ceiling — see docstring for sizing rationale.
    const outCap = 4 * 1024 * 1024
    var outBuf = newSeq[byte](outCap)
    var outLen: cint = 0
    var outKey: cint = 0
    let rgbaPtr = cast[ptr UncheckedArray[byte]](unsafeAddr rgba[0])
    let outPtr = cast[ptr UncheckedArray[byte]](addr outBuf[0])
    let ok = vt_encoder_encode(enc.handle, rgbaPtr,
                                cint(enc.width), cint(enc.height),
                                outPtr, cint(outCap),
                                addr outLen, addr outKey)
    if ok == 0:
      raise newException(Defect,
        "VTCompressionSessionEncodeFrame failed (outLen=" & $outLen & ")")
    var nalu = newSeq[byte](int(outLen))
    for i in 0 ..< int(outLen): nalu[i] = outBuf[i]
    VideoToolboxEncodedFrame(naluBytes: nalu, isKeyframe: outKey != 0)

  proc getExtraData*(enc: VideoToolboxEncoder): seq[byte] =
    ## Read back the SPS/PPS parameter sets in Annex-B framing. Only
    ## populated after the first successful ``encodeFrame``; returns
    ## an empty seq before that.
    if enc == nil or enc.handle == nil:
      return @[]
    const cap = 512
    var buf = newSeq[byte](cap)
    var outLen: cint = 0
    let p = cast[ptr UncheckedArray[byte]](addr buf[0])
    let ok = vt_encoder_get_extra_data(enc.handle, p, cint(cap), addr outLen)
    if ok == 0:
      return @[]
    var sps = newSeq[byte](int(outLen))
    for i in 0 ..< int(outLen): sps[i] = buf[i]
    sps

else:
  ## Linux / non-macOS stub. The launcher composition falls back to
  ## the raw F-packet path when ``isVideoToolboxAvailable`` returns
  ## false; this body lets every cross-platform module that imports
  ## the wrapper compile without an ``#ifdef`` sprinkle.

  proc isVideoToolboxAvailable*(): bool = false

  proc newVideoToolboxEncoder*(width, height: int;
                                bitrate = 2_000_000;
                                gop = 1): VideoToolboxEncoder =
    discard width; discard height; discard bitrate; discard gop
    nil

  proc destroy*(enc: VideoToolboxEncoder) = discard

  proc encodeFrame*(enc: VideoToolboxEncoder;
                     rgba: openArray[byte]): VideoToolboxEncodedFrame =
    raise newException(Defect,
      "VideoToolbox encoder is not available on this platform; " &
      "callers must check isVideoToolboxAvailable() first")

  proc getExtraData*(enc: VideoToolboxEncoder): seq[byte] = @[]
