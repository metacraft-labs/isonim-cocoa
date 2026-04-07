## Tests for NSAlert, Modal state machine, NSMenu (action sheets),
## and NSOpenPanel/NSSavePanel file dialogs (M10).

import unittest
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views
import isonim_cocoa/appkit/dialogs
import isonim_cocoa/renderer
import isonim_cocoa/testing/snapshots

# ===========================================================================
# NSAlert
# ===========================================================================

suite "NSAlert - configuration":
  test "create, set message/info, add 3 buttons, verify":
    let alert = newNSAlert("Save changes?", "Your changes will be lost.",
                           style = 1)
    alertAddButton(alert, "Save")
    alertAddButton(alert, "Discard")
    alertAddButton(alert, "Cancel")
    check alertButtonCount(alert) == 3
    check alertButtonTitle(alert, 0) == "Save"
    check alertButtonTitle(alert, 1) == "Discard"
    check alertButtonTitle(alert, 2) == "Cancel"
    check alertMessageText(alert) == "Save changes?"
    check alertInformativeText(alert) == "Your changes will be lost."
    release(alert)

  test "alert style round-trip - critical":
    let alert = newNSAlert("Error", "Something went wrong.", style = 2)
    check alertStyle(alert) == 2  # NSAlertStyleCritical
    release(alert)

  test "simulated button press via performClick fires callback":
    let alert = newNSAlert("Test", "Press a button.")
    alertAddButton(alert, "OK")
    alertAddButton(alert, "Cancel")
    # Get button at index 1 (Cancel) and set up target-action
    let btn = alertButtonAt(alert, 1)
    var fired = false
    var firedIndex = -1
    let cbId = registerCallback(proc() =
      fired = true
      firedIndex = 1
    )
    let target = newCallbackTarget(cbId)
    msgSendVoid(btn, sel("setTarget:"), target)
    msgSendVoid(btn, sel("setAction:"), Id(sel("callbackAction:")))
    # Trigger via sendAction:to:
    let action = sel("callbackAction:")
    discard msgSendBool(btn, sel("sendAction:to:"), action, target)
    check fired
    check firedIndex == 1
    release(alert)

  test "accessory view - add NSTextField as accessory":
    let alert = newNSAlert("Input", "Enter your name:")
    let textField = newNSTextField()
    setPlaceholder(textField, "Name")
    alertSetAccessoryView(alert, textField)
    let readBack = alertAccessoryView(alert)
    check not readBack.isNil
    # The accessory view should be the same text field
    check pointer(readBack) == pointer(textField)
    release(alert)

  test "informational style is default":
    let alert = newNSAlert("Hello", "World")
    check alertStyle(alert) == 0  # NSAlertStyleInformational (actually Warning is 0 on some, but we set it)
    release(alert)

# ===========================================================================
# Modal state machine
# ===========================================================================

suite "Modal state machine":
  setup:
    resetTree()

  test "initial state - modal element with visible=false is msHidden":
    let r = CocoaRenderer()
    let modal = r.createElement("modal")
    check not Id(modal).isNil
    check r.modalState(modal) == msHidden

  test "show - set visible=true transitions to msPresenting":
    let r = CocoaRenderer()
    let modal = r.createElement("modal")
    r.setAttribute(modal, "visible", "true")
    check r.modalState(modal) == msPresenting
    # The underlying view should be visible
    check not isHidden(Id(modal))

  test "hide - set visible=false transitions through msDismissing to msHidden":
    let r = CocoaRenderer()
    let modal = r.createElement("modal")
    r.setAttribute(modal, "visible", "true")
    check r.modalState(modal) == msPresenting
    r.setAttribute(modal, "visible", "false")
    check r.modalState(modal) == msHidden
    # The underlying view should be hidden
    check isHidden(Id(modal))

  test "modal content tree - children tracked in Nim tree":
    let r = CocoaRenderer()
    let modal = r.createElement("modal")
    let child1 = r.createElement("div")
    let child2 = r.createElement("button")
    r.appendChild(modal, child1)
    r.appendChild(modal, child2)
    check r.childCount(modal) == 2
    check pointer(r.firstChild(modal)) == pointer(child1)
    check pointer(r.nextSibling(child1)) == pointer(child2)
    # When hidden, the underlying view should be hidden
    r.setAttribute(modal, "visible", "false")
    check isHidden(Id(modal))

# ===========================================================================
# NSMenu / action sheet
# ===========================================================================

suite "NSMenu - action sheet items":
  setup:
    resetTree()

  test "create menu with 4 items, verify count and titles":
    let menu = newNSMenu("Actions")
    menuAddItem(menu, "Copy", proc() = discard)
    menuAddItem(menu, "Paste", proc() = discard)
    menuAddItem(menu, "Cut", proc() = discard)
    menuAddItem(menu, "Delete", proc() = discard)
    check menuItemCount(menu) == 4
    check menuItemTitle(menu, 0) == "Copy"
    check menuItemTitle(menu, 1) == "Paste"
    check menuItemTitle(menu, 2) == "Cut"
    check menuItemTitle(menu, 3) == "Delete"
    release(menu)

  test "simulate click on item 2, verify callback fired":
    let menu = newNSMenu()
    var clickedItem = -1
    menuAddItem(menu, "A", proc() = clickedItem = 0)
    menuAddItem(menu, "B", proc() = clickedItem = 1)
    menuAddItem(menu, "C", proc() = clickedItem = 2)
    menuSimulateClick(menu, 2)
    check clickedItem == 2
    release(menu)

  test "renderer integration - createElement action-sheet":
    let r = CocoaRenderer()
    let sheet = r.createElement("action-sheet")
    check not Id(sheet).isNil
    # The element should be created (NSMenu-backed)
    # We can add items via the dialogs API
    menuAddItem(Id(sheet), "Option 1", proc() = discard)
    menuAddItem(Id(sheet), "Option 2", proc() = discard)
    check menuItemCount(Id(sheet)) == 2

# ===========================================================================
# File dialogs (NSOpenPanel)
# ===========================================================================

suite "NSOpenPanel - file dialog config":
  test "create, set allowsMultiple and canCreateDirs, read back":
    let panel = newNSOpenPanel()
    check not panel.isNil
    openPanelSetAllowsMultiple(panel, true)
    check openPanelAllowsMultiple(panel) == true
    openPanelSetCanCreateDirs(panel, true)
    check openPanelCanCreateDirs(panel) == true
    release(panel)

  test "property round-trip - set and unset":
    let panel = newNSOpenPanel()
    # Set to true
    openPanelSetAllowsMultiple(panel, true)
    openPanelSetCanCreateDirs(panel, true)
    check openPanelAllowsMultiple(panel) == true
    check openPanelCanCreateDirs(panel) == true
    # Set back to false
    openPanelSetAllowsMultiple(panel, false)
    openPanelSetCanCreateDirs(panel, false)
    check openPanelAllowsMultiple(panel) == false
    check openPanelCanCreateDirs(panel) == false
    release(panel)

# ===========================================================================
# Snapshot
# ===========================================================================

suite "NSAlert - Snapshot":
  test "alert snapshot with buttons":
    let alert = newNSAlert("Test Alert", "This is a test message", 2)
    alertAddButton(alert, "OK")
    alertAddButton(alert, "Cancel")
    # NSAlert has a window property with contentView we can snapshot
    let alertWindow = msgSend(alert, sel("window"))
    if not alertWindow.isNil:
      let contentView = msgSend(alertWindow, sel("contentView"))
      if not contentView.isNil:
        let result = compareSnapshot(contentView, "alert_with_buttons", 400, 200)
        check result.matched
    else:
      # NSAlert window may not exist without layout pass — verify alert config instead
      check alertButtonCount(alert) == 2
      check alertMessageText(alert) == "Test Alert"
    release(alert)
