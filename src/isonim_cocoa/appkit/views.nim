## AppKit view wrappers — NSView, NSTextField, NSButton, NSStackView, NSImageView.

import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation

{.passL: "-framework AppKit".}

# ---------------------------------------------------------------------------
# Bool-argument msgSend (needed for setHidden:, setEditable:, etc.)
# ---------------------------------------------------------------------------

{.emit: """
#define nim_msg_void_1_bool  ((void(*)(id, SEL, _Bool))objc_msgSend)
#define nim_msg_void_1_int   ((void(*)(id, SEL, int))objc_msgSend)
""".}

proc msgSendVoidBool*(self: Id; op: Sel; a1: bool)
  {.importc: "nim_msg_void_1_bool", header: objcSendH.}

proc msgSendVoidInt*(self: Id; op: Sel; a1: cint)
  {.importc: "nim_msg_void_1_int", header: objcSendH.}

# ---------------------------------------------------------------------------
# NSView
# ---------------------------------------------------------------------------

proc addSubview*(parent, child: Id) =
  msgSendVoid(parent, sel("addSubview:"), child)

proc removeFromSuperview*(view: Id) =
  msgSendVoid(view, sel("removeFromSuperview"))

proc superview*(view: Id): Id =
  msgSend(view, sel("superview"))

proc subviews*(view: Id): Id =
  msgSend(view, sel("subviews"))

proc subviewCount*(view: Id): int =
  let subs = subviews(view)
  if subs.isNil: 0
  else: nsArrayCount(subs)

proc subviewAtIndex*(view: Id; index: int): Id =
  nsArrayObjectAtIndex(subviews(view), index)

proc setHidden*(view: Id; hidden: bool) =
  msgSendVoidBool(view, sel("setHidden:"), hidden)

proc isHidden*(view: Id): bool =
  msgSendBool(view, sel("isHidden"))

proc setWantsLayer*(view: Id; wants: bool = true) =
  msgSendVoidBool(view, sel("setWantsLayer:"), wants)

proc layer*(view: Id): Id =
  msgSend(view, sel("layer"))

proc setNeedsDisplay*(view: Id) =
  msgSendVoidBool(view, sel("setNeedsDisplay:"), true)

# ---------------------------------------------------------------------------
# NSTextField (labels and text input)
# ---------------------------------------------------------------------------

proc newNSTextField*(): Id =
  allocInit("NSTextField")

proc newNSLabel*(text: string = ""): Id =
  result = allocInit("NSTextField")
  let nsText = toNSString(text)
  msgSendVoid(result, sel("setStringValue:"), nsText)
  msgSendVoidBool(result, sel("setEditable:"), false)
  msgSendVoidBool(result, sel("setBezeled:"), false)
  msgSendVoidBool(result, sel("setDrawsBackground:"), false)
  release(nsText)

proc stringValue*(textField: Id): string =
  toNimString(msgSend(textField, sel("stringValue")))

proc setStringValue*(textField: Id; value: string) =
  let nsStr = toNSString(value)
  msgSendVoid(textField, sel("setStringValue:"), nsStr)
  release(nsStr)

proc setEditable*(textField: Id; editable: bool) =
  msgSendVoidBool(textField, sel("setEditable:"), editable)

proc setPlaceholder*(textField: Id; placeholder: string) =
  let nsStr = toNSString(placeholder)
  msgSendVoid(textField, sel("setPlaceholderString:"), nsStr)
  release(nsStr)

proc setFontSize*(textField: Id; size: cdouble) =
  let font = msgSend(Id(cls("NSFont")), sel("systemFontOfSize:"), size)
  msgSendVoid(textField, sel("setFont:"), font)

# ---------------------------------------------------------------------------
# NSButton
# ---------------------------------------------------------------------------

proc newNSButton*(title: string = ""): Id =
  result = allocInit("NSButton")
  msgSendVoidInt(result, sel("setBezelStyle:"), 1)  # NSBezelStyleRounded
  if title.len > 0:
    let nsTitle = toNSString(title)
    msgSendVoid(result, sel("setTitle:"), nsTitle)
    release(nsTitle)

proc buttonTitle*(button: Id): string =
  toNimString(msgSend(button, sel("title")))

proc setButtonTitle*(button: Id; title: string) =
  let nsTitle = toNSString(title)
  msgSendVoid(button, sel("setTitle:"), nsTitle)
  release(nsTitle)

proc setEnabled*(control: Id; enabled: bool) =
  msgSendVoidBool(control, sel("setEnabled:"), enabled)

# ---------------------------------------------------------------------------
# NSStackView
# ---------------------------------------------------------------------------

proc newNSStackView*(orientation: int = 1): Id =
  ## orientation: 0 = horizontal, 1 = vertical
  result = allocInit("NSStackView")
  msgSendVoidInt(result, sel("setOrientation:"), cint(orientation))

proc addArrangedSubview*(stackView, view: Id) =
  msgSendVoid(stackView, sel("addArrangedSubview:"), view)

proc insertArrangedSubview*(stackView, view: Id; index: int) =
  msgSendVoid(stackView, sel("insertArrangedSubview:atIndex:"), view, clong(index))

proc removeArrangedSubview*(stackView, view: Id) =
  msgSendVoid(stackView, sel("removeArrangedSubview:"), view)

proc arrangedSubviews*(stackView: Id): Id =
  msgSend(stackView, sel("arrangedSubviews"))

proc arrangedSubviewCount*(stackView: Id): int =
  nsArrayCount(arrangedSubviews(stackView))

proc setSpacing*(stackView: Id; spacing: cdouble) =
  msgSendVoid(stackView, sel("setSpacing:"), spacing)

proc setStackOrientation*(stackView: Id; horizontal: bool) =
  msgSendVoidInt(stackView, sel("setOrientation:"), cint(if horizontal: 0 else: 1))

# ---------------------------------------------------------------------------
# NSImageView
# ---------------------------------------------------------------------------

proc newNSImageView*(): Id =
  allocInit("NSImageView")
