// snapshot_helper.m — ObjC helper for rendering NSViews to PNG bitmaps.
// Compiled separately since AppKit headers require Objective-C mode.
//
// The capture is DETERMINISTIC by construction. Golden files are compared
// byte for byte, so every rendering parameter AppKit would otherwise take
// from the host or the logged-in user is fixed here:
//
//   * Font smoothing: off. Its default comes from the per-user
//     `AppleFontSmoothing` preference. Measured on macOS 26.5.1: running the
//     scenario snapshots with `AppleFontSmoothing` 0 instead of the default
//     changed all seven captures. With smoothing off in our own context the
//     captures are identical for 0, 1, 2 and 3 and with
//     `CGFontRenderingFontSmoothingDisabled`. Grey-scale antialiasing stays
//     on. See
//     https://developer.apple.com/documentation/coregraphics/cgcontext/setshouldsmoothfonts(_:)
//   * Appearance: light Aqua. A view inherits the user's appearance, and a
//     dark one changed all seven captures. It is pinned on the view and while
//     drawing (-[NSAppearance performAsCurrentDrawingAppearance:]).
//   * Pixel density: 2 pixels per point. AppKit's own caching bitmap
//     (-bitmapImageRepForCachingDisplayInRect:) takes the main screen's
//     backingScaleFactor, which depends on the display attached to the
//     session (a "Screen Sharing Virtual Display" at 2x on the host where the
//     goldens were made).
//   * Colour space: Generic RGB (NSCalibratedRGBColorSpace), not the
//     screen's profile.
//
// Drawing goes through -displayRectIgnoringOpacity:inContext: into a
// bitmap context we own, so the CGContext flags above govern all text
// drawing. (-[CALayer renderInContext:] was tried and produced blank images.)

#import <AppKit/AppKit.h>
#include <stdlib.h>

static const NSInteger kSnapshotPixelsPerPoint = 2;

// Capture `view` once as a PNG. On success returns its length and stores a
// malloc'ed copy in *out, which the caller frees with free(). On failure
// returns 0 and stores NULL.
long nim_capture_view_png(id view, int width, int height,
                          unsigned char **out) {
    if (out == NULL) return 0;
    *out = NULL;
    @autoreleasepool {
        NSView *v = (NSView *)view;
        NSAppearance *aqua = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [v setAppearance:aqua];
        [v setFrame:NSMakeRect(0, 0, width, height)];
        [v setWantsLayer:YES];
        [v layoutSubtreeIfNeeded];

        NSBitmapImageRep *bmp = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
            pixelsWide:width * kSnapshotPixelsPerPoint
            pixelsHigh:height * kSnapshotPixelsPerPoint
            bitsPerSample:8
            samplesPerPixel:4
            hasAlpha:YES
            isPlanar:NO
            colorSpaceName:NSCalibratedRGBColorSpace
            bytesPerRow:0
            bitsPerPixel:0];
        if (bmp == nil) return 0;
#if !__has_feature(objc_arc)
        // Nim compiles this file without ARC; hand the owned rep to the
        // enclosing pool so a capture does not leak it.
        [bmp autorelease];
#endif
        // Size in points: the rep maps width x height points onto
        // 2*width x 2*height pixels, whatever the screen's scale.
        [bmp setSize:NSMakeSize(width, height)];

        NSGraphicsContext *ctx =
            [NSGraphicsContext graphicsContextWithBitmapImageRep:bmp];
        if (ctx == nil) return 0;
        CGContextRef cg = [ctx CGContext];
        CGContextSetAllowsFontSmoothing(cg, false);
        CGContextSetShouldSmoothFonts(cg, false);
        CGContextSetAllowsAntialiasing(cg, true);
        CGContextSetShouldAntialias(cg, true);

        [aqua performAsCurrentDrawingAppearance:^{
            [v displayRectIgnoringOpacity:[v bounds] inContext:ctx];
        }];

        NSData *png = [bmp representationUsingType:NSBitmapImageFileTypePNG
                                        properties:@{}];
        long len = (long)[png length];
        if (png == nil || len <= 0) return 0;
        unsigned char *copy = malloc((size_t)len);
        if (copy == NULL) return 0;
        memcpy(copy, [png bytes], (size_t)len);
        *out = copy;
        return len;
    }
}
