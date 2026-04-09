## App entry point — called from Swift/ObjC thin shell.
## Drives the entire branded UI from Nim using UIKitRenderer + branded_ui + Yoga.
##
## Swift creates a UIWindow with a root UIView, then calls isonim_start()
## passing that root view. Nim takes over from there:
## 1. Sets up the branded theme
## 2. Creates TaskAppState
## 3. Renders the branded UI via UIKitRenderer
## 4. Computes Yoga layout
## 5. Applies computed frames to all UIViews
## 6. Adds the root element as a subview

import isonim_cocoa/objc_runtime
import isonim_cocoa/uikit_renderer
import isonim_cocoa/uikit/views
import isonim/theming/theme
import isonim/components/task_manager
import isonim/components/branded_ui
import isonim/layout/layout_engine

var appState: TaskAppState
var currentRootView: Id          # The Swift-provided root UIView
var currentRenderedRoot: Id      # The Nim-rendered root element
var screenWidth: float = 390.0
var screenHeight: float = 844.0

proc rebuildUI() =
  ## Tear down old UI and rebuild from current state.
  if not currentRenderedRoot.isNil:
    uiRemoveFromSuperview(currentRenderedRoot)

  resetUITree()

  let r = UIKitRenderer()
  let engine = newLayoutEngine()

  # Render branded UI
  let rendered = renderTaskApp[UIKitRenderer, UIKitElement](
    r, appState,
    onAdd = proc(text: string) =
      appState.addTask(text)
      rebuildUI(),
    onToggle = proc(id: int) =
      appState.toggleTask(id)
      rebuildUI(),
    onDelete = proc(id: int) =
      appState.deleteTask(id)
      rebuildUI(),
    onFilter = proc(f: FilterMode) =
      appState.filter = f
      rebuildUI(),
    onClear = proc() =
      appState.clearCompleted()
      rebuildUI(),
    engine = engine
  )
  currentRenderedRoot = rendered

  # Compute Yoga layout
  engine.calculateLayout(screenWidth, screenHeight)

  # Apply frames. UIKit uses top-left origin (Y=0 at top), same as Yoga.
  # No Y-axis flip needed (unlike AppKit).
  let setFrameSel = sel("setFrame:")
  for (handle, layout) in engine.allLayouts():
    if layout.width > 0 and layout.height > 0:
      let view = Id(cast[pointer](handle))
      let rect = CGRect(
        origin: CGPoint(x: CGFloat(layout.x), y: CGFloat(layout.y)),
        size: CGSize(width: CGFloat(layout.width), height: CGFloat(layout.height)))
      msgSendVoidCGRect(view, setFrameSel, rect)

  # Set the rendered root frame to fill the available area
  msgSendVoidCGRect(currentRenderedRoot, setFrameSel,
    CGRect(origin: CGPoint(x: 0, y: 0),
           size: CGSize(width: screenWidth, height: screenHeight)))

  # Add rendered root to the Swift root view
  uiAddSubview(currentRootView, currentRenderedRoot)

  engine.freeAll()

proc isonim_start(rootView: pointer; width, height: cdouble) {.exportc, cdecl.} =
  ## Called from Swift. rootView is the UIView to populate.
  currentRootView = Id(rootView)
  screenWidth = width
  screenHeight = height

  setTheme(isoTheme())
  appState = newTaskAppState()
  rebuildUI()
