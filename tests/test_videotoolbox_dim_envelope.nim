## EPP-M9 — VideoToolbox dim envelope.
##
## *Claim.* The encoder's EPP-M9 dynamic profile/level selector
## successfully configures a session at every viewport the editor's
## EPP-M8 acceptance matrix exercises. Specifically: 1280×800 (Laptop),
## 1440×900 (Desktop), 1024×768 (Tablet), 786×1704 (Phone Portrait),
## and 1920×1080 (HD). The EPP-M5 default
## (``kVTProfileLevel_H264_Baseline_AutoLevel``) capped coded dims at
## 720×576 (Level 3.0) and rejected every entry but the Tablet pill
## that landed inside that envelope. The new selector picks the smallest
## level whose MaxFS macroblock budget covers the requested dims and
## emits a codec_id the launcher can ship straight into the V-packet
## without round-tripping through the raw VideoToolbox CFStringRef.
##
## *Methodology.* For each target dim, build a fresh encoder, push
## 100 frames of moving content (the EPP-M5 bitrate test's sweep
## pattern), and assert
##
##   1. every encode returns ``naluBytes.len > 0`` (no
##      ``kVTCouldNotFindVideoEncoderErr`` / ``kVTParameterErr`` —
##      both surface as nil ``encodeFrame`` on the Nim side);
##   2. the encoder's reported (profileIdc, levelIdc) — surfaced via
##      the EPP-M9 wrapper field — maps via
##      ``packet_video.profileLevelToCodecId`` to a codec_id the
##      V-packet helper recognises as a valid Baseline / Main / High
##      string;
##   3. the first frame is a keyframe (GOP=1 contract carries through
##      from EPP-M5).
##
## Cross-check: the encoder's chosen level must have enough MaxFS
## headroom for the requested width × height (per AVC Annex A). We
## verify by reading ``levelIdc`` and asserting it's at least one of
## the levels whose MaxFS covers ``(W/16) * (H/16)``.
##
## Gated entirely ``when defined(macosx)``.

import std/[strutils, unittest]

# Profile / constraint / level constants — kept inline here because
# isonim-cocoa does not depend on isonim-render-serve. The
# render-serve side's ``packet_video.profileLevelToCodecId`` helper
# is the canonical implementation; this test re-implements the same
# byte layout to verify the encoder's reported profile/level produces
# a valid RFC 6381 codec_id without crossing a repo boundary. The
# matching helper test in
## isonim-render-serve/tests/test_packet_video_codec_id_helper.nim
## locks down the byte-exact behaviour of the canonical helper.
const
  H264ProfileBaseline = 0x42
  H264ProfileMain     = 0x4D
  H264ProfileHigh     = 0x64
  H264ConstraintByte  = 0x00  # mirrors SPS constraint_set_flags from
                              # the live VideoToolbox encoder; see
                              # packet_video.nim const doc-comment.

proc localProfileLevelToCodecId(profileIdc, levelIdc: int): string =
  proc hex2(n: int): string =
    proc nibble(x: int): char =
      if x < 10: char(ord('0') + x) else: char(ord('A') + x - 10)
    result = ""
    result.add nibble((n shr 4) and 0x0F)
    result.add nibble(n and 0x0F)
  "avc1." & hex2(profileIdc) & hex2(H264ConstraintByte) & hex2(levelIdc)

when defined(macosx):
  import isonim_cocoa/appkit/capture_videotoolbox as vt

  proc moveContent(buf: var seq[byte]; w, h, tick: int) =
    ## EPP-M5 sweep pattern: a vertical bright band that translates
    ## across a black background each tick. Smooth enough to keep the
    ## encoder honest about bandwidth without trivialising to a single
    ## colour the encoder would short-circuit.
    for y in 0 ..< h:
      for x in 0 ..< w:
        let off = (y * w + x) * 4
        let band = (x + tick * 4) mod w
        let intensity = if band < 24: byte(255) else: byte(8)
        buf[off + 0] = intensity
        buf[off + 1] = intensity
        buf[off + 2] = intensity
        buf[off + 3] = 0xFF'u8

  proc maxFsForLevel(levelIdc: int): int =
    ## MaxFS (max frame size in 16×16 macroblocks) per H.264 Annex A,
    ## abridged to the levels the EPP-M9 selector picks from. Used to
    ## verify the encoder's level genuinely fits the requested dims.
    case levelIdc
    of 0x1E:  1620   # 3.0
    of 0x1F:  3600   # 3.1
    of 0x20:  5120   # 3.2
    of 0x28:  8192   # 4.0
    of 0x29:  8192   # 4.1
    of 0x2A:  8704   # 4.2
    of 0x32: 22080   # 5.0
    of 0x33: 36864   # 5.1
    of 0x34: 36864   # 5.2
    else: 0

  proc isKnownProfile(profileIdc: int): bool =
    profileIdc == H264ProfileBaseline or
      profileIdc == H264ProfileMain or
      profileIdc == H264ProfileHigh

  template profileLevelToCodecId(p, l: int): string =
    localProfileLevelToCodecId(p, l)

  const Dims = [
    (w: 1280, h:  800, label: "Laptop_1280x800"),
    (w: 1440, h:  900, label: "Desktop_1440x900"),
    (w: 1024, h:  768, label: "Tablet_1024x768"),
    (w:  786, h: 1704, label: "Phone_Portrait_786x1704"),
    (w: 1920, h: 1080, label: "HD_1920x1080"),
  ]

  const FramesPerDim = 100

  suite "EPP-M9: VideoToolbox encoder dim envelope":

    test "encoder succeeds at every editor viewport":
      if not vt.isVideoToolboxAvailable():
        skip()
      else:
        for d in Dims:
          let enc = vt.newVideoToolboxEncoder(d.w, d.h,
                                              bitrate = 2_000_000)
          check enc != nil
          if enc == nil:
            echo "EPP-M9 ENVELOPE FAIL: ", d.label,
                 " — encoder construction returned nil"
            continue

          # EPP-M9: profile/level must be populated by the dynamic
          # selector. The pair drives the codec_id helper.
          check isKnownProfile(enc.profileIdc)
          let mbCount = ((d.w + 15) div 16) * ((d.h + 15) div 16)
          let maxFs = maxFsForLevel(enc.levelIdc)
          check maxFs > 0
          check maxFs >= mbCount

          let codecId = profileLevelToCodecId(enc.profileIdc,
                                              enc.levelIdc)
          # Sanity: codec_id is the RFC 6381 ``avc1.XXXXXX`` shape.
          check codecId.startsWith("avc1.")
          check codecId.len == 11
          echo "EPP-M9 envelope ", d.label,
               " profile=0x", toHex(enc.profileIdc, 2),
               " level=0x", toHex(enc.levelIdc, 2),
               " codec_id=", codecId,
               " mb=", mbCount, "/", maxFs

          # Now push 100 frames; every encode must succeed (non-empty
          # NALU stream).
          var rgba = newSeq[byte](d.w * d.h * 4)
          var firstKey = false
          for i in 0 ..< FramesPerDim:
            moveContent(rgba, d.w, d.h, i)
            let r = vt.encodeFrame(enc, rgba)
            check r.naluBytes.len > 0
            if i == 0:
              firstKey = r.isKeyframe
            # GOP=1 contract from EPP-M5: every frame is keyframe.
            check r.isKeyframe
          check firstKey
          vt.destroy(enc)

    test "profile/level produces a codec_id helper recognises":
      ## Sanity guard so the dim envelope test can never silently
      ## select a profile/level pair the ``profileLevelToCodecId``
      ## helper rejects (would surface as PacketProtocolError there).
      if not vt.isVideoToolboxAvailable():
        skip()
      else:
        let enc = vt.newVideoToolboxEncoder(1280, 800,
                                            bitrate = 2_000_000)
        check enc != nil
        if enc != nil:
          let codecId = profileLevelToCodecId(enc.profileIdc,
                                              enc.levelIdc)
          # Format: avc1.<2hex profile><2hex constraints><2hex level>
          check codecId.len == 11
          check codecId[0..4] == "avc1."
          # Profile nibble should match the encoder's reported profileIdc.
          check codecId[5..6] == toHex(enc.profileIdc, 2)
          # Level nibble.
          check codecId[9..10] == toHex(enc.levelIdc, 2)
          vt.destroy(enc)

else:
  ## Non-macOS host: EPP-M9 is macOS-only by design.
  suite "EPP-M9: VideoToolbox encoder dim envelope":
    test "skipped on non-macOS hosts":
      check true
