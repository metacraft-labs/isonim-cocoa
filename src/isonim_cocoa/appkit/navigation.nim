## Navigation & layout container wrappers — NSTabView, NSSplitView,
## NSToolbar (Nim-managed), Drawer (Nim state), NavStack (Nim state).

import std/tables
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

{.passL: "-framework AppKit".}

# CGGeometry is already included via objc_runtime (which emits #include <CoreGraphics/CGGeometry.h>)

# ===========================================================================
# Helper: set frame on a view (uses emit to avoid struct-passing issues)
# ===========================================================================

proc setViewFrame*(view: Id; x, y, w, h: cdouble) =
  ## Set the frame of an NSView to (x, y, w, h).
  {.emit: """
  ((void(*)(id, SEL, CGRect))objc_msgSend)((id)`view`, sel_registerName("setFrame:"),
    (CGRect){{`x`, `y`}, {`w`, `h`}});
  """.}

# ===========================================================================
# NSTabView
# ===========================================================================

proc newNSTabView*(): Id =
  ## Create a new NSTabView.
  result = allocInit("NSTabView")
  setWantsLayer(result)

proc tabViewAddTab*(tv: Id; label: string; contentView: Id) =
  ## Create an NSTabViewItem, set its label and view, add to tab view.
  let item = allocInit("NSTabViewItem")
  let nsLabel = toNSString(label)
  msgSendVoid(item, sel("setLabel:"), nsLabel)
  release(nsLabel)
  msgSendVoid(item, sel("setView:"), contentView)
  msgSendVoid(tv, sel("addTabViewItem:"), item)

proc tabViewTabCount*(tv: Id): int =
  ## Number of tabs.
  int(msgSendInt(tv, sel("numberOfTabViewItems")))

proc tabViewSelectedIndex*(tv: Id): int =
  ## Index of the selected tab. Returns -1 if none selected.
  # NSTabView doesn't have a direct selectedIndex method.
  # We get the selected item and find its index via indexOfTabViewItem:.
  let sel_item = msgSend(tv, sel("selectedTabViewItem"))
  if sel_item.isNil:
    return -1
  int(msgSendInt(tv, sel("indexOfTabViewItem:"), sel_item))

proc tabViewSelectIndex*(tv: Id; idx: int) =
  ## Select tab at index.
  msgSendVoid(tv, sel("selectTabViewItemAtIndex:"), clong(idx))

proc tabViewItemAt(tv: Id; idx: int): Id =
  ## Get the NSTabViewItem at the given index.
  msgSend(tv, sel("tabViewItemAtIndex:"), clong(idx))

proc tabViewItemLabel*(tv: Id; idx: int): string =
  ## Get the label of the tab at the given index.
  let item = tabViewItemAt(tv, idx)
  toNimString(msgSend(item, sel("label")))

proc tabViewItemView*(tv: Id; idx: int): Id =
  ## Get the content view of the tab at the given index.
  let item = tabViewItemAt(tv, idx)
  msgSend(item, sel("view"))

# ===========================================================================
# NSSplitView
# ===========================================================================

proc newNSSplitView*(vertical: bool = true): Id =
  ## Create a new NSSplitView. vertical=true means subviews are side-by-side.
  result = allocInit("NSSplitView")
  setWantsLayer(result)
  msgSendVoidBool(result, sel("setVertical:"), vertical)

proc splitViewAddSubview*(sv: Id; view: Id) =
  ## Add a subview to the split view.
  addSubview(sv, view)

proc splitViewSubviewCount*(sv: Id): int =
  ## Number of subviews in the split view.
  # NSSplitView uses regular subviews (not arrangedSubviews).
  subviewCount(sv)

proc splitViewIsVertical*(sv: Id): bool =
  ## Whether the split view is vertical (subviews side-by-side).
  msgSendBool(sv, sel("isVertical"))

proc splitViewSetPosition*(sv: Id; position: cdouble; dividerIndex: int) =
  ## Set the position of a divider.
  msgSendVoid(sv, sel("setPosition:ofDividerAtIndex:"), position, clong(dividerIndex))

proc splitViewSubviewFrame*(sv: Id; idx: int): CGRect =
  ## Get the frame of the subview at the given index.
  let sub = subviewAtIndex(sv, idx)
  msgSendCGRect(sub, sel("frame"))

# ===========================================================================
# NSToolbar (Nim-managed items with labels and callbacks)
# ===========================================================================

type
  ToolbarItem* = object
    label*: string
    action*: proc()

# Nim-side storage: toolbar pointer -> seq of items
var toolbarItems: Table[pointer, seq[ToolbarItem]]

proc newNSToolbar*(identifier: string): Id =
  ## Create a new NSToolbar. Items are tracked Nim-side.
  let nsId = toNSString(identifier)
  result = msgSend(alloc("NSToolbar"), sel("initWithIdentifier:"), nsId)
  release(nsId)
  toolbarItems[pointer(result)] = @[]

proc toolbarAddItem*(tb: Id; label: string; action: proc()) =
  ## Add a toolbar item (tracked Nim-side).
  let p = pointer(tb)
  if p notin toolbarItems:
    toolbarItems[p] = @[]
  toolbarItems[p].add(ToolbarItem(label: label, action: action))

proc toolbarItemCount*(tb: Id): int =
  ## Number of items tracked for this toolbar.
  let p = pointer(tb)
  if p in toolbarItems:
    toolbarItems[p].len
  else:
    0

proc toolbarItemLabel*(tb: Id; idx: int): string =
  ## Label of the item at the given index.
  let p = pointer(tb)
  if p in toolbarItems and idx >= 0 and idx < toolbarItems[p].len:
    toolbarItems[p][idx].label
  else:
    ""

proc toolbarSimulateClick*(tb: Id; idx: int) =
  ## Fire the callback of the item at the given index (for testing).
  let p = pointer(tb)
  if p in toolbarItems and idx >= 0 and idx < toolbarItems[p].len:
    let action = toolbarItems[p][idx].action
    if action != nil:
      action()

proc resetToolbarItems*() =
  ## Clear all toolbar item tracking (for test isolation).
  toolbarItems.clear()

# ===========================================================================
# Drawer (pure Nim state machine)
# ===========================================================================

type
  DrawerState* = enum
    dsClosed
    dsOpen

  DrawerEdge* = enum
    deLeft
    deRight

# ===========================================================================
# NavStack (pure Nim state — managed view switching)
# ===========================================================================
#
# NavStackState is stored externally (in the renderer's element info).
# Here we define the type and stack operations that the renderer delegates to.

type
  NavStackState* = object
    stack*: seq[pointer]  # CocoaElement is Id which is pointer-sized
    onPush*: proc()
    onPop*: proc()
