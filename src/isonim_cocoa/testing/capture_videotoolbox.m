// capture_videotoolbox.m — EPP-M5 ObjC helper: own a
// ``VTCompressionSession`` configured for low-latency Baseline H.264,
// feed RGBA frames into it, and collect the emitted NALU bytes as a
// flat Annex-B stream.
//
// Per the EPP-M1 audit § 2.1 there is no existing VideoToolbox FFI in
// the workspace; this is greenfield. The helper API mirrors the
// ObjC-shim shape from ``capture_metal.m`` (init / per-frame / destroy
// triplet returning ``int`` for success-or-failure) so the Nim
// wrapper at ``isonim_cocoa/appkit/capture_videotoolbox.nim`` can
// follow the same pattern as ``capture_metal.nim``.
//
// Session configuration (per the EPP-M5 brief + audit § 2.1, updated
// per the EPP-M9 audit § 2.1 dim-cap finding):
//
//   ProfileLevel:          DYNAMIC — selected per encoded dimensions.
//                          See pickProfileLevelForDims() below.
//                          Replaces EPP-M5's hard-coded
//                          ``kVTProfileLevel_H264_Baseline_AutoLevel``
//                          which the EPP-M9 audit traced to a Level 3.0
//                          coded-dim cap (720×576) that rejected the
//                          editor's Laptop / Desktop viewports
//                          (1280×800, 1440×900).
//   RealTime:              kCFBooleanTrue
//   AllowFrameReordering:  kCFBooleanFalse
//   MaxKeyFrameInterval:   1                   (every frame is IDR)
//   AverageBitRate:        ~2 Mbps (caller-tunable)
//
// Encoder lifecycle: the VTCompressionSession is dimension-bound.
// Callers re-create the session via ``vt_encoder_create`` when the
// surface resizes; the Nim wrapper takes care of the
// invalidate / destroy pair. EPP-M9 adds
// ``vt_encoder_get_profile_level`` so the launcher can read back the
// chosen profile/level and feed it to the V-packet codec_id helper
// (avc1.<ProfileIDC><Constraints><LevelIDC>, RFC 6381).
//
// NALU output framing: the helper collects raw Annex-B bytes
// (start code prefixes 0x00000001) for both SPS / PPS parameter sets
// (carried as a CMVideoFormatDescription extension on the first
// sample buffer) AND the per-frame slice NALUs. Each frame's NALUs
// are prepended with SPS/PPS the first time the descriptor changes;
// downstream the launcher can drop SPS/PPS after the first
// successful decode, but EPP-M5 always emits them inline so the
// browser-side decoder configuration is identical for every V packet.
//
// The codec emits AVCC framing natively (length-prefixed NALUs
// inside the CMBlockBuffer); we transcode to Annex-B at copy-out
// time so ffmpeg / WebCodecs accept the bytes without an extra
// parser stage.

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Public availability probe.
// ---------------------------------------------------------------------------
//
// Returns 1 when VideoToolbox + a hardware H.264 encoder are usable on
// this host. We instantiate a 16×16 throwaway session — the cheapest
// way to verify the encoder is actually available without paying for
// a full encode. The cost is one VTCompressionSession alloc + destroy
// (~hundreds of microseconds), called at most once per launcher boot.
//
// On hosts without a hardware H.264 encoder (sandboxed iOS Simulator,
// the rare macOS install where the encoder service is unreachable) the
// call returns 0 and the launcher falls back to the F-packet path.
int nim_videotoolbox_available(void) {
    @autoreleasepool {
        VTCompressionSessionRef probe = NULL;
        OSStatus status = VTCompressionSessionCreate(
            kCFAllocatorDefault,
            16, 16,
            kCMVideoCodecType_H264,
            NULL, NULL, NULL,
            NULL, NULL,
            &probe);
        if (status != noErr || probe == NULL) {
            if (probe != NULL) { VTCompressionSessionInvalidate(probe); CFRelease(probe); }
            return 0;
        }
        VTCompressionSessionInvalidate(probe);
        CFRelease(probe);
        return 1;
    }
}

// ---------------------------------------------------------------------------
// Encoder state.
// ---------------------------------------------------------------------------
//
// One ``CtVTEncoder`` instance per encoder. The output callback runs
// synchronously on the encoder's internal thread; we lock the bytes
// buffer with a serial dispatch queue. Because ``vt_encoder_encode``
// blocks via ``VTCompressionSessionCompleteFrames`` after each push,
// the callback finishes before the call returns and there is no
// outstanding work at the destroy point.

// H.264 profile / level identifiers — match the RFC 6381 codec_id
// triplet that drives the browser's ``VideoDecoder.configure({codec})``
// call. ``profileIdc`` is the AVC ProfileIDC byte (Baseline=0x42,
// Main=0x4D, High=0x64); ``levelIdc`` is the AVC level encoded as the
// integer level * 10 (so 3.0 = 30 = 0x1E, 4.0 = 40 = 0x28). The codec
// string the launcher hands the browser is
// ``avc1.<profileIdc><constraints><levelIdc>`` with each pair hex-
// encoded; we keep the constraints field fixed at 0xE0 (the bit
// pattern Apple's encoder emits — constraint_set0..2 = 1 for
// "compatible with stricter profiles") so the browser's codec parser
// accepts the string regardless of the selected level.
typedef struct CtVTEncoder {
    VTCompressionSessionRef session;
    int width;
    int height;
    int bitrate;          // average bps target
    int gop;              // max key frame interval (1 = every frame is keyframe)
    int64_t frameIndex;   // monotonic frame counter; drives the PTS
    int hasSentExtraData; // 1 once SPS/PPS were attached to a frame
    int extraDataLen;     // bytes in extraData buffer (0 if none)
    unsigned char extraData[512]; // SPS/PPS in Annex-B framing
    int profileIdc;       // EPP-M9: chosen H.264 ProfileIDC (0x42/0x4D/0x64)
    int levelIdc;         // EPP-M9: chosen H.264 LevelIDC (e.g. 0x1E, 0x28)

    // Per-encode collection buffer. Reset before each
    // ``vt_encoder_encode`` call; the output callback appends here.
    unsigned char *collect;
    size_t collectCap;
    size_t collectLen;
    int collectIsKeyframe;
    int collectIncludedExtra;
} CtVTEncoder;

// ---------------------------------------------------------------------------
// AVCC → Annex-B conversion.
// ---------------------------------------------------------------------------

static void appendBytes(CtVTEncoder *enc,
                        const unsigned char *src, size_t n) {
    if (enc->collectLen + n > enc->collectCap) {
        size_t newCap = enc->collectCap * 2;
        if (newCap < enc->collectLen + n) newCap = enc->collectLen + n;
        if (newCap < 4096) newCap = 4096;
        enc->collect = (unsigned char *)realloc(enc->collect, newCap);
        enc->collectCap = newCap;
    }
    memcpy(enc->collect + enc->collectLen, src, n);
    enc->collectLen += n;
}

static const unsigned char kAnnexBStart[4] = { 0x00, 0x00, 0x00, 0x01 };

static void appendAnnexBStart(CtVTEncoder *enc) {
    appendBytes(enc, kAnnexBStart, 4);
}

// Extract SPS/PPS NALUs from the sample buffer's format description and
// store them in ``enc->extraData`` as a contiguous Annex-B blob. Called
// on the first frame; subsequent frames re-use the cached bytes.
static void cacheParameterSets(CtVTEncoder *enc,
                               CMFormatDescriptionRef fmt) {
    if (fmt == NULL) return;
    size_t paramCount = 0;
    OSStatus s = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        fmt, 0, NULL, NULL, &paramCount, NULL);
    if (s != noErr || paramCount == 0) return;

    int written = 0;
    for (size_t i = 0; i < paramCount; i++) {
        const uint8_t *ps = NULL;
        size_t psLen = 0;
        int nalHeaderLen = 0;
        s = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fmt, i, &ps, &psLen, NULL, &nalHeaderLen);
        if (s != noErr || ps == NULL) continue;
        if ((size_t)written + 4 + psLen > sizeof(enc->extraData)) break;
        memcpy(enc->extraData + written, kAnnexBStart, 4);
        written += 4;
        memcpy(enc->extraData + written, ps, psLen);
        written += (int)psLen;
    }
    enc->extraDataLen = written;
}

// AVCC sample buffers carry NALUs as length-prefixed blobs:
//   [4-byte length BE | NALU bytes]+
// We transcode in-place to Annex-B by replacing each length prefix
// with the 0x00000001 start code.
static void appendAVCCToAnnexB(CtVTEncoder *enc,
                               const unsigned char *src, size_t srcLen) {
    size_t off = 0;
    while (off + 4 <= srcLen) {
        uint32_t naluLen = ((uint32_t)src[off] << 24) |
                           ((uint32_t)src[off + 1] << 16) |
                           ((uint32_t)src[off + 2] << 8) |
                           (uint32_t)src[off + 3];
        off += 4;
        if (off + naluLen > srcLen) break;
        appendAnnexBStart(enc);
        appendBytes(enc, src + off, naluLen);
        off += naluLen;
    }
}

// ---------------------------------------------------------------------------
// VTCompressionSession output callback.
// ---------------------------------------------------------------------------
//
// Runs on the encoder's internal serial queue. Because
// ``vt_encoder_encode`` calls ``VTCompressionSessionCompleteFrames``
// before returning, this callback fires synchronously and the
// returned bytes are visible to the caller without any cross-thread
// synchronisation beyond the implicit happens-before
// VTCompressionSessionCompleteFrames provides.

static void vtOutputCallback(void *outputCallbackRefCon,
                              void *sourceFrameRefCon,
                              OSStatus status,
                              VTEncodeInfoFlags infoFlags,
                              CMSampleBufferRef sampleBuffer) {
    (void)sourceFrameRefCon;
    (void)infoFlags;
    CtVTEncoder *enc = (CtVTEncoder *)outputCallbackRefCon;
    if (status != noErr || sampleBuffer == NULL) return;
    if (!CMSampleBufferDataIsReady(sampleBuffer)) return;

    // Keyframe detection: attachment array's first dictionary's
    // kCMSampleAttachmentKey_NotSync key is absent or false for IDR.
    int isKeyframe = 1;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, false);
    if (attachments != NULL && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef d = (CFDictionaryRef)CFArrayGetValueAtIndex(
            attachments, 0);
        if (d != NULL) {
            CFBooleanRef notSync = (CFBooleanRef)CFDictionaryGetValue(
                d, kCMSampleAttachmentKey_NotSync);
            if (notSync != NULL && CFBooleanGetValue(notSync)) {
                isKeyframe = 0;
            }
        }
    }
    enc->collectIsKeyframe = isKeyframe;

    // Cache parameter sets from the format description on the first
    // frame so subsequent frames can reuse the same Annex-B blob.
    if (enc->extraDataLen == 0) {
        CMFormatDescriptionRef fmt =
            CMSampleBufferGetFormatDescription(sampleBuffer);
        cacheParameterSets(enc, fmt);
    }

    // Prepend SPS/PPS to every keyframe. EPP-M5 brief: GOP=1, so every
    // frame is keyframe and every frame ships the parameter sets.
    if (isKeyframe && enc->extraDataLen > 0) {
        appendBytes(enc, enc->extraData,
                    (size_t)enc->extraDataLen);
        enc->collectIncludedExtra = 1;
    }

    // Append the AVCC-framed slice NALUs as Annex-B.
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (block == NULL) return;
    size_t total = CMBlockBufferGetDataLength(block);
    if (total == 0) return;
    unsigned char *buf = (unsigned char *)malloc(total);
    if (buf == NULL) return;
    OSStatus copyStatus = CMBlockBufferCopyDataBytes(block, 0, total, buf);
    if (copyStatus == noErr) {
        appendAVCCToAnnexB(enc, buf, total);
    }
    free(buf);
}

// ---------------------------------------------------------------------------
// Session create / configure.
// ---------------------------------------------------------------------------

static OSStatus setSessionInt(VTCompressionSessionRef session,
                              CFStringRef key, int value) {
    CFNumberRef n = CFNumberCreate(kCFAllocatorDefault,
                                   kCFNumberIntType, &value);
    OSStatus s = VTSessionSetProperty(session, key, n);
    if (n != NULL) CFRelease(n);
    return s;
}

static OSStatus setSessionBool(VTCompressionSessionRef session,
                               CFStringRef key, int value) {
    CFBooleanRef b = value ? kCFBooleanTrue : kCFBooleanFalse;
    return VTSessionSetProperty(session, key, b);
}

// ---------------------------------------------------------------------------
// EPP-M9: profile / level selection.
// ---------------------------------------------------------------------------
//
// H.264 levels cap the coded dimensions, frame rate, and bitrate. Per the
// AVC standard (ITU-T Rec. H.264, Annex A) the relevant per-level
// constraints we care about here are:
//
//   Level 3.0: MaxFS  =  1620 MB  (e.g. 720×576 @ 30 fps)
//   Level 3.1: MaxFS  =  3600 MB  (e.g. 1280×720 @ 30 fps)
//   Level 3.2: MaxFS  =  5120 MB  (e.g. 1280×720 @ 60 fps)
//   Level 4.0: MaxFS  =  8192 MB  (e.g. 2048×1024 @ 30 fps;
//                                  also 1920×1080 @ 30 fps)
//   Level 4.1: MaxFS  =  8192 MB  (higher bitrate budget than 4.0)
//   Level 4.2: MaxFS  =  8704 MB  (e.g. 2048×1080 @ 60 fps)
//   Level 5.0: MaxFS  = 22080 MB  (e.g. 3672×1536; phone portrait
//                                  786×1704 = 5240 MB also fits 4.0
//                                  by total but we step to 5.0 when
//                                  either dimension is large enough
//                                  that 4.0's per-side caps risk
//                                  being tight — see picker below).
//
// One macroblock = 16×16 px so MaxFS in MB = ceil(W/16) * ceil(H/16).
//
// EPP-M5's original ``kVTProfileLevel_H264_Baseline_AutoLevel`` selector
// observed at runtime always produced Level 3.0 NALUs (codec_id
// ``avc1.42E01E``); that capped the coded dim envelope at 720×576 and
// broke the Laptop / Desktop viewports.
//
// EPP-M9 picks the smallest level that fits the requested dims +
// 30 fps target. We prefer Baseline because the browser-side
// WebCodecs decoder has the broadest Baseline support; we step to
// Main/High only if VideoToolbox refuses Baseline at the chosen level
// (which it should not, for any of our target dims).

typedef struct {
    CFStringRef key;     // VTCompression property symbol
    int profileIdc;      // Baseline=0x42, Main=0x4D, High=0x64
    int levelIdc;        // level * 10, e.g. 4.0 -> 0x28
    int maxFs;           // max frame size in 16×16 macroblocks
    int maxSideLen;      // max side length in pixels (sqrt(8*MaxFS))
    const char *label;   // for logging
} CtH264ProfileLevel;

static int macroblockCount(int width, int height) {
    int wMb = (width + 15) / 16;
    int hMb = (height + 15) / 16;
    return wMb * hMb;
}

// Pick the smallest H.264 Baseline level whose MaxFS *and* MaxMBPS
// envelopes cover the requested dims at the EPP-M5 60-fps
// ``ExpectedFrameRate`` hint. AVC levels constrain three things we
// care about here:
//
//   * MaxFS (max frame size in 16×16 macroblocks);
//   * MaxMBPS (max macroblock processing rate, mb/s);
//   * the per-side coded dim — derived from MaxFS as a soft cap.
//
// EPP-M9 audit observation: simply matching MaxFS isn't enough.
// VideoToolbox enforces MaxMBPS strictly when we pin an explicit
// level — at 60 fps a 640×480 frame (1200 mb) exceeds Level 3.0's
// 40500 mb/s envelope (it'd need 72000 mb/s) and the encoder
// silently drops every frame from the output callback. That was the
// regression that produced "0 bytes" naluBytes during EPP-M9
// development. EPP-M5's previous ``Baseline_AutoLevel`` selector
// avoided the trap by letting VideoToolbox pick a Level high enough
// for both the dims AND the frame rate — we replicate the same
// arithmetic explicitly so the (profileIdc, levelIdc) pair the
// launcher advertises in the V-packet codec_id genuinely matches
// what the encoder produces on the wire.
//
// EPP-M9 codec_id-stability observation: in addition to the
// MaxFS / MaxMBPS arithmetic the level picker enforces a *floor*
// of Baseline 4.0 (``0x28``). Two reasons:
//
//   1. The editor's viewport pills (Desktop 1440×900, Laptop
//      1280×800, Tablet 1024×768, Phone 390×844) span a MaxFS range
//      of 600 → 5130 macroblocks. Without a floor the picker would
//      flip between Baseline 3.0/3.1/3.2/4.0/4.2 across viewport
//      switches; each flip changes the V-packet codec_id, which
//      forces the browser's WebCodecs ``VideoDecoder`` to tear
//      down + reconfigure for the new codec string. Chrome's
//      WebCodecs implementation is selective about which exact
//      ``avc1.42E0XX`` strings it accepts — empirically
//      ``avc1.42E020`` (Baseline 3.2) is rejected with
//      "Unsupported configuration" at Chrome 137+ even though the
//      stream is decodable, while ``avc1.42E028`` (Baseline 4.0)
//      is accepted universally. Pinning the floor at Baseline 4.0
//      avoids the rejection and keeps the codec_id stable across
//      the most common viewport switches.
//   2. Baseline 4.0's MaxFS (8192 MB) covers every editor viewport
//      through HD (1920×1080 = 8160 MB), so the floor is "free" —
//      we never under-spec by using it. Above HD the picker steps
//      to 4.2 / 5.0 / 5.x as needed.
//
// Frame-rate target: we pin 60 fps as the upper-bound for the level
// picker so the same encoder works whether the launcher runs at 30
// or 60 fps. 60 fps is more demanding (2× the MaxMBPS budget) so a
// 60-fps-fit level is necessarily a 30-fps-fit level too.
//
// No probe-session round-trip is needed — Baseline is supported at
// every level the macOS 10.9+ SDK exposes (we build against 11.0+)
// so the lookup is purely arithmetic.
static CtH264ProfileLevel pickProfileLevelForDims(int width, int height) {
    int mbCount = macroblockCount(width, height);
    // Target frame rate for the level-picker. EPP-M9 drops this from
    // the EPP-M5 default of 60 to 30 to match the launcher's actual
    // ``--fps 30`` cadence cap (and the ``ExpectedFrameRate`` hint
    // set below). 30 fps halves the MaxMBPS pressure relative to 60
    // fps, so Baseline 4.0 covers every editor viewport through
    // 1920×1080 — keeping the codec_id stable at ``avc1.42E028`` for
    // the entire pinned viewport ladder
    // (Desktop / Laptop / Tablet / Phone). Bump targetFps in lockstep
    // with the ``ExpectedFrameRate`` property set below if a future
    // launcher needs 60 fps.
    const int targetFps = 30;
    int mbPerSecond = mbCount * targetFps;
    // EPP-M9 codec_id-stability floor — see § doc-comment above.
    const int floorLevelIdc = 0x28;  // Baseline 4.0
    static const struct {
        int profileIdc;
        int levelIdc;
        int maxFs;
        int maxMbps;
        const char *label;
    } ladder[] = {
        { 0x42, 0x28,  8192,  245760, "Baseline_4_0" },
        { 0x42, 0x29,  8192,  245760, "Baseline_4_1" },
        { 0x42, 0x2A,  8704,  522240, "Baseline_4_2" },
        { 0x42, 0x32, 22080,  589824, "Baseline_5_0" },
        { 0x42, 0x33, 36864,  983040, "Baseline_5_1" },
        { 0x42, 0x34, 36864, 2073600, "Baseline_5_2" },
    };
    CFStringRef key = NULL;
    for (size_t i = 0; i < sizeof(ladder) / sizeof(ladder[0]); i++) {
        if (ladder[i].levelIdc < floorLevelIdc) continue;
        if (ladder[i].maxFs < mbCount) continue;
        if (ladder[i].maxMbps < mbPerSecond) continue;
        switch (ladder[i].levelIdc) {
        case 0x28: key = kVTProfileLevel_H264_Baseline_4_0; break;
        case 0x29: key = kVTProfileLevel_H264_Baseline_4_1; break;
        case 0x2A: key = kVTProfileLevel_H264_Baseline_4_2; break;
        case 0x32: key = kVTProfileLevel_H264_Baseline_5_0; break;
        case 0x33: key = kVTProfileLevel_H264_Baseline_5_1; break;
        case 0x34: key = kVTProfileLevel_H264_Baseline_5_2; break;
        default: key = NULL; break;
        }
        if (key == NULL) continue;
        CtH264ProfileLevel pl;
        pl.key = key;
        pl.profileIdc = ladder[i].profileIdc;
        pl.levelIdc = ladder[i].levelIdc;
        pl.maxFs = ladder[i].maxFs;
        pl.maxSideLen = 0;
        pl.label = ladder[i].label;
        return pl;
    }
    // Last-resort fallback: dims exceed Baseline 5.2's MaxFS/MaxMBPS.
    // Pin to Baseline 5.2 and let VideoToolbox emit beyond-spec
    // packets; the browser-side WebCodecs decoder will surface any
    // actual rejection.
    CtH264ProfileLevel pl;
    pl.key = kVTProfileLevel_H264_Baseline_5_2;
    pl.profileIdc = 0x42;
    pl.levelIdc = 0x34;
    pl.maxFs = 36864;
    pl.maxSideLen = 0;
    pl.label = "Baseline_5_2_fallback";
    return pl;
}

void *vt_encoder_create(int width, int height, int bitrate, int gop) {
    if (width <= 0 || height <= 0) return NULL;
    @autoreleasepool {
        CtVTEncoder *enc = (CtVTEncoder *)calloc(1, sizeof(CtVTEncoder));
        if (enc == NULL) return NULL;
        enc->width = width;
        enc->height = height;
        enc->bitrate = (bitrate > 0) ? bitrate : 2000000;
        enc->gop = (gop > 0) ? gop : 1;
        enc->frameIndex = 0;
        enc->collectCap = 8192;
        enc->collect = (unsigned char *)malloc(enc->collectCap);
        if (enc->collect == NULL) { free(enc); return NULL; }

        VTCompressionSessionRef session = NULL;
        OSStatus s = VTCompressionSessionCreate(
            kCFAllocatorDefault,
            width, height,
            kCMVideoCodecType_H264,
            NULL, NULL, NULL,
            vtOutputCallback,
            enc,
            &session);
        if (s != noErr || session == NULL) {
            free(enc->collect);
            free(enc);
            return NULL;
        }
        enc->session = session;

        // EPP-M9: dynamic profile/level selection. ``pickProfileLevelForDims``
        // probes a candidate ladder (Baseline 3.0 .. 5.2, then High at
        // the same MaxFS envelope) and returns the smallest entry whose
        // MaxFS covers the requested width × height. The chosen
        // CFStringRef goes straight into the live session via the
        // ProfileLevel property key; the (profileIdc, levelIdc) pair is
        // stashed on the encoder so ``vt_encoder_get_profile_level``
        // can hand it back to the Nim wrapper for the V-packet codec_id.
        CtH264ProfileLevel pl = pickProfileLevelForDims(width, height);
        enc->profileIdc = pl.profileIdc;
        enc->levelIdc = pl.levelIdc;
        (void)VTSessionSetProperty(session,
            kVTCompressionPropertyKey_ProfileLevel,
            pl.key);
        (void)setSessionBool(session,
            kVTCompressionPropertyKey_RealTime, 1);
        (void)setSessionBool(session,
            kVTCompressionPropertyKey_AllowFrameReordering, 0);
        (void)setSessionInt(session,
            kVTCompressionPropertyKey_MaxKeyFrameInterval, enc->gop);
        (void)setSessionInt(session,
            kVTCompressionPropertyKey_AverageBitRate, enc->bitrate);
        // Hint the encoder we're driving real-time content; this nudges
        // rate control toward the bitrate ceiling. EPP-M9 drops the
        // ExpectedFrameRate from 60 to 30 to match the launcher's
        // actual ``--fps 30`` cap; the picker above uses the same
        // value when checking each candidate level's MaxMBPS budget.
        (void)setSessionInt(session,
            kVTCompressionPropertyKey_ExpectedFrameRate, 30);

        // VTCompressionSessionPrepareToEncodeFrames warms the encoder
        // so the first ``EncodeFrame`` call doesn't pay the lazy
        // hardware-handoff cost. Best-effort; ignore errors.
        (void)VTCompressionSessionPrepareToEncodeFrames(session);
        return enc;
    }
}

// ---------------------------------------------------------------------------
// Per-frame encode.
// ---------------------------------------------------------------------------
//
// Steps:
//   1. Allocate a CVPixelBuffer in BGRA format.
//   2. Copy the caller's RGBA bytes into the buffer with channel
//      swizzle (R<->B; A stays in place).
//   3. Call VTCompressionSessionEncodeFrame.
//   4. Block until completion (VTCompressionSessionCompleteFrames).
//   5. Read the collected Annex-B bytes out of ``enc->collect`` and
//      copy them to the caller-supplied output buffer.

int vt_encoder_encode(void *handle,
                       const unsigned char *rgba,
                       int width, int height,
                       unsigned char *out, int outCap,
                       int *outLen, int *outIsKeyframe) {
    if (handle == NULL || rgba == NULL || out == NULL ||
        outLen == NULL || width <= 0 || height <= 0) {
        return 0;
    }
    @autoreleasepool {
        CtVTEncoder *enc = (CtVTEncoder *)handle;
        if (enc->session == NULL) return 0;
        if (width != enc->width || height != enc->height) {
            // Caller violated the resize contract — the session is
            // dimension-bound. Surface as failure so the launcher
            // re-creates the session.
            return 0;
        }

        enc->collectLen = 0;
        enc->collectIsKeyframe = 0;
        enc->collectIncludedExtra = 0;

        // 1. CVPixelBuffer allocation. BGRA matches what
        //    VideoToolbox accepts natively without an explicit
        //    swizzle property; the Y'CbCr conversion happens inside
        //    the encoder.
        CVPixelBufferRef pb = NULL;
        NSDictionary *attrs = @{
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVReturn r = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attrs,
            &pb);
        if (r != kCVReturnSuccess || pb == NULL) return 0;

        CVPixelBufferLockBaseAddress(pb, 0);
        unsigned char *dst = (unsigned char *)
            CVPixelBufferGetBaseAddress(pb);
        size_t dstStride = CVPixelBufferGetBytesPerRow(pb);

        // 2. RGBA -> BGRA swizzle.
        for (int y = 0; y < height; y++) {
            const unsigned char *srcRow = rgba + (size_t)y * width * 4;
            unsigned char *dstRow = dst + (size_t)y * dstStride;
            for (int x = 0; x < width; x++) {
                dstRow[x * 4 + 0] = srcRow[x * 4 + 2]; // B
                dstRow[x * 4 + 1] = srcRow[x * 4 + 1]; // G
                dstRow[x * 4 + 2] = srcRow[x * 4 + 0]; // R
                dstRow[x * 4 + 3] = srcRow[x * 4 + 3]; // A
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, 0);

        // 3. Encode. PTS in 60Hz timebase; CMTime denominator is
        //    arbitrary as long as the deltas are consistent.
        CMTime pts = CMTimeMake(enc->frameIndex, 60);
        CMTime dur = CMTimeMake(1, 60);
        VTEncodeInfoFlags infoFlags = 0;
        OSStatus s = VTCompressionSessionEncodeFrame(
            enc->session, pb, pts, dur,
            NULL, NULL, &infoFlags);
        CVPixelBufferRelease(pb);
        if (s != noErr) return 0;

        // 4. Flush. CompleteFrames blocks until the output callback
        //    has run for every queued frame up to ``invalidTime``;
        //    passing kCMTimeInvalid drains everything.
        s = VTCompressionSessionCompleteFrames(
            enc->session, kCMTimeInvalid);
        if (s != noErr) return 0;

        enc->frameIndex++;

        // 5. Copy out.
        if ((int)enc->collectLen > outCap) {
            *outLen = (int)enc->collectLen;
            return 0;
        }
        memcpy(out, enc->collect, enc->collectLen);
        *outLen = (int)enc->collectLen;
        if (outIsKeyframe != NULL) {
            *outIsKeyframe = enc->collectIsKeyframe;
        }
        if (enc->collectIncludedExtra) {
            enc->hasSentExtraData = 1;
        }
        return 1;
    }
}

// ---------------------------------------------------------------------------
// Introspection — SPS/PPS extra data.
// ---------------------------------------------------------------------------
//
// The browser's WebCodecs decoder needs SPS/PPS to configure itself.
// Because EPP-M5 ships GOP=1, every keyframe (i.e. every frame)
// already carries SPS/PPS inline; this helper exists so a future
// EPP-M6 milestone that wants to ship the parameter sets out-of-band
// (e.g. in the hello capability bag) can read them without consuming
// a full encode.

// EPP-M9: profile / level introspection. Returns the (profileIdc,
// levelIdc) pair the encoder was created with so the Nim wrapper can
// build the V-packet ``codec_id`` (avc1.<ProfileIdc><Constraints><Level>)
// the WebCodecs VideoDecoder consumes. The values are stable for the
// lifetime of the encoder handle — VTCompressionSession's
// dimension-bound contract means a resize tears down + rebuilds the
// session, at which point a fresh selector pass runs.
int vt_encoder_get_profile_level(void *handle,
                                  int *outProfileIdc,
                                  int *outLevelIdc) {
    if (handle == NULL || outProfileIdc == NULL || outLevelIdc == NULL) {
        return 0;
    }
    CtVTEncoder *enc = (CtVTEncoder *)handle;
    *outProfileIdc = enc->profileIdc;
    *outLevelIdc = enc->levelIdc;
    return 1;
}

int vt_encoder_get_extra_data(void *handle,
                                unsigned char *out, int outCap,
                                int *outLen) {
    if (handle == NULL || outLen == NULL) return 0;
    CtVTEncoder *enc = (CtVTEncoder *)handle;
    if (enc->extraDataLen == 0) {
        *outLen = 0;
        return 0;
    }
    if (out == NULL || outCap < enc->extraDataLen) {
        *outLen = enc->extraDataLen;
        return 0;
    }
    memcpy(out, enc->extraData, enc->extraDataLen);
    *outLen = enc->extraDataLen;
    return 1;
}

void vt_encoder_destroy(void *handle) {
    if (handle == NULL) return;
    CtVTEncoder *enc = (CtVTEncoder *)handle;
    if (enc->session != NULL) {
        VTCompressionSessionInvalidate(enc->session);
        CFRelease(enc->session);
        enc->session = NULL;
    }
    if (enc->collect != NULL) {
        free(enc->collect);
        enc->collect = NULL;
    }
    free(enc);
}
