## Dialog wrappers — NSAlert, NSMenu (action sheets), NSOpenPanel (file dialogs).
##
## NSAlert — informational/warning/critical alerts with buttons.
## NSMenu — popup menus for action sheet semantics.
## NSOpenPanel — file open dialogs (config-only, no runModal).
##
## Modal state machine is Nim-side only — no ObjC presentation needed.

import std/tables
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

{.passL: "-framework AppKit".}

# ---------------------------------------------------------------------------
# Modal state machine (Nim-side)
# ---------------------------------------------------------------------------

type
  ModalState* = enum
    msHidden      ## Not visible
    msPresenting  ## Visible / presenting
    msDismissing  ## Transitioning to hidden

# ---------------------------------------------------------------------------
# NSAlert
# ---------------------------------------------------------------------------

proc newNSAlert*(message, info: string; style: int = 0): Id =
  ## Create an NSAlert. style: 0=informational, 1=warning, 2=critical.
  result = allocInit("NSAlert")
  let nsMsg = toNSString(message)
  msgSendVoid(result, sel("setMessageText:"), nsMsg)
  release(nsMsg)
  let nsInfo = toNSString(info)
  msgSendVoid(result, sel("setInformativeText:"), nsInfo)
  release(nsInfo)
  msgSendVoid(result, sel("setAlertStyle:"), clong(style))

proc alertAddButton*(alert: Id; title: string) =
  ## Add a button to the alert. Returns the button (discarded here).
  let nsTitle = toNSString(title)
  discard msgSend(alert, sel("addButtonWithTitle:"), nsTitle)
  release(nsTitle)

proc alertButtons(alert: Id): Id =
  ## Get the NSArray of buttons.
  msgSend(alert, sel("buttons"))

proc alertButtonCount*(alert: Id): int =
  ## Count buttons on the alert.
  nsArrayCount(alertButtons(alert))

proc alertButtonAt*(alert: Id; index: int): Id =
  ## Get button by index from the alert's buttons array.
  nsArrayObjectAtIndex(alertButtons(alert), index)

proc alertButtonTitle*(alert: Id; index: int): string =
  ## Get the title of the button at the given index.
  let btn = alertButtonAt(alert, index)
  toNimString(msgSend(btn, sel("title")))

proc alertMessageText*(alert: Id): string =
  ## Get the alert's message text.
  toNimString(msgSend(alert, sel("messageText")))

proc alertInformativeText*(alert: Id): string =
  ## Get the alert's informative text.
  toNimString(msgSend(alert, sel("informativeText")))

proc alertStyle*(alert: Id): int =
  ## Get the alert style (0=informational, 1=warning, 2=critical).
  int(msgSendInt(alert, sel("alertStyle")))

proc alertSetAccessoryView*(alert: Id; view: Id) =
  ## Set the accessory view (e.g. a text field for input prompts).
  msgSendVoid(alert, sel("setAccessoryView:"), view)

proc alertAccessoryView*(alert: Id): Id =
  ## Get the accessory view.
  msgSend(alert, sel("accessoryView"))

# ---------------------------------------------------------------------------
# NSMenu (for action sheets)
# ---------------------------------------------------------------------------

# We store menu item callbacks in a Nim-side table keyed by (menu pointer, index).
var menuCallbacks: Table[pointer, seq[proc()]]

proc newNSMenu*(title: string = ""): Id =
  ## Create a new NSMenu.
  result = allocInit("NSMenu")
  if title.len > 0:
    let nsTitle = toNSString(title)
    msgSendVoid(result, sel("setTitle:"), nsTitle)
    release(nsTitle)
  menuCallbacks[pointer(result)] = @[]

proc menuAddItem*(menu: Id; title: string; action: proc()) =
  ## Add a clickable menu item with a callback.
  let nsTitle = toNSString(title)
  let emptyStr = toNSString("")
  # NSMenuItem initWithTitle:action:keyEquivalent:
  {.emit: """
  id itemCls = (id)objc_getClass("NSMenuItem");
  id alloc = ((id(*)(id, SEL))objc_msgSend)(itemCls, sel_registerName("alloc"));
  id item = ((id(*)(id, SEL, id, SEL, id))objc_msgSend)(
    alloc, sel_registerName("initWithTitle:action:keyEquivalent:"),
    `nsTitle`, (SEL)0, `emptyStr`);
  ((void(*)(id, SEL, id))objc_msgSend)(`menu`, sel_registerName("addItem:"), item);
  """.}
  release(nsTitle)
  release(emptyStr)
  # Store the callback
  let p = pointer(menu)
  if p notin menuCallbacks:
    menuCallbacks[p] = @[]
  menuCallbacks[p].add(action)

proc menuItemCount*(menu: Id): int =
  ## Get the number of items in the menu.
  int(msgSendInt(menu, sel("numberOfItems")))

proc menuItemAt(menu: Id; index: int): Id =
  ## Get the menu item at the given index.
  msgSend(menu, sel("itemAtIndex:"), clong(index))

proc menuItemTitle*(menu: Id; index: int): string =
  ## Get the title of the menu item at the given index.
  let item = menuItemAt(menu, index)
  toNimString(msgSend(item, sel("title")))

proc menuSimulateClick*(menu: Id; index: int) =
  ## Simulate clicking a menu item (for testing).
  ## Calls the Nim callback stored for this item.
  let p = pointer(menu)
  if p in menuCallbacks:
    let cbs = menuCallbacks[p]
    if index >= 0 and index < cbs.len:
      cbs[index]()

proc resetMenuCallbacks*() =
  ## Clear all menu callbacks (for test isolation).
  menuCallbacks.clear()

# ---------------------------------------------------------------------------
# NSOpenPanel (file dialogs, config-only)
# ---------------------------------------------------------------------------

proc newNSOpenPanel*(): Id =
  ## Create an NSOpenPanel.
  result = msgSend(Id(cls("NSOpenPanel")), sel("openPanel"))
  retain(result)

proc openPanelSetAllowsMultiple*(panel: Id; v: bool) =
  ## Set whether multiple file selection is allowed.
  msgSendVoidBool(panel, sel("setAllowsMultipleSelection:"), v)

proc openPanelAllowsMultiple*(panel: Id): bool =
  ## Get whether multiple file selection is allowed.
  msgSendBool(panel, sel("allowsMultipleSelection"))

proc openPanelSetCanCreateDirs*(panel: Id; v: bool) =
  ## Set whether the user can create directories.
  msgSendVoidBool(panel, sel("setCanCreateDirectories:"), v)

proc openPanelCanCreateDirs*(panel: Id): bool =
  ## Get whether the user can create directories.
  msgSendBool(panel, sel("canCreateDirectories"))
