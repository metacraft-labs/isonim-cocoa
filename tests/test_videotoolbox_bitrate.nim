## EPP-M5 — VideoToolbox bandwidth envelope.
##
## *Claim.* Encoding 100 frames of moving content at the EPP-M5
## default ~2 Mbps target keeps the mean output bytes-per-frame
## inside a sensible envelope. At 30 FPS / 2 Mbps the budget is
## 2_000_000 / 30 / 8 ≈ 8.3 KB / frame. EPP-M5 ships GOP=1 (every
## frame is keyframe + SPS/PPS prepended), which bumps each frame
## by ~5×; we accept up to 250_000 bytes / frame at 320x240.
##
## The test also prints the percentile distribution so a future
## regression has a clear before/after baseline.
##
## Gated entirely ``when defined(macosx)``.

import std/[algorithm, monotimes, strutils, times, unittest]

when defined(macosx):
  import isonim_cocoa/appkit/capture_videotoolbox as vt

  const
    FrameCount = 100
    Width      = 320
    Height     = 240
    Bitrate    = 2_000_000
    # Per-frame upper bound: every frame is a keyframe so the per-frame
    # byte count is much higher than what an IPB stream would produce.
    # We assert mean stays under 250 KB / frame which the actual
    # encoder beats by an order of magnitude on smooth content.
    MaxMeanBytesPerFrame = 250_000

  proc moveContent(buf: var seq[byte]; w, h, tick: int) =
    ## Animate a simple horizontal sweep. Each tick shifts a vertical
    ## bright band by 4 pixels across a black background. Smooth
    ## content keeps the bitrate predictable without giving the
    ## encoder a trivial single-colour shortcut.
    for y in 0 ..< h:
      for x in 0 ..< w:
        let off = (y * w + x) * 4
        let band = (x + tick * 4) mod w
        let intensity = if band < 24: byte(255) else: byte(8)
        buf[off + 0] = intensity
        buf[off + 1] = intensity
        buf[off + 2] = intensity
        buf[off + 3] = 0xFF'u8

  suite "EPP-M5: VideoToolbox bandwidth envelope":

    test "100-frame mean output bytes/frame within envelope":
      if not vt.isVideoToolboxAvailable():
        skip()
      else:
        let enc = vt.newVideoToolboxEncoder(Width, Height, Bitrate)
        check enc != nil
        var rgba = newSeq[byte](Width * Height * 4)
        var perFrame = newSeq[int](FrameCount)
        var perFrameMs = newSeq[float](FrameCount)
        var totalBytes = 0

        # Warm-up: first frame pays the encoder priming cost. Discard.
        moveContent(rgba, Width, Height, 0)
        discard vt.encodeFrame(enc, rgba)

        for i in 0 ..< FrameCount:
          moveContent(rgba, Width, Height, i + 1)
          let start = getMonoTime()
          let r = vt.encodeFrame(enc, rgba)
          let elapsed = getMonoTime() - start
          perFrame[i] = r.naluBytes.len
          perFrameMs[i] = elapsed.inMicroseconds.float / 1000.0
          totalBytes += r.naluBytes.len

        let meanBytes = totalBytes div FrameCount
        var sortedBytes = perFrame
        sortedBytes.sort()
        perFrameMs.sort()
        echo "EPP-M5 bandwidth ", Width, "x", Height, " @ ",
             Bitrate, " bps (GOP=1, 100 frames):"
        echo "  bytes/frame: mean=", meanBytes,
             " p50=", sortedBytes[FrameCount div 2],
             " p90=", sortedBytes[(FrameCount * 9) div 10],
             " p99=", sortedBytes[(FrameCount * 99) div 100],
             " min=", sortedBytes[0],
             " max=", sortedBytes[FrameCount - 1]
        echo "  latency ms: p50=",
             perFrameMs[FrameCount div 2].formatFloat(ffDecimal, 2),
             " p90=", perFrameMs[(FrameCount * 9) div 10].formatFloat(ffDecimal, 2),
             " p99=", perFrameMs[(FrameCount * 99) div 100].formatFloat(ffDecimal, 2),
             " min=", perFrameMs[0].formatFloat(ffDecimal, 2),
             " max=", perFrameMs[FrameCount - 1].formatFloat(ffDecimal, 2)

        check meanBytes < MaxMeanBytesPerFrame
        check sortedBytes[0] > 0
        vt.destroy(enc)

else:
  suite "EPP-M5: VideoToolbox bandwidth envelope":
    test "skipped on non-macOS hosts":
      check true
