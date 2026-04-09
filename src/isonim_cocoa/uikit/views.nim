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
    ((void(*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setBorderWidth:"), 1.5);
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

# ---------------------------------------------------------------------------
# UITextField
# ---------------------------------------------------------------------------

proc uiTextFieldNew*(): Id =
  ## Create a UITextField.
  result = allocInit("UITextField")
  # Set border style to rounded rect
  uikitMsgSendVoidInt(result, sel("setBorderStyle:"), 3)  # UITextBorderStyleRoundedRect

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
