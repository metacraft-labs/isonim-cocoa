## App entry point for native controls variant — called from Swift/ObjC thin shell.
## Same architecture as app_entry.nim but compiled with -d:nativeControls
## which routes through native_ios_controls instead of branded_controls.

import isonim_cocoa/objc_runtime
import isonim_cocoa/uikit_renderer
import isonim_cocoa/uikit/views
import isonim/components/task_app
import isonim/layout/layout_engine
import isonim/core/[owner, signals, computation]

var currentRootView: Id
var currentRenderedRoot: Id
var screenWidth: float = 390.0
var screenHeight: float = 844.0
var safeAreaTop: float = 59.0
var safeAreaBottom: float = 34.0

proc isonim_native_start(rootView: pointer; width, height, saTop, saBottom: cdouble) {.exportc, cdecl.} =
  currentRootView = Id(rootView)
  screenWidth = width
  screenHeight = height
  safeAreaTop = saTop
  safeAreaBottom = saBottom

  createRoot proc(dispose: proc()) =
    let engine = newLayoutEngine()
    let r = UIKitRenderer(engine: engine)
    let store = createTaskStore()

    let rendered = renderApp[UIKitRenderer, UIKitElement](r, store)
    currentRenderedRoot = rendered

    let safeWidth = screenWidth
    let safeHeight = screenHeight - safeAreaTop - safeAreaBottom
    let setFrameSel = sel("setFrame:")

    let rootHandle = cast[int64](cast[pointer](rendered))

    proc applyLayout() =
      engine.calculateLayout(safeWidth, safeHeight)
      for (handle, layout) in engine.allLayouts():
        if layout.width > 0 and layout.height > 0 and handle != rootHandle:
          let view = Id(cast[pointer](handle))
          let rect = CGRect(
            origin: CGPoint(x: CGFloat(layout.x), y: CGFloat(layout.y)),
            size: CGSize(width: CGFloat(layout.width), height: CGFloat(layout.height)))
          msgSendVoidCGRect(view, setFrameSel, rect)

    applyLayout()

    createRenderEffect proc() =
      discard store.tasks.val
      discard store.filter.val
      applyLayout()

    msgSendVoidCGRect(currentRenderedRoot, setFrameSel,
      CGRect(origin: CGPoint(x: 0, y: safeAreaTop),
             size: CGSize(width: screenWidth,
                          height: safeHeight)))

    uiAddSubview(currentRootView, currentRenderedRoot)
