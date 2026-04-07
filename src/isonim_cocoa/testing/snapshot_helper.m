// snapshot_helper.m — ObjC helper for rendering NSViews to PNG bitmaps.
// Compiled separately since AppKit headers require Objective-C mode.

#import <AppKit/AppKit.h>

// Capture an NSView to a PNG byte buffer.
// Returns the PNG data length; caller provides a buffer.
// Call with buf=NULL to get required length.
long nim_capture_view_png(id view, int width, int height,
                          unsigned char *buf, long bufLen) {
    @autoreleasepool {
        NSRect frame = NSMakeRect(0, 0, width, height);
        [view setFrame:frame];
        if ([view respondsToSelector:@selector(setWantsLayer:)]) {
            [view setWantsLayer:YES];
        }
        [view layoutSubtreeIfNeeded];

        NSBitmapImageRep *bmp = [view bitmapImageRepForCachingDisplayInRect:
                                 [view bounds]];
        if (bmp == nil) {
            // Fallback: create manually
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
        }

        [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bmp];

        NSData *png = [bmp representationUsingType:NSBitmapImageFileTypePNG
                                        properties:@{}];
        long len = (long)[png length];

        if (buf != NULL && bufLen >= len) {
            memcpy(buf, [png bytes], len);
        }

        return len;
    }
}
