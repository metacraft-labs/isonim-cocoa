## Scenario-driven snapshot tests for the branded task manager UI.
##
## Renders each predefined scenario from isonim/components/scenarios.nim
## using CocoaRenderer + branded_ui.nim, then captures NSView → PNG
## and compares against golden files.
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
import isonim_cocoa/renderer
import isonim_cocoa/testing/snapshots

# Branded theme is set inside renderTaskApp, but set it here too for clarity.
setTheme(isoTheme())

# No-op callbacks for rendering (snapshot tests don't exercise interaction)
proc nopAdd(t: string) = discard
proc nopId(id: int) = discard
proc nopFilter(f: FilterMode) = discard
proc nopClear() = discard

suite "Scenario Snapshots - Cocoa Branded":
  setup:
    resetTree()

  test "empty state":
    let r = CocoaRenderer()
    let root = renderTaskApp[CocoaRenderer, CocoaElement](
      r, emptyScenario(), nopAdd, nopId, nopId, nopFilter, nopClear)
    let result = compareSnapshot(root, "scenario_empty", 390, 844)
    check result.matched

  test "three tasks":
    let r = CocoaRenderer()
    let root = renderTaskApp[CocoaRenderer, CocoaElement](
      r, threeTasksScenario(), nopAdd, nopId, nopId, nopFilter, nopClear)
    let result = compareSnapshot(root, "scenario_three_tasks", 390, 844)
    check result.matched

  test "one completed":
    let r = CocoaRenderer()
    let root = renderTaskApp[CocoaRenderer, CocoaElement](
      r, oneCompletedScenario(), nopAdd, nopId, nopId, nopFilter, nopClear)
    let result = compareSnapshot(root, "scenario_one_completed", 390, 844)
    check result.matched

  test "filtered active":
    let r = CocoaRenderer()
    let root = renderTaskApp[CocoaRenderer, CocoaElement](
      r, filteredActiveScenario(), nopAdd, nopId, nopId, nopFilter, nopClear)
    let result = compareSnapshot(root, "scenario_filtered_active", 390, 844)
    check result.matched

  test "filtered completed":
    let r = CocoaRenderer()
    let root = renderTaskApp[CocoaRenderer, CocoaElement](
      r, filteredCompletedScenario(), nopAdd, nopId, nopId, nopFilter, nopClear)
    let result = compareSnapshot(root, "scenario_filtered_completed", 390, 844)
    check result.matched

  test "all completed":
    let r = CocoaRenderer()
    let root = renderTaskApp[CocoaRenderer, CocoaElement](
      r, allCompletedScenario(), nopAdd, nopId, nopId, nopFilter, nopClear)
    let result = compareSnapshot(root, "scenario_all_completed", 390, 844)
    check result.matched

  test "many tasks":
    let r = CocoaRenderer()
    let root = renderTaskApp[CocoaRenderer, CocoaElement](
      r, manyTasksScenario(), nopAdd, nopId, nopId, nopFilter, nopClear)
    let result = compareSnapshot(root, "scenario_many_tasks", 390, 844)
    check result.matched
