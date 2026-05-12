// capture_rgba.m — ObjC helper for RS-M5: render an NSView headlessly to
// a canonical RGBA8888 row-major byte buffer.
//
// This is the bytes-only sibling of snapshot_helper.m's
// nim_capture_view_png. The bridge (isonim-render-serve) needs the raw
// pixel buffer in canonical RGBA8888 byte order so it can build an
// `F` packet directly without a PNG decode step on the wire.
//
// Recipe (mirrors the 6-step path documented in
// isonim-render-serve/src/isonim_render_serve/adapters/cocoa_adapter.nim
// module docstring):
//
//   1. Set the view's frame to (0, 0, width, height) so the capture
//      target matches the configured stream dimensions.
//   2. Lay the subtree out (`layoutSubtreeIfNeeded`) so any pending
//      AutoLayout passes commit before the bitmap is drawn.
//   3. Ask the view for an NSBitmapImageRep via
//      `bitmapImageRepForCachingDisplayInRect:`, falling back to a
//      manually-allocated rep if AppKit returns nil (matches the
//      snapshot_helper.m guard).
//   4. Drive the rep through `cacheDisplayInRect:toBitmapImageRep:` —
//      AppKit walks the view hierarchy and renders into the rep's
//      backing store.
//   5. Inspect the rep's pixelFormat / bytesPerRow / bitmapFormat /
//      samplesPerPixel / colorSpace properties. The rep allocated by
//      bitmapImageRepForCachingDisplayInRect: is *almost* canonical
//      RGBA8888 row-major, but:
//        * bytesPerRow may exceed pixelsWide * 4 for alignment.
//        * On retina hosts (or HiDPI bitmaps) pixelsWide / pixelsHigh
//          may exceed the requested width / height (in points).
//        * bitmapFormat may set NSBitmapFormatAlphaFirst (ARGB) or
//          NSBitmapFormatThirtyTwoBitLittleEndian (BGRA / ABGR
//          depending on the alpha bit).
//   6. Copy each row of the rep into the caller's RGBA8888 destination
//      buffer, swizzling per-pixel when bitmapFormat indicates a
//      non-canonical channel order. If the rep is wider/taller than
//      the requested capture size (retina scale), we *downscale*
//      with a simple nearest-neighbor stride so the wire payload
//      length stays `width * height * 4`.
//
// Returns 1 on success, 0 on failure. The caller pre-allocates `buf`
// of size `width * height * 4` bytes.

#import <AppKit/AppKit.h>
#include <string.h>

// NSBitmapImageRep bitmapFormat option bits we care about.
#ifndef NSBitmapFormatAlphaFirst
#define NSBitmapFormatAlphaFirst 1
#endif
#ifndef NSBitmapFormatAlphaNonpremultiplied
#define NSBitmapFormatAlphaNonpremultiplied 2
#endif
#ifndef NSBitmapFormatThirtyTwoBitLittleEndian
#define NSBitmapFormatThirtyTwoBitLittleEndian (1 << 10)
#endif
#ifndef NSBitmapFormatThirtyTwoBitBigEndian
#define NSBitmapFormatThirtyTwoBitBigEndian (1 << 11)
#endif

int nim_capture_view_rgba(id view, int width, int height,
                          unsigned char *buf) {
    if (view == nil || buf == NULL || width <= 0 || height <= 0) {
        return 0;
    }

    @autoreleasepool {
        // Step 1+2: set the frame & flush layout.
        NSView *nsView = (NSView *)view;
        NSRect frame = NSMakeRect(0, 0, width, height);
        [nsView setFrame:frame];
        if ([nsView respondsToSelector:@selector(setWantsLayer:)]) {
            [nsView setWantsLayer:YES];
        }
        if ([nsView respondsToSelector:@selector(layoutSubtreeIfNeeded)]) {
            [nsView layoutSubtreeIfNeeded];
        }

        NSRect bounds = [nsView bounds];

        // Step 3: try AppKit's bitmap-rep factory first.
        NSBitmapImageRep *bmp =
            [nsView bitmapImageRepForCachingDisplayInRect:bounds];
        if (bmp == nil) {
            // Manual fallback: matches snapshot_helper.m's allocation.
            bmp = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL
                pixelsWide:width
                pixelsHigh:height
                bitsPerSample:8
                samplesPerPixel:4
                hasAlpha:YES
                isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace
                bytesPerRow:0
                bitsPerPixel:0];
            if (bmp == nil) {
                return 0;
            }
        }

        // Step 4: render the view into the rep.
        [nsView cacheDisplayInRect:bounds toBitmapImageRep:bmp];

        // Step 5: inspect format.
        unsigned char *src = [bmp bitmapData];
        if (src == NULL) {
            return 0;
        }
        NSInteger srcW = [bmp pixelsWide];
        NSInteger srcH = [bmp pixelsHigh];
        NSInteger srcStride = [bmp bytesPerRow];
        NSInteger samples = [bmp samplesPerPixel];
        NSInteger bitsPerSample = [bmp bitsPerSample];
        NSBitmapFormat fmt = [bmp bitmapFormat];

        // We can only handle 8-bit-per-sample bitmaps cleanly. AppKit
        // produces 8-bit reps for the `forCachingDisplayInRect:`
        // factory on every macOS version we ship against; anything
        // else means the host configured a wide-gamut HDR pipeline
        // we don't support yet.
        if (bitsPerSample != 8 || samples < 3) {
            return 0;
        }

        BOOL alphaFirst = (fmt & NSBitmapFormatAlphaFirst) != 0;
        BOOL littleEndian =
            (fmt & NSBitmapFormatThirtyTwoBitLittleEndian) != 0;
        BOOL hasAlpha = (samples >= 4);

        // Step 6: row-by-row copy with optional swizzle and optional
        // nearest-neighbor downscale (when the rep is bigger than the
        // requested capture size — happens on retina hosts).
        for (int y = 0; y < height; y++) {
            // Nearest-neighbor row index in the source rep.
            NSInteger sy = (NSInteger)y * srcH / height;
            if (sy >= srcH) sy = srcH - 1;
            unsigned char *srcRow = src + sy * srcStride;
            unsigned char *dstRow = buf + (NSInteger)y * width * 4;
            for (int x = 0; x < width; x++) {
                NSInteger sx = (NSInteger)x * srcW / width;
                if (sx >= srcW) sx = srcW - 1;
                unsigned char *sp = srcRow + sx * samples;
                unsigned char r, g, b, a;
                if (alphaFirst) {
                    // ARGB or BGRA depending on endianness.
                    if (littleEndian) {
                        // little-endian + alphaFirst => BGRA in memory
                        b = sp[0]; g = sp[1]; r = sp[2];
                        a = hasAlpha ? sp[3] : 0xFF;
                    } else {
                        // big-endian + alphaFirst => ARGB in memory
                        a = hasAlpha ? sp[0] : 0xFF;
                        r = sp[1]; g = sp[2]; b = sp[3];
                    }
                } else {
                    if (littleEndian) {
                        // little-endian, alpha-last => ABGR in memory
                        a = hasAlpha ? sp[0] : 0xFF;
                        b = sp[1]; g = sp[2]; r = sp[3];
                    } else {
                        // canonical big-endian RGBA — the common case
                        // when bitmapImageRepForCachingDisplayInRect:
                        // allocates the rep for us.
                        r = sp[0]; g = sp[1]; b = sp[2];
                        a = hasAlpha ? sp[3] : 0xFF;
                    }
                }
                dstRow[x * 4 + 0] = r;
                dstRow[x * 4 + 1] = g;
                dstRow[x * 4 + 2] = b;
                dstRow[x * 4 + 3] = a;
            }
        }
        return 1;
    }
}
