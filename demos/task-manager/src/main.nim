## Task Manager Demo — CocoaRenderer
##
## A complete task manager built with IsoNim's reactive core and CocoaRenderer.
## Features: add task, toggle completion, filter (all/active/completed),
## remove task, clear completed.
##
## Compile with:
##   nim c -r --path:../../../src --path:../../../../isonim/src demos/task-manager/src/main.nim

import std/[strutils, sequtils]
import isonim/core/[signals, computation, owner]
import isonim_cocoa/renderer
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

type
  Task = object
    name: string
    completed: bool

proc buildTaskManager(r: CocoaRenderer): tuple[root: CocoaElement, run: proc()] =
  ## Build the task manager UI. Returns the root element and a run proc
  ## that can be called to start the event loop (or used for testing).
  var tasks: seq[Task]
  var currentFilter = createSignal("all")
  var taskVersion = createSignal(0)  # bumped on any task mutation

  let app = r.createElement("div")
  r.setAttribute(app, "class", "task-manager")
  r.setStyle(app, "width", "400px")
  r.setStyle(app, "padding", "20")

  # ── Header ──
  let header = r.createElement("header")
  let title = r.createElement("h1")
  r.setTextContent(title, "Task Manager")
  r.setStyle(title, "font-size", "24px")
  r.appendChild(header, title)
  r.appendChild(app, header)

  # ── Input area ──
  let inputArea = r.createElement("div")
  r.setStyle(inputArea, "flex-direction", "row")
  r.setStyle(inputArea, "gap", "8")

  let inputField = r.createElement("input")
  r.setAttribute(inputField, "placeholder", "New task...")
  r.setStyle(inputField, "width", "250px")

  let addBtn = r.createElement("button")
  r.setTextContent(addBtn, "Add Task")

  r.appendChild(inputArea, inputField)
  r.appendChild(inputArea, addBtn)
  r.appendChild(app, inputArea)

  # ── Filter buttons ──
  let filterBar = r.createElement("div")
  r.setStyle(filterBar, "flex-direction", "row")
  r.setStyle(filterBar, "gap", "4")

  let allBtn = r.createElement("button")
  r.setTextContent(allBtn, "All")
  let activeBtn = r.createElement("button")
  r.setTextContent(activeBtn, "Active")
  let completedBtn = r.createElement("button")
  r.setTextContent(completedBtn, "Completed")
  let clearBtn = r.createElement("button")
  r.setTextContent(clearBtn, "Clear Done")

  r.appendChild(filterBar, allBtn)
  r.appendChild(filterBar, activeBtn)
  r.appendChild(filterBar, completedBtn)
  r.appendChild(filterBar, clearBtn)
  r.appendChild(app, filterBar)

  # ── Task list ──
  let taskList = r.createElement("ul")
  r.setAttribute(taskList, "class", "task-list")
  r.setStyle(taskList, "gap", "4")
  r.appendChild(app, taskList)

  # ── Footer ──
  let footer = r.createElement("footer")
  let countLabel = r.createElement("span")
  r.appendChild(footer, countLabel)
  r.appendChild(app, footer)

  # ── Reactive: update count label ──
  createRenderEffect proc() =
    let v = taskVersion.val  # subscribe to mutations
    let total = tasks.len
    let active = tasks.filterIt(not it.completed).len
    r.setTextContent(countLabel, $active & " of " & $total & " tasks remaining")

  # ── Reactive: rebuild visible task list ──
  createRenderEffect proc() =
    let f = currentFilter.val
    let v = taskVersion.val

    # Clear current list
    while r.childCount(taskList) > 0:
      let child = r.firstChild(taskList)
      r.removeChild(taskList, child)

    for i, task in tasks:
      let show = case f
        of "active": not task.completed
        of "completed": task.completed
        else: true
      if show:
        let li = r.createElement("li")
        r.setStyle(li, "flex-direction", "row")
        r.setStyle(li, "gap", "8")

        let toggleBtn = r.createElement("button")
        let marker = if task.completed: "[x]" else: "[ ]"
        r.setTextContent(toggleBtn, marker)

        let label = r.createElement("span")
        let displayText = if task.completed:
          task.name & " (done)"
        else:
          task.name
        r.setTextContent(label, displayText)

        let removeBtn = r.createElement("button")
        r.setTextContent(removeBtn, "x")

        # Capture index for closures
        let idx = i
        r.addEventListener(toggleBtn, "click", proc() =
          tasks[idx].completed = not tasks[idx].completed
          taskVersion.val = taskVersion.val + 1
        )
        r.addEventListener(removeBtn, "click", proc() =
          tasks.delete(idx)
          taskVersion.val = taskVersion.val + 1
        )

        r.appendChild(li, toggleBtn)
        r.appendChild(li, label)
        r.appendChild(li, removeBtn)
        r.appendChild(taskList, li)

  # ── Event handlers ──
  r.addEventListener(addBtn, "click", proc() =
    # In a real app, we'd read from inputField. For the demo, add a placeholder.
    let name = "Task " & $(tasks.len + 1)
    tasks.add(Task(name: name, completed: false))
    taskVersion.val = taskVersion.val + 1
  )

  r.addEventListener(allBtn, "click", proc() =
    currentFilter.val = "all"
  )
  r.addEventListener(activeBtn, "click", proc() =
    currentFilter.val = "active"
  )
  r.addEventListener(completedBtn, "click", proc() =
    currentFilter.val = "completed"
  )
  r.addEventListener(clearBtn, "click", proc() =
    var i = 0
    while i < tasks.len:
      if tasks[i].completed:
        tasks.delete(i)
      else:
        inc i
    taskVersion.val = taskVersion.val + 1
  )

  proc run() =
    # In a full app, this would set up an NSWindow and run the event loop.
    # For now, just verify the component tree was built.
    discard

  result = (root: app, run: run)

# ── Main ──

when isMainModule:
  createRoot proc(dispose: proc()) =
    resetTree()
    let r = CocoaRenderer()
    let (root, run) = buildTaskManager(r)

    echo "Task Manager demo built successfully."
    echo "Root element children: ", r.childCount(root)
    echo "  header, input area, filter bar, task list, footer"

    # Simulate adding tasks via the Add button
    # The Add button is inside inputArea (child 1), at position 1
    let inputArea = r.nthChild(root, 1)
    let addBtn = r.nthChild(inputArea, 1)
    echo "\nSimulating: add 3 tasks..."
    r.fireEvent(addBtn, "click")
    r.fireEvent(addBtn, "click")
    r.fireEvent(addBtn, "click")

    let taskList = r.nthChild(root, 3)
    echo "Task list children: ", r.childCount(taskList)

    # Toggle first task
    echo "Toggling first task..."
    let firstLi = r.nthChild(taskList, 0)
    let toggleBtn = r.nthChild(firstLi, 0)
    r.fireEvent(toggleBtn, "click")

    # Filter to active
    let filterBar = r.nthChild(root, 2)
    let activeBtn = r.nthChild(filterBar, 1)
    echo "Filtering to active..."
    r.fireEvent(activeBtn, "click")
    echo "Visible tasks: ", r.childCount(taskList)

    # Show all again
    let allBtn = r.nthChild(filterBar, 0)
    r.fireEvent(allBtn, "click")
    echo "All tasks visible: ", r.childCount(taskList)

    echo "\nDemo complete."
    run()
    dispose()
