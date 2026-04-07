/* textcontrols_helper.m — ObjC helpers for NSTextView, NSSearchField operations.
 *
 * These functions require Objective-C compilation (not plain C) because
 * they use AppKit classes like NSTextView, NSScrollView, NSTextStorage.
 */

#import <AppKit/AppKit.h>

/* Create an NSTextView inside an NSScrollView. Returns the scroll view. */
id nim_create_textview(int width, int height) {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    [scrollView setWantsLayer:YES];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:NO];

    NSSize contentSize = [scrollView contentSize];
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];

    [textView setEditable:YES];
    [textView setRichText:NO];

    /* Make text view resize horizontally with the scroll view */
    [[textView textContainer] setContainerSize:NSMakeSize(contentSize.width, 1.0e7)];
    [[textView textContainer] setWidthTracksTextView:YES];
    [textView setMaxSize:NSMakeSize(1.0e7, 1.0e7)];
    [textView setVerticallyResizable:YES];
    [textView setHorizontallyResizable:NO];
    [textView setAutoresizingMask:NSViewWidthSizable];

    [scrollView setDocumentView:textView];
    return (id)scrollView;
}

/* Set text on an NSTextView via its textStorage. */
void nim_textview_set_string(id textView, id nsString) {
    NSTextView *tv = (NSTextView *)textView;
    NSTextStorage *ts = [tv textStorage];
    [ts replaceCharactersInRange:NSMakeRange(0, [ts length]) withString:(NSString *)nsString];
}

/* Count lines in an NSTextView via its layout manager. */
int nim_textview_line_count(id textView) {
    NSTextView *tv = (NSTextView *)textView;
    NSLayoutManager *lm = [tv layoutManager];
    NSTextStorage *ts = [tv textStorage];
    NSUInteger length = [ts length];

    if (length == 0) return 0;

    /* Force layout for the full range */
    [lm ensureLayoutForCharacterRange:NSMakeRange(0, length)];

    NSUInteger numberOfLines = 0;
    NSUInteger index = 0;
    while (index < length) {
        NSRange lineRange;
        (void)[lm lineFragmentRectForGlyphAtIndex:index effectiveRange:&lineRange];
        numberOfLines++;
        index = NSMaxRange(lineRange);
    }
    return (int)numberOfLines;
}

/* Set frame on any NSView using CGRect. */
void nim_view_set_frame(id view, double x, double y, double w, double h) {
    [(NSView *)view setFrame:NSMakeRect(x, y, w, h)];
}
