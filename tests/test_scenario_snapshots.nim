## Scenario-driven snapshot tests for the branded task manager UI.
##
## Renders each predefined scenario from isonim/components/scenarios.nim
## using CocoaRenderer + branded_ui.nim, then captures NSView -> PNG
## and compares against golden files.
##
## A Yoga LayoutEngine runs in parallel to compute flexbox layout.
## After rendering, computed frames are applied to every NSView so that
## snapshot captures produce real pixels instead of blank images.
##
## First run creates golden files in tests/golden/.
## Subsequent runs compare against them.
##
## Run with:
##   nim c -r --nimcache:nimcache/test_scenarios tests/test_scenario_snapshots.nim

import unittest
import isonim/components/task_manager
import isonim/components/scenarios
import isonim/components/branded_ui
import isonim/theming/theme
import isonim/layout/layout_engine
import isonim_cocoa/renderer
import isonim_cocoa/objc_runtime
import isonim_cocoa/testing/snapshots

# Branded theme is set inside renderTaskApp, but set it here too for clarity.
setTheme(isoTheme())

# No-op callbacks for rendering (snapshot tests don't exercise interaction)
proc nopAdd(t: string) = discard
proc nopId(id: int) = discard
proc nopFilter(f: FilterMode) = discard
proc nopClear() = discard

# ---------------------------------------------------------------------------
# Apply Yoga layout results to NSViews
# ---------------------------------------------------------------------------

proc applyLayout(engine: LayoutEngine; rootHeight: float) =
  ## Walk all layout nodes and set NSView frames from Yoga-computed positions.
  ## Y coordinates are flipped to match AppKit's bottom-left origin.
  let setFrameSel = sel("setFrame:")
  for (handle, layout) in engine.allLayoutsFlipped(rootHeight):
    if layout.width > 0 and layout.height > 0:
      let view = Id(cast[pointer](handle))
      let rect = CGRect(
        origin: CGPoint(x: CGFloat(layout.x), y: CGFloat(layout.y)),
        size: CGSize(width: CGFloat(layout.width), height: CGFloat(layout.height)))
      msgSendVoidCGRect(view, setFrameSel, rect)

# ---------------------------------------------------------------------------
# Test helper
# ---------------------------------------------------------------------------

const ScreenW = 390
const ScreenH = 844

proc renderAndSnapshot(state: TaskAppState; name: string): SnapshotResult =
  let r = CocoaRenderer()
  let engine = newLayoutEngine()
  let root = renderTaskApp[CocoaRenderer, CocoaElement](
    r, state, nopAdd, nopId, nopId, nopFilter, nopClear, engine)
  engine.calculateLayout(ScreenW.float, ScreenH.float)
  applyLayout(engine, ScreenH.float)
  let res = compareSnapshot(root, name, ScreenW, ScreenH)
  engine.freeAll()
  res

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "Scenario Snapshots - Cocoa Branded":
  setup:
    resetTree()

  test "empty state":
    let result = renderAndSnapshot(emptyScenario(), "scenario_empty")
    check result.matched

  test "three tasks":
    let result = renderAndSnapshot(threeTasksScenario(), "scenario_three_tasks")
    check result.matched

  test "one completed":
    let result = renderAndSnapshot(oneCompletedScenario(), "scenario_one_completed")
    check result.matched

  test "filtered active":
    let result = renderAndSnapshot(filteredActiveScenario(), "scenario_filtered_active")
    check result.matched

  test "filtered completed":
    let result = renderAndSnapshot(filteredCompletedScenario(), "scenario_filtered_completed")
    check result.matched

  test "all completed":
    let result = renderAndSnapshot(allCompletedScenario(), "scenario_all_completed")
    check result.matched

  test "many tasks":
    let result = renderAndSnapshot(manyTasksScenario(), "scenario_many_tasks")
    check result.matched
