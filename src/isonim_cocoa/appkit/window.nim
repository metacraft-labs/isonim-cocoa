## AppKit window management — NSApplication, NSWindow lifecycle.

import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

{.passL: "-framework AppKit".}

proc cgRect*(x, y, w, h: CGFloat): CGRect =
  result.origin.x = x
  result.origin.y = y
  result.size.width = w
  result.size.height = h

# ---------------------------------------------------------------------------
# NSApplication
# ---------------------------------------------------------------------------

proc sharedApplication*(): Id =
  ## Get or create the shared NSApplication instance.
  msgSend(Id(cls("NSApplication")), sel("sharedApplication"))

proc nsAppRun*() =
  ## Start the NSApplication event loop (blocks until terminated).
  let app = sharedApplication()
  msgSendVoid(app, sel("run"))

proc nsAppTerminate*() =
  ## Terminate the NSApplication.
  let app = sharedApplication()
  msgSendVoid(app, sel("terminate:"), Id(nil))

# ---------------------------------------------------------------------------
# NSWindow
# ---------------------------------------------------------------------------

const
  # NSWindow style masks
  NSWindowStyleMaskTitled*         = 1 shl 0
  NSWindowStyleMaskClosable*       = 1 shl 1
  NSWindowStyleMaskMiniaturizable* = 1 shl 2
  NSWindowStyleMaskResizable*      = 1 shl 3

  NSWindowStyleMaskDefault* =
    NSWindowStyleMaskTitled or NSWindowStyleMaskClosable or
    NSWindowStyleMaskMiniaturizable or NSWindowStyleMaskResizable

  # NSBackingStoreType
  NSBackingStoreBuffered* = 2

proc newNSWindow*(x, y, w, h: CGFloat;
                  styleMask: int = NSWindowStyleMaskDefault): Id =
  ## Create a new window with the given frame and style.
  let win = msgSend(Id(cls("NSWindow")), sel("alloc"))
  var frame = cgRect(x, y, w, h)
  # NSWindow initWithContentRect:styleMask:backing:defer:
  # This needs a special emit since it has 4 args of mixed types
  {.emit: [
    result, " = ((id(*)(id, SEL, CGRect, unsigned long, unsigned long, _Bool))objc_msgSend)(",
    win, ", ", sel("initWithContentRect:styleMask:backing:defer:"), ", ",
    frame, ", (unsigned long)", styleMask, ", (unsigned long)", NSBackingStoreBuffered, ", (_Bool)0);"
  ].}

proc contentView*(window: Id): Id =
  ## Get the content view of a window.
  msgSend(window, sel("contentView"))

proc setContentView*(window: Id; view: Id) =
  ## Set the content view of a window.
  msgSendVoid(window, sel("setContentView:"), view)

proc windowTitle*(window: Id): string =
  ## Get the window title.
  toNimString(msgSend(window, sel("title")))

proc setWindowTitle*(window: Id; title: string) =
  ## Set the window title.
  let nsTitle = toNSString(title)
  msgSendVoid(window, sel("setTitle:"), nsTitle)
  release(nsTitle)

proc makeKeyAndOrderFront*(window: Id) =
  ## Show the window and make it key.
  msgSendVoid(window, sel("makeKeyAndOrderFront:"), Id(nil))

proc orderOut*(window: Id) =
  ## Hide the window.
  msgSendVoid(window, sel("orderOut:"), Id(nil))

proc close*(window: Id) =
  ## Close the window.
  msgSendVoid(window, sel("close"))
