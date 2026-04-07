## NSTextView, NSSecureTextField, NSSearchField wrappers.
##
## NSTextView — multiline editable text (must live inside NSScrollView).
## NSSecureTextField — password input with hidden characters.
## NSSearchField — text field with cancel button and search UX.

import std/strutils
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/scrollview

{.passL: "-framework AppKit".}

# ObjC helper compiled separately (needs ObjC mode for AppKit types)
{.compile: currentSourcePath()[0..^(len("textcontrols.nim") + 1)] & "textcontrols_helper.m".}

# C-callable helpers from textcontrols_helper.m
proc nim_create_textview(width, height: cint): Id {.importc, cdecl.}
proc nim_textview_set_string(textView, nsString: Id) {.importc, cdecl.}
proc nim_textview_line_count(textView: Id): cint {.importc, cdecl.}
proc nim_view_set_frame*(view: Id; x, y, w, h: cdouble) {.importc, cdecl.}

# ---------------------------------------------------------------------------
# NSTextView (multiline rich text)
# ---------------------------------------------------------------------------

proc newNSTextView*(width, height: int): Id =
  ## Create an NSTextView embedded in an NSScrollView (required by AppKit).
  ## Returns the NSScrollView; use textViewFromScroll() to get the NSTextView.
  nim_create_textview(cint(width), cint(height))

proc textViewFromScroll*(scroll: Id): Id =
  ## Get the NSTextView from the enclosing NSScrollView.
  documentView(scroll)

proc textViewString*(tv: Id): string =
  ## Get the text content of an NSTextView.
  ## `tv` should be the NSTextView itself (not the scroll view).
  toNimString(msgSend(tv, sel("string")))

proc setTextViewString*(tv: Id; text: string) =
  ## Set text on an NSTextView via its textStorage.
  ## `tv` should be the NSTextView itself (not the scroll view).
  let nsStr = toNSString(text)
  nim_textview_set_string(tv, nsStr)
  release(nsStr)

proc textViewLineCount*(tv: Id): int =
  ## Count lines in an NSTextView via its layout manager.
  ## `tv` should be the NSTextView itself (not the scroll view).
  int(nim_textview_line_count(tv))

# ---------------------------------------------------------------------------
# NSSecureTextField (password input)
# ---------------------------------------------------------------------------

proc newNSSecureTextField*(): Id =
  ## Create a password input field.
  allocInit("NSSecureTextField")

proc isSecureTextField*(tf: Id): bool =
  ## Check if a text field is of the secure (password) type.
  let cls = object_getClass(tf)
  let name = $class_getName(cls)
  result = "Secure" in name

# ---------------------------------------------------------------------------
# NSSearchField (search with cancel button)
# ---------------------------------------------------------------------------

proc newNSSearchField*(placeholder: string = ""): Id =
  ## Create a search field with optional placeholder text.
  result = allocInit("NSSearchField")
  if placeholder.len > 0:
    setPlaceholder(result, placeholder)

proc searchString*(sf: Id): string =
  ## Get the current search text.
  stringValue(sf)

proc setSearchString*(sf: Id; text: string) =
  ## Set the search text.
  setStringValue(sf, text)

proc searchFieldPlaceholder*(sf: Id): string =
  ## Get the placeholder text of a search field.
  toNimString(msgSend(sf, sel("placeholderString")))

proc hasCancelButton*(sf: Id): bool =
  ## Check if the search field has a cancel button cell.
  ## NSSearchFieldCell (the cell of NSSearchField) has cancelButtonCell.
  let cell = msgSend(sf, sel("cell"))
  if cell.isNil:
    return false
  let cancelCell = msgSend(cell, sel("cancelButtonCell"))
  result = not cancelCell.isNil
