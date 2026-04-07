## NSScrollView wrapper — scrollable container with document view.

import isonim_cocoa/objc_runtime
import isonim_cocoa/appkit/views

{.passL: "-framework AppKit".}

# ---------------------------------------------------------------------------
# NSScrollView creation
# ---------------------------------------------------------------------------

proc newNSScrollView*(): Id =
  ## Create an NSScrollView with a default document view.
  result = allocInit("NSScrollView")
  setWantsLayer(result)
  # Create a default document view (flipped NSView for top-left origin)
  let docView = allocInit("NSView")
  setWantsLayer(docView)
  msgSendVoid(result, sel("setDocumentView:"), docView)

# ---------------------------------------------------------------------------
# Document view
# ---------------------------------------------------------------------------

proc setDocumentView*(scroll, view: Id) =
  ## Set the content view displayed inside the scroll view.
  msgSendVoid(scroll, sel("setDocumentView:"), view)

proc documentView*(scroll: Id): Id =
  ## Get the current document view.
  msgSend(scroll, sel("documentView"))

# ---------------------------------------------------------------------------
# Content size
# ---------------------------------------------------------------------------

proc contentSize*(scroll: Id): (CGFloat, CGFloat) =
  ## Return the content size (width, height) of the scroll view's clip view.
  var w, h: CGFloat
  {.emit: """
  CGSize sz = ((CGSize(*)(id, SEL))objc_msgSend)(
    (id)`scroll`, sel_registerName("contentSize"));
  `w` = sz.width;
  `h` = sz.height;
  """.}
  result = (w, h)

# ---------------------------------------------------------------------------
# Scroll position
# ---------------------------------------------------------------------------

proc scrollToPoint*(scroll: Id; x, y: CGFloat) =
  ## Programmatically scroll by setting the content view's bounds origin.
  let contentView = msgSend(scroll, sel("contentView"))
  {.emit: """
  CGPoint pt = { `x`, `y` };
  ((void(*)(id, SEL, CGPoint))objc_msgSend)(
    (id)`contentView`, sel_registerName("setBoundsOrigin:"), pt);
  """.}
  msgSendVoid(scroll, sel("reflectScrolledClipView:"), contentView)

# ---------------------------------------------------------------------------
# Scroller visibility
# ---------------------------------------------------------------------------

proc setHasVerticalScroller*(scroll: Id; v: bool) =
  msgSendVoidBool(scroll, sel("setHasVerticalScroller:"), v)

proc hasVerticalScroller*(scroll: Id): bool =
  msgSendBool(scroll, sel("hasVerticalScroller"))

proc setHasHorizontalScroller*(scroll: Id; v: bool) =
  msgSendVoidBool(scroll, sel("setHasHorizontalScroller:"), v)

proc hasHorizontalScroller*(scroll: Id): bool =
  msgSendBool(scroll, sel("hasHorizontalScroller"))

# ---------------------------------------------------------------------------
# Visible rect
# ---------------------------------------------------------------------------

proc documentVisibleRect*(scroll: Id): CGRect =
  ## Return the visible portion of the document view.
  {.emit: """
  `result` = ((CGRect(*)(id, SEL))objc_msgSend)(
    (id)`scroll`, sel_registerName("documentVisibleRect"));
  """.}

# ---------------------------------------------------------------------------
# Bounds origin reading (for verifying scroll position)
# ---------------------------------------------------------------------------

proc boundsOrigin*(scroll: Id): (CGFloat, CGFloat) =
  ## Return the bounds origin of the scroll view's content (clip) view.
  let contentView = msgSend(scroll, sel("contentView"))
  var x, y: CGFloat
  {.emit: """
  CGRect bounds = ((CGRect(*)(id, SEL))objc_msgSend)(
    (id)`contentView`, sel_registerName("bounds"));
  `x` = bounds.origin.x;
  `y` = bounds.origin.y;
  """.}
  result = (x, y)
