## EPP-M5 — VideoToolbox resize lifecycle.
##
## *Claim.* The encoder is dimension-bound (VTCompressionSession is
## allocated at a specific width / height). On resize the launcher
## tears down the old session and builds a new one; the EPP-M5 brief
## acknowledges this and the audit § 7.4 documents it as the
## canonical lifecycle.
##
## *Methodology.* Build a 320×240 encoder, encode a frame, destroy
## the session, build a fresh 640×480 encoder, encode a frame at the
## new dimensions, and assert ffmpeg decodes the second frame at the
## new resolution.
##
## Gated entirely ``when defined(macosx)``.

import std/[os, osproc, streams, strutils, unittest]

when defined(macosx):
  import isonim_cocoa/appkit/capture_videotoolbox as vt

  proc makeUniformRgba(w, h: int; r, g, b: byte): seq[byte] =
    result = newSeq[byte](w * h * 4)
    for i in 0 ..< w * h:
      let off = i * 4
      result[off + 0] = r
      result[off + 1] = g
      result[off + 2] = b
      result[off + 3] = 0xFF'u8

  proc decodeDimsWithFfprobe(nalu: seq[byte]): tuple[w, h: int] =
    ## Inspect the encoded stream with ``ffprobe`` to extract the
    ## decoded width + height. ffprobe parses the SPS NALU to find
    ## the dims, so we don't rely on the launcher knowing them.
    let tmpDir = getTempDir()
    let naluPath = tmpDir / "vt_resize_input.h264"
    block:
      let s = newFileStream(naluPath, fmWrite)
      doAssert s != nil
      for b in nalu: s.write(b)
      s.close()
    # Use ffprobe to extract width / height.
    let cmd = "ffprobe -hide_banner -v error -select_streams v:0 " &
              "-show_entries stream=width,height " &
              "-of csv=p=0 " & naluPath.quoteShell
    let (output, exitCode) = execCmdEx(cmd)
    doAssert exitCode == 0,
      "ffprobe failed (exit " & $exitCode & "): " & output
    let parts = output.strip.split(',')
    doAssert parts.len == 2, "ffprobe output unexpected: " & output
    result = (parts[0].parseInt, parts[1].parseInt)

  suite "EPP-M5: VideoToolbox resize lifecycle":

    test "encoder rebuilt at new dimensions encodes cleanly":
      if not vt.isVideoToolboxAvailable():
        skip()
      else:
        # Step 1: encode at 320x240.
        var enc = vt.newVideoToolboxEncoder(320, 240, bitrate = 1_500_000)
        check enc != nil
        let small = makeUniformRgba(320, 240, 0x40, 0x80, 0xC0)
        let result1 = vt.encodeFrame(enc, small)
        check result1.naluBytes.len > 0
        let dims1 = decodeDimsWithFfprobe(result1.naluBytes)
        check dims1.w == 320
        check dims1.h == 240
        # Step 2: tear down the small session.
        vt.destroy(enc)
        # Step 3: simulate iekResize -> rebuild at 640x480.
        enc = vt.newVideoToolboxEncoder(640, 480, bitrate = 1_500_000)
        check enc != nil
        let large = makeUniformRgba(640, 480, 0xC0, 0x40, 0x80)
        let result2 = vt.encodeFrame(enc, large)
        check result2.naluBytes.len > 0
        let dims2 = decodeDimsWithFfprobe(result2.naluBytes)
        check dims2.w == 640
        check dims2.h == 480
        # Step 4: also test growing further -> 786x1704 (the EPP-M5
        # spec brief's mobile-portrait test target).
        vt.destroy(enc)
        enc = vt.newVideoToolboxEncoder(786, 1704, bitrate = 2_500_000)
        check enc != nil
        let portrait = makeUniformRgba(786, 1704, 0x80, 0x80, 0x80)
        let result3 = vt.encodeFrame(enc, portrait)
        check result3.naluBytes.len > 0
        let dims3 = decodeDimsWithFfprobe(result3.naluBytes)
        check dims3.w == 786
        check dims3.h == 1704
        vt.destroy(enc)

    test "encoding at wrong dimensions for the session is rejected":
      ## Defence in depth: the helper rejects RGBA buffers whose size
      ## doesn't match the encoder's width / height. Catches launcher
      ## bugs where the resize fires AFTER the next render-frame.
      if not vt.isVideoToolboxAvailable():
        skip()
      else:
        let enc = vt.newVideoToolboxEncoder(160, 120, bitrate = 1_000_000)
        check enc != nil
        let mismatched = makeUniformRgba(320, 240, 0x10, 0x20, 0x30)
        expect Defect:
          discard vt.encodeFrame(enc, mismatched)
        vt.destroy(enc)

else:
  suite "EPP-M5: VideoToolbox resize lifecycle":
    test "skipped on non-macOS hosts":
      check true
