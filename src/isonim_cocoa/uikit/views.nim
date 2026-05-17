## UIKit view wrappers — UIView, UILabel, UITextField, UIButton.
##
## Mirrors the AppKit views module but targets iOS UIKit classes.
## All calls go through objc_msgSend via objc_runtime.nim.

import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation

{.passL: "-framework UIKit".}

# ---------------------------------------------------------------------------
# Bool-argument msgSend (shared with appkit/views.nim signature)
# ---------------------------------------------------------------------------

{.emit: """
#define nim_uikit_msg_void_1_bool  ((void(*)(id, SEL, _Bool))objc_msgSend)
#define nim_uikit_msg_void_1_int   ((void(*)(id, SEL, int))objc_msgSend)
""".}

proc uikitMsgSendVoidBool*(self: Id; op: Sel; a1: bool)
  {.importc: "nim_uikit_msg_void_1_bool", header: objcSendH.}

proc uikitMsgSendVoidInt*(self: Id; op: Sel; a1: cint)
  {.importc: "nim_uikit_msg_void_1_int", header: objcSendH.}

# ---------------------------------------------------------------------------
# UIView
# ---------------------------------------------------------------------------

proc uiViewNew*(): Id =
  ## Create a new UIView via [[UIView alloc] init].
  allocInit("UIView")

proc uiAddSubview*(parent, child: Id) =
  msgSendVoid(parent, sel("addSubview:"), child)

proc uiRemoveFromSuperview*(view: Id) =
  msgSendVoid(view, sel("removeFromSuperview"))

proc uiSetNeedsLayout*(view: Id) =
  ## Mark `view` as needing layout — UIKit will recompute frames on
  ## the next layout pass. Pair with `uiLayoutIfNeeded` to force an
  ## immediate synchronous layout, which is what the Nim composition
  ## roots want after they push frames via `setFrame:` so that the
  ## off-screen `drawHierarchy(in:)` capture in the Stream app sees
  ## fully-laid-out subviews on the very first tick.
  msgSendVoid(view, sel("setNeedsLayout"))

proc uiLayoutIfNeeded*(view: Id) =
  ## Force an immediate layout pass on `view` and its descendants.
  ## Equivalent to `[view layoutIfNeeded]` in Objective-C.
  msgSendVoid(view, sel("layoutIfNeeded"))

proc uiSetHidden*(view: Id; hidden: bool) =
  uikitMsgSendVoidBool(view, sel("setHidden:"), hidden)

proc uiSetClipsToBounds*(view: Id; clips: bool) =
  uikitMsgSendVoidBool(view, sel("setClipsToBounds:"), clips)

proc uiSetUserInteractionEnabled*(view: Id; enabled: bool) =
  uikitMsgSendVoidBool(view, sel("setUserInteractionEnabled:"), enabled)

proc uiSetBackgroundColor*(view: Id; r, g, b, a: cdouble) =
  ## Set UIView.backgroundColor via UIColor.
  # UIColor colorWithRed:green:blue:alpha: takes 4 doubles.
  # Use emit because Nim lacks a 4-double msgSend overload.
  {.emit: """
  id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
    (id)objc_getClass("UIColor"),
    sel_registerName("colorWithRed:green:blue:alpha:"),
    `r`, `g`, `b`, `a`);
  ((void(*)(id, SEL, id))objc_msgSend)(`view`, sel_registerName("setBackgroundColor:"), color);
  """.}

proc uiSetCornerRadius*(view: Id; radius: cdouble) =
  ## Set layer.cornerRadius on a UIView.
  {.emit: """
  id layer = ((id(*)(id, SEL))objc_msgSend)(`view`, sel_registerName("layer"));
  if (layer) {
    ((void(*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setCornerRadius:"), `radius`);
  }
  """.}

proc uiSetBorderColor*(view: Id; r, g, b, a: cdouble) =
  {.emit: """
  id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
    (id)objc_getClass("UIColor"),
    sel_registerName("colorWithRed:green:blue:alpha:"),
    `r`, `g`, `b`, `a`);
  id layer = ((id(*)(id, SEL))objc_msgSend)(`view`, sel_registerName("layer"));
  if (layer) {
    void* cgColor = ((void*(*)(id, SEL))objc_msgSend)(color, sel_registerName("CGColor"));
    ((void(*)(id, SEL, void*))objc_msgSend)(layer, sel_registerName("setBorderColor:"), cgColor);
    // Set default border width of 1 if none was explicitly set
    double existingWidth = ((double(*)(id, SEL))objc_msgSend)(layer, sel_registerName("borderWidth"));
    if (existingWidth == 0.0) {
      ((void(*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setBorderWidth:"), 1.0);
    }
  }
  """.}

proc uiSetBorderWidth*(view: Id; width: cdouble) =
  {.emit: """
  id layer = ((id(*)(id, SEL))objc_msgSend)(`view`, sel_registerName("layer"));
  if (layer) {
    ((void(*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setBorderWidth:"), `width`);
  }
  """.}

proc uiSetAlpha*(view: Id; alpha: cdouble) =
  {.emit: """
  ((void(*)(id, SEL, double))objc_msgSend)(`view`, sel_registerName("setAlpha:"), `alpha`);
  """.}

# ---------------------------------------------------------------------------
# UILabel
# ---------------------------------------------------------------------------

proc uiLabelNew*(text: string = ""): Id =
  ## Create a UILabel with optional initial text.
  result = allocInit("UILabel")
  # numberOfLines = 0 for multi-line
  uikitMsgSendVoidInt(result, sel("setNumberOfLines:"), 0)
  if text.len > 0:
    let nsStr = toNSString(text)
    msgSendVoid(result, sel("setText:"), nsStr)
    release(nsStr)

proc uiLabelGetText*(label: Id): string =
  toNimString(msgSend(label, sel("text")))

proc uiLabelSetText*(label: Id; text: string) =
  let nsStr = toNSString(text)
  msgSendVoid(label, sel("setText:"), nsStr)
  release(nsStr)

proc uiSetTextColor*(view: Id; r, g, b, a: cdouble) =
  {.emit: """
  id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
    (id)objc_getClass("UIColor"),
    sel_registerName("colorWithRed:green:blue:alpha:"),
    `r`, `g`, `b`, `a`);
  ((void(*)(id, SEL, id))objc_msgSend)(`view`, sel_registerName("setTextColor:"), color);
  """.}

proc uiSetFontSize*(view: Id; size: cdouble) =
  let font = msgSend(Id(cls("UIFont")), sel("systemFontOfSize:"), size)
  msgSendVoid(view, sel("setFont:"), font)

proc uiSetBoldFontSize*(view: Id; size: cdouble) =
  let font = msgSend(Id(cls("UIFont")), sel("boldSystemFontOfSize:"), size)
  msgSendVoid(view, sel("setFont:"), font)

proc uiSetTextAlignment*(view: Id; alignment: cint) =
  ## Set NSTextAlignment: 0=left, 1=center, 2=right, 3=justified, 4=natural
  uikitMsgSendVoidInt(view, sel("setTextAlignment:"), alignment)

proc uiLabelSizeThatFits*(label: Id; maxWidth, maxHeight: cdouble): CGSize =
  ## Ask a UILabel for the size it would prefer to occupy when given the
  ## supplied (width, height) constraint. Used by the renderer to push a
  ## text-intrinsic height into Yoga so labels actually take up space in
  ## the layout pass (UILabel has no implicit Yoga measure callback —
  ## without this, every label resolves to 0x0 and the iOS frame
  ## flushing pass skips it).
  ##
  ## Implemented as a `sizeToFit` + frame read-back rather than a direct
  ## `sizeThatFits:` msgSend: the latter returns a `CGSize` and the
  ## struct-return ABI on ARM64 routes through a different objc_msgSend
  ## variant depending on struct size, whereas `setFrame:` /
  ## `frame` are already known-working in this codebase
  ## (`msgSendCGRect` ships in `objc_runtime.nim`). We seed the label
  ## with a large bounding frame so `sizeToFit` clamps to the natural
  ## intrinsic content size rather than to a stale zero-sized frame.
  {.emit: """
  CGRect bigFrame = { {0.0, 0.0}, { (CGFloat)`maxWidth`, (CGFloat)`maxHeight` } };
  ((void(*)(id, SEL, CGRect))objc_msgSend)(
    (id)`label`, sel_registerName("setFrame:"), bigFrame);
  ((void(*)(id, SEL))objc_msgSend)(
    (id)`label`, sel_registerName("sizeToFit"));
  CGRect fitted = ((CGRect(*)(id, SEL))objc_msgSend)(
    (id)`label`, sel_registerName("frame"));
  `result` = fitted.size;
  """.}

# ---------------------------------------------------------------------------
# UITextField
# ---------------------------------------------------------------------------

proc uiTextFieldNew*(): Id =
  ## Create a UITextField with no default border (styled by renderer).
  result = allocInit("UITextField")
  # UITextBorderStyleNone — let branded_ui handle styling via setStyle
  uikitMsgSendVoidInt(result, sel("setBorderStyle:"), 0)
  # Add left padding (12pt inset view)
  {.emit: """
  id paddingView = ((id(*)(id, SEL))objc_msgSend)(
    (id)objc_getClass("UIView"), sel_registerName("alloc"));
  CGRect paddingRect = {{0, 0}, {12, 1}};
  paddingView = ((id(*)(id, SEL, CGRect))objc_msgSend)(paddingView,
    sel_registerName("initWithFrame:"), paddingRect);
  ((void(*)(id, SEL, id))objc_msgSend)(`result`,
    sel_registerName("setLeftView:"), paddingView);
  ((void(*)(id, SEL, int))objc_msgSend)(`result`,
    sel_registerName("setLeftViewMode:"), 3); // UITextFieldViewModeAlways
  """.}

proc uiTextFieldGetText*(tf: Id): string =
  toNimString(msgSend(tf, sel("text")))

proc uiTextFieldSetText*(tf: Id; text: string) =
  let nsStr = toNSString(text)
  msgSendVoid(tf, sel("setText:"), nsStr)
  release(nsStr)

proc uiSetPlaceholder*(tf: Id; placeholder: string) =
  let nsStr = toNSString(placeholder)
  msgSendVoid(tf, sel("setPlaceholder:"), nsStr)
  release(nsStr)

# ---------------------------------------------------------------------------
# UITapGestureRecognizer
# ---------------------------------------------------------------------------

proc uiAddTapGesture*(view: Id; target: Id; action: Sel) =
  ## Add a UITapGestureRecognizer to a UIView.
  let recognizer = msgSend(Id(cls("UITapGestureRecognizer")), sel("alloc"))
  let initd = msgSend(recognizer, sel("initWithTarget:action:"), target, Id(action))
  msgSendVoid(view, sel("addGestureRecognizer:"), initd)
  uiSetUserInteractionEnabled(view, true)

# ---------------------------------------------------------------------------
# UIButton
# ---------------------------------------------------------------------------

proc uiButtonNew*(title: string = ""): Id =
  ## Create a UIButton (system type).
  {.emit: """
  `result` = ((id(*)(id, SEL, int))objc_msgSend)(
    (id)objc_getClass("UIButton"),
    sel_registerName("buttonWithType:"), 1); // UIButtonTypeSystem = 1
  """.}
  if title.len > 0:
    let nsStr = toNSString(title)
    msgSendVoid(result, sel("setTitle:forState:"), nsStr, Id(nil))
    release(nsStr)

proc uiButtonSetTitle*(btn: Id; title: string) =
  let nsStr = toNSString(title)
  {.emit: """
  ((void(*)(id, SEL, id, unsigned long))objc_msgSend)(
    `btn`, sel_registerName("setTitle:forState:"), `nsStr`, 0); // UIControlStateNormal
  """.}
  release(nsStr)

proc uiButtonGetTitle*(btn: Id): string =
  {.emit: """
  id titleLabel = ((id(*)(id, SEL))objc_msgSend)(`btn`, sel_registerName("titleLabel"));
  id nsText = ((id(*)(id, SEL))objc_msgSend)(titleLabel, sel_registerName("text"));
  """.}
  var nsText {.importc, nodecl.}: Id
  toNimString(nsText)

proc uiButtonAddTarget*(btn: Id; target: Id; action: Sel) =
  ## Add target-action for UIControlEventTouchUpInside (1 << 6 = 64).
  {.emit: """
  ((void(*)(id, SEL, id, SEL, unsigned long))objc_msgSend)(
    `btn`, sel_registerName("addTarget:action:forControlEvents:"),
    `target`, `action`, (1UL << 6));
  """.}

proc uiButtonSetEnabled*(btn: Id; enabled: bool) =
  uikitMsgSendVoidBool(btn, sel("setEnabled:"), enabled)

proc uiButtonSetFontSize*(btn: Id; size: cdouble) =
  ## Set the font size of a UIButton's titleLabel.
  {.emit: """
  id titleLabel = ((id(*)(id, SEL))objc_msgSend)(`btn`, sel_registerName("titleLabel"));
  if (titleLabel) {
    id font = ((id(*)(id, SEL, double))objc_msgSend)(
      (id)objc_getClass("UIFont"), sel_registerName("systemFontOfSize:"), `size`);
    ((void(*)(id, SEL, id))objc_msgSend)(titleLabel, sel_registerName("setFont:"), font);
  }
  """.}

proc uiButtonSizeThatFits*(btn: Id; maxWidth, maxHeight: cdouble): CGSize =
  ## Ask a UIButton for the size it would prefer when constrained to
  ## (maxWidth, maxHeight). Used by the renderer to compute an intrinsic
  ## height for buttons whose title fits naturally — matches the
  ## measure-into-Yoga pattern `uiLabelSizeThatFits` uses for UILabel.
  ##
  ## Same `sizeToFit` + `frame` read-back idiom as `uiLabelSizeThatFits`
  ## — see that proc for why we avoid the direct `sizeThatFits:`
  ## struct-return msgSend.
  {.emit: """
  CGRect bigFrame = { {0.0, 0.0}, { (CGFloat)`maxWidth`, (CGFloat)`maxHeight` } };
  ((void(*)(id, SEL, CGRect))objc_msgSend)(
    (id)`btn`, sel_registerName("setFrame:"), bigFrame);
  ((void(*)(id, SEL))objc_msgSend)(
    (id)`btn`, sel_registerName("sizeToFit"));
  CGRect fitted = ((CGRect(*)(id, SEL))objc_msgSend)(
    (id)`btn`, sel_registerName("frame"));
  `result` = fitted.size;
  """.}

proc uiButtonSetTitleColor*(btn: Id; r, g, b, a: cdouble) =
  ## Set the title color for UIControlStateNormal.
  {.emit: """
  id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
    (id)objc_getClass("UIColor"),
    sel_registerName("colorWithRed:green:blue:alpha:"),
    `r`, `g`, `b`, `a`);
  ((void(*)(id, SEL, id, unsigned long))objc_msgSend)(
    `btn`, sel_registerName("setTitleColor:forState:"), color, 0); // UIControlStateNormal
  """.}

proc uiButtonSetSFSymbol*(btn: Id; name: string;
                          r, g, b, a: cdouble;
                          pointSize: cdouble = 22.0) =
  ## Replace the button's title image with an SF Symbol named `name`
  ## (e.g. ``checkmark.circle.fill``), tinted with the given RGBA, and
  ## also clear the title text so only the glyph paints. Used by the
  ## task-app iOS leaves to swap the legacy Unicode ballot box / "x"
  ## glyphs for native iOS check / minus icons.
  let nsStr = toNSString(name)
  {.emit: """
  // Build a UIImage.SymbolConfiguration with the requested point size.
  id cfgClass = (id)objc_getClass("UIImageSymbolConfiguration");
  id cfg = ((id(*)(id, SEL, double))objc_msgSend)(
    cfgClass, sel_registerName("configurationWithPointSize:"), `pointSize`);

  // [UIImage systemImageNamed:`name` withConfiguration:cfg]
  id img = ((id(*)(id, SEL, id, id))objc_msgSend)(
    (id)objc_getClass("UIImage"),
    sel_registerName("systemImageNamed:withConfiguration:"),
    `nsStr`, cfg);

  // Apply tint via [img imageWithTintColor:UIColor.colorWithRed:...]
  // using the always-template rendering mode (2) so tintColor wins.
  id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
    (id)objc_getClass("UIColor"),
    sel_registerName("colorWithRed:green:blue:alpha:"),
    `r`, `g`, `b`, `a`);
  if (img) {
    id tinted = ((id(*)(id, SEL, id, long))objc_msgSend)(
      img, sel_registerName("imageWithTintColor:renderingMode:"), color, 2);
    if (tinted) img = tinted;
  }

  // [btn setImage:img forState:UIControlStateNormal]
  ((void(*)(id, SEL, id, unsigned long))objc_msgSend)(
    `btn`, sel_registerName("setImage:forState:"), img, 0);

  // Clear the title so only the symbol paints.
  id empty = ((id(*)(id, SEL, const char*))objc_msgSend)(
    (id)objc_getClass("NSString"),
    sel_registerName("stringWithUTF8String:"), "");
  ((void(*)(id, SEL, id, unsigned long))objc_msgSend)(
    `btn`, sel_registerName("setTitle:forState:"), empty, 0);

  // Also tint the button itself so template images respect the colour
  // even on iOS versions that ignore the per-image tint mode.
  ((void(*)(id, SEL, id))objc_msgSend)(
    `btn`, sel_registerName("setTintColor:"), color);
  """.}
  release(nsStr)

proc uiTextFieldSetPlaceholderColor*(tf: Id; r, g, b, a: cdouble) =
  ## Set the placeholder text color via an attributed placeholder
  ## string. Without this, UITextField paints the placeholder in the
  ## default ``placeholderText`` colour which on a dark ``surfaceCard``
  ## background reads as nearly invisible faint grey — the reviewer
  ## flagged this on the iOS task cell.
  ##
  ## ``NSForegroundColorAttributeName`` is exposed as a global NSString
  ## symbol by Foundation; we declare it ``extern`` inside the emit
  ## block and use it as the attribute key.
  {.emit: """
  extern id NSForegroundColorAttributeName;

  id placeholder = ((id(*)(id, SEL))objc_msgSend)(
    `tf`, sel_registerName("placeholder"));
  if (!placeholder) return;

  id color = ((id(*)(id, SEL, double, double, double, double))objc_msgSend)(
    (id)objc_getClass("UIColor"),
    sel_registerName("colorWithRed:green:blue:alpha:"),
    `r`, `g`, `b`, `a`);

  id dictClass = (id)objc_getClass("NSDictionary");
  id attrs = ((id(*)(id, SEL, id, id))objc_msgSend)(
    dictClass, sel_registerName("dictionaryWithObject:forKey:"),
    color, NSForegroundColorAttributeName);

  id astrClass = (id)objc_getClass("NSAttributedString");
  id astrAlloc = ((id(*)(id, SEL))objc_msgSend)(
    astrClass, sel_registerName("alloc"));
  id astr = ((id(*)(id, SEL, id, id))objc_msgSend)(
    astrAlloc, sel_registerName("initWithString:attributes:"),
    placeholder, attrs);

  ((void(*)(id, SEL, id))objc_msgSend)(
    `tf`, sel_registerName("setAttributedPlaceholder:"), astr);
  """.}

# ---------------------------------------------------------------------------
# UISwitch
# ---------------------------------------------------------------------------

proc uiSwitchNew*(): Id =
  ## Create a UISwitch via [[UISwitch alloc] init].
  allocInit("UISwitch")

proc uiSwitchSetOn*(sw: Id; on: bool) =
  uikitMsgSendVoidBool(sw, sel("setOn:"), on)

proc uiSwitchIsOn*(sw: Id): bool =
  {.emit: """
  `result` = ((_Bool(*)(id, SEL))objc_msgSend)(`sw`, sel_registerName("isOn"));
  """.}

proc uiSwitchAddTarget*(sw: Id; target: Id; action: Sel) =
  ## Add target-action for UIControlEventValueChanged (1 << 12 = 4096).
  {.emit: """
  ((void(*)(id, SEL, id, SEL, unsigned long))objc_msgSend)(
    `sw`, sel_registerName("addTarget:action:forControlEvents:"),
    `target`, `action`, (1UL << 12));
  """.}

# ---------------------------------------------------------------------------
# UISegmentedControl
# ---------------------------------------------------------------------------

proc uiSegmentedControlNew*(items: seq[string]): Id =
  ## Create a UISegmentedControl with the given segment titles.
  # Build NSArray of NSStrings
  var nsItems: seq[Id]
  for s in items:
    nsItems.add(toNSString(s))

  let nsArray = msgSend(Id(cls("NSMutableArray")), sel("alloc"))
  let nsArrayInit = msgSend(nsArray, sel("init"))

  for ns in nsItems:
    msgSendVoid(nsArrayInit, sel("addObject:"), ns)
    release(ns)

  result = msgSend(Id(cls("UISegmentedControl")), sel("alloc"))
  result = msgSend(result, sel("initWithItems:"), nsArrayInit)

proc uiSegmentedControlSetSegments*(sc: Id; items: seq[string]) =
  ## Remove all segments and add new ones.
  {.emit: """
  ((void(*)(id, SEL))objc_msgSend)(`sc`, sel_registerName("removeAllSegments"));
  """.}
  for i, s in items:
    let nsStr = toNSString(s)
    {.emit: """
    ((void(*)(id, SEL, id, unsigned long, _Bool))objc_msgSend)(
      `sc`, sel_registerName("insertSegmentWithTitle:atIndex:animated:"),
      `nsStr`, (unsigned long)`i`, 0);
    """.}
    release(nsStr)

proc uiSegmentedControlSetSelectedIndex*(sc: Id; index: cint) =
  {.emit: """
  ((void(*)(id, SEL, long))objc_msgSend)(
    `sc`, sel_registerName("setSelectedSegmentIndex:"), (long)`index`);
  """.}

proc uiSegmentedControlGetSelectedIndex*(sc: Id): cint =
  {.emit: """
  `result` = (int)((long(*)(id, SEL))objc_msgSend)(
    `sc`, sel_registerName("selectedSegmentIndex"));
  """.}

proc uiSegmentedControlAddTarget*(sc: Id; target: Id; action: Sel) =
  ## Add target-action for UIControlEventValueChanged.
  {.emit: """
  ((void(*)(id, SEL, id, SEL, unsigned long))objc_msgSend)(
    `sc`, sel_registerName("addTarget:action:forControlEvents:"),
    `target`, `action`, (1UL << 12));
  """.}
