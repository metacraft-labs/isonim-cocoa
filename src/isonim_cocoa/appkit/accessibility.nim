## NSAccessibility protocol wrappers for AppKit views.
##
## NSAccessibility methods are synchronous property getters/setters on NSView.
## They work headlessly without a window or screen.

import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views  # for msgSendVoidBool

{.passL: "-framework AppKit".}

# ---------------------------------------------------------------------------
# Accessibility role constants (NSAccessibilityRole = NSString)
# ---------------------------------------------------------------------------
# These are NSString constants defined in AppKit. We access them by their
# known AX string values rather than linking to the extern symbols, which
# avoids emit complexity and works identically.

proc accessibilityButtonRole*(): Id =
  ## NSAccessibilityButtonRole = "AXButton"
  toNSString("AXButton")

proc accessibilityTextFieldRole*(): Id =
  ## NSAccessibilityTextFieldRole = "AXTextField"
  toNSString("AXTextField")

proc accessibilityStaticTextRole*(): Id =
  ## NSAccessibilityStaticTextRole = "AXStaticText"
  toNSString("AXStaticText")

proc accessibilityGroupRole*(): Id =
  ## NSAccessibilityGroupRole = "AXGroup"
  toNSString("AXGroup")

proc accessibilityImageRole*(): Id =
  ## NSAccessibilityImageRole = "AXImage"
  toNSString("AXImage")

proc accessibilitySliderRole*(): Id =
  ## NSAccessibilitySliderRole = "AXSlider"
  toNSString("AXSlider")

proc accessibilityCheckBoxRole*(): Id =
  ## NSAccessibilityCheckBoxRole = "AXCheckBox"
  toNSString("AXCheckBox")

proc accessibilityListRole*(): Id =
  ## NSAccessibilityListRole = "AXList"
  toNSString("AXList")

proc accessibilityLinkRole*(): Id =
  ## NSAccessibilityLinkRole = "AXLink"
  toNSString("AXLink")

# ---------------------------------------------------------------------------
# Accessibility label
# ---------------------------------------------------------------------------

proc setAccessibilityLabel*(view: Id; label: string) =
  ## Set the accessibility label (VoiceOver description) on a view.
  let nsStr = toNSString(label)
  msgSendVoid(view, sel("setAccessibilityLabel:"), nsStr)
  release(nsStr)

proc accessibilityLabel*(view: Id): string =
  ## Get the accessibility label from a view.
  let nsStr = msgSend(view, sel("accessibilityLabel"))
  toNimString(nsStr)

# ---------------------------------------------------------------------------
# Accessibility role
# ---------------------------------------------------------------------------

proc setAccessibilityRole*(view: Id; role: Id) =
  ## Set the accessibility role on a view (pass an NSAccessibilityRole constant).
  msgSendVoid(view, sel("setAccessibilityRole:"), role)

proc accessibilityRole*(view: Id): string =
  ## Get the accessibility role string from a view.
  let nsStr = msgSend(view, sel("accessibilityRole"))
  toNimString(nsStr)

# ---------------------------------------------------------------------------
# Accessibility element
# ---------------------------------------------------------------------------

proc setAccessibilityElement*(view: Id; isElement: bool) =
  ## Set whether this view is an accessibility element.
  msgSendVoidBool(view, sel("setAccessibilityElement:"), isElement)

proc isAccessibilityElement*(view: Id): bool =
  ## Query whether this view is an accessibility element.
  msgSendBool(view, sel("isAccessibilityElement"))

# ---------------------------------------------------------------------------
# Accessibility value
# ---------------------------------------------------------------------------

proc setAccessibilityValue*(view: Id; value: string) =
  ## Set the accessibility value (e.g. current slider position).
  let nsStr = toNSString(value)
  msgSendVoid(view, sel("setAccessibilityValue:"), nsStr)
  release(nsStr)

proc accessibilityValue*(view: Id): string =
  ## Get the accessibility value from a view.
  let val = msgSend(view, sel("accessibilityValue"))
  if val.isNil:
    return ""
  # accessibilityValue returns id, which may be NSString or NSNumber.
  # Check if it responds to UTF8String (NSString).
  let isString = msgSendBool(val, sel("respondsToSelector:"),
                              sel("UTF8String"))
  if isString:
    toNimString(val)
  else:
    # Probably NSNumber -- get description
    toNimString(msgSend(val, sel("description")))

# ---------------------------------------------------------------------------
# Focus / key view
# ---------------------------------------------------------------------------

proc setCanBecomeKeyView*(view: Id; can: bool) =
  ## Mark a view as focusable via accessibility.
  ## canBecomeKeyView is read-only on NSView (requires subclassing),
  ## so we use setAccessibilityFocused: as the settable proxy.
  msgSendVoidBool(view, sel("setAccessibilityFocused:"), can)

proc canBecomeKeyView*(view: Id): bool =
  ## Check if a view can become the key view.
  msgSendBool(view, sel("canBecomeKeyView"))

proc isAccessibilityFocused*(view: Id): bool =
  ## Check if a view has accessibility focus.
  msgSendBool(view, sel("isAccessibilityFocused"))

proc setAccessibilityFocused*(view: Id; focused: bool) =
  ## Set accessibility focus on a view.
  msgSendVoidBool(view, sel("setAccessibilityFocused:"), focused)

proc nextValidKeyView*(view: Id): Id =
  ## Get the next valid key view in the focus chain.
  msgSend(view, sel("nextValidKeyView"))
