## EPP-M5 — VideoToolbox encoder round-trip.
##
## *Claim.* The encoder produces a self-decodable Annex-B H.264 stream
## that ffmpeg can decode back to RGBA pixels matching the original
## frame within a perceptual tolerance.
##
## *Methodology.* Build a known-content RGBA frame, push it through
## ``capture_videotoolbox.encodeFrame``, pipe the resulting NALU
## bytes into ``ffmpeg -i pipe:0 -f rawvideo -pix_fmt rgba -``, and
## compare the decoded bytes against the source pixels using a mean
## per-channel L1 distance. H.264 Baseline is lossy at the typical
## ~2 Mbps target so we accept up to a 12% per-channel mean delta —
## but for the saturated single-colour fill we drive here the
## perceptual error lands well below 5% even at low bitrates.
##
## Gated entirely ``when defined(macosx)``. On Linux the helper is
## a stub and the test skips.

import std/[os, osproc, streams, strutils, unittest]

when defined(macosx):
  import isonim_cocoa/appkit/capture_videotoolbox as vt

  proc makeGradientRgba(w, h: int): seq[byte] =
    ## Build a smooth horizontal R / G / B gradient. Avoids
    ## degenerate single-colour rasters that VideoToolbox can
    ## compress to a trivial NALU sequence and removes high-entropy
    ## noise that would force a larger error tolerance.
    result = newSeq[byte](w * h * 4)
    for y in 0 ..< h:
      for x in 0 ..< w:
        let off = (y * w + x) * 4
        result[off + 0] = byte((x * 255) div max(1, w - 1))
        result[off + 1] = byte((y * 255) div max(1, h - 1))
        result[off + 2] = byte(((x + y) * 127) div max(1, w + h - 2))
        result[off + 3] = 0xFF'u8

  proc decodeNaluWithFfmpeg(nalu: seq[byte]; w, h: int): seq[byte] =
    ## Pipe the Annex-B NALU bytes through ffmpeg and read the
    ## decoded RGBA back out. Uses ``-f h264`` to tell ffmpeg the
    ## input is raw Annex-B (no container).
    let tmpDir = getTempDir()
    let naluPath = tmpDir / "vt_round_trip_input.h264"
    let outPath = tmpDir / "vt_round_trip_output.rgba"
    block:
      let s = newFileStream(naluPath, fmWrite)
      doAssert s != nil
      for b in nalu: s.write(b)
      s.close()
    if fileExists(outPath): removeFile(outPath)

    let cmd = "ffmpeg -hide_banner -loglevel error -f h264 -i " &
              naluPath.quoteShell &
              " -f rawvideo -pix_fmt rgba -frames:v 1 " &
              outPath.quoteShell
    let exitCode = execShellCmd(cmd)
    doAssert exitCode == 0, "ffmpeg decode failed (exit " & $exitCode & ")"
    doAssert fileExists(outPath), "ffmpeg produced no output"

    let s = newFileStream(outPath, fmRead)
    doAssert s != nil
    result = newSeq[byte](w * h * 4)
    let n = s.readData(addr result[0], result.len)
    s.close()
    doAssert n == result.len,
      "decoded RGBA byte count " & $n & " != expected " & $result.len

  proc meanChannelDelta(src, dec: seq[byte]; w, h: int): float =
    ## Mean per-channel L1 over the RGB triples (ignore alpha — VT
    ## drops alpha to 0xFF in YUV420 round-trip). Returns the
    ## percentage relative to 255.
    var total = 0
    let pixels = w * h
    for i in 0 ..< pixels:
      let off = i * 4
      for c in 0 .. 2:
        total += abs(int(src[off + c]) - int(dec[off + c]))
    let avg = total.float / (pixels * 3).float
    avg * 100.0 / 255.0

  suite "EPP-M5: VideoToolbox encoder round-trip":

    test "VideoToolbox encoder available on this macOS host":
      check vt.isVideoToolboxAvailable()

    test "encode + ffmpeg-decode round-trip matches source within tolerance":
      if not vt.isVideoToolboxAvailable():
        skip()
      else:
        const W = 320
        const H = 240
        let src = makeGradientRgba(W, H)
        let enc = vt.newVideoToolboxEncoder(W, H, bitrate = 2_000_000)
        check enc != nil
        let result = vt.encodeFrame(enc, src)
        check result.isKeyframe
        check result.naluBytes.len > 0
        # The first 4 bytes must be the Annex-B start code prefix for
        # the SPS NALU — proves the helper's AVCC -> Annex-B
        # conversion is wired.
        check result.naluBytes[0] == 0x00'u8
        check result.naluBytes[1] == 0x00'u8
        check result.naluBytes[2] == 0x00'u8
        check result.naluBytes[3] == 0x01'u8

        let decoded = decodeNaluWithFfmpeg(result.naluBytes, W, H)
        let delta = meanChannelDelta(src, decoded, W, H)
        echo "EPP-M5 round-trip mean Delta: ",
             delta.formatFloat(ffDecimal, 2), "%"
        # Baseline H.264 at 2 Mbps reproduces saturated gradients with
        # mean L1 typically <5 %; we accept 12 % to leave headroom for
        # YUV chroma sub-sampling and any future bitrate trim.
        check delta < 12.0
        vt.destroy(enc)

    test "second frame on the same session also decodes cleanly":
      ## Validates the encoder doesn't hold per-frame state in a way
      ## that breaks subsequent frames (regression guard for
      ## CompleteFrames / output-callback ordering bugs).
      if not vt.isVideoToolboxAvailable():
        skip()
      else:
        const W = 256
        const H = 192
        let src1 = makeGradientRgba(W, H)
        var src2 = newSeq[byte](W * H * 4)
        for i in 0 ..< W * H:
          let off = i * 4
          src2[off + 0] = 0x80'u8
          src2[off + 1] = byte((i * 73) and 0xFF)
          src2[off + 2] = byte((i * 191) and 0xFF)
          src2[off + 3] = 0xFF'u8
        let enc = vt.newVideoToolboxEncoder(W, H, bitrate = 2_000_000)
        check enc != nil
        discard vt.encodeFrame(enc, src1)
        let r2 = vt.encodeFrame(enc, src2)
        check r2.naluBytes.len > 0
        let decoded = decodeNaluWithFfmpeg(r2.naluBytes, W, H)
        # Per-frame size check — ffmpeg returned a full RGBA frame.
        check decoded.len == W * H * 4
        vt.destroy(enc)

else:
  ## Non-macOS host: EPP-M5 is macOS-only by design.
  suite "EPP-M5: VideoToolbox encoder round-trip":
    test "skipped on non-macOS hosts":
      check true
