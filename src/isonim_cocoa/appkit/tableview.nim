## NSTableView with dynamic ObjC datasource backed by Nim closures.
##
## Creates a `NimTableDataSource` ObjC class at runtime that implements
## NSTableViewDataSource and NSTableViewDelegate. The datasource calls
## back into Nim closures for row count and view creation.

import std/tables
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

{.passL: "-framework AppKit".}

# ---------------------------------------------------------------------------
# Datasource callback storage
# ---------------------------------------------------------------------------

type
  TableCallbacks* = object
    numberOfRows*: proc(): int
    viewForRow*: proc(row: int): Id

# Map from datasource ObjC object pointer -> callbacks
var datasourceCallbacks: Table[pointer, TableCallbacks]

# Track how many views have been created (for cell reuse verification)
var viewCreationCount*: int = 0

proc resetViewCreationCount*() =
  viewCreationCount = 0

# ---------------------------------------------------------------------------
# ObjC datasource methods (cdecl, called by the runtime)
# ---------------------------------------------------------------------------

proc nimNumberOfRows(self: Id; cmd: Sel; tableView: Id): clong {.cdecl.} =
  let p = pointer(self)
  if p in datasourceCallbacks:
    result = clong(datasourceCallbacks[p].numberOfRows())
  else:
    result = 0

proc nimViewForRow(self: Id; cmd: Sel; tableView: Id; column: Id;
                   row: clong): Id {.cdecl.} =
  let p = pointer(self)
  if p in datasourceCallbacks:
    inc viewCreationCount
    result = datasourceCallbacks[p].viewForRow(int(row))
  else:
    result = NilId

# ---------------------------------------------------------------------------
# Dynamic ObjC class: NimTableDataSource
# ---------------------------------------------------------------------------

var nimTableDataSourceClass: Class

proc ensureTableDataSourceClass(): Class =
  if nimTableDataSourceClass.isNil:
    nimTableDataSourceClass = objc_allocateClassPair(
      cls("NSObject"), "NimTableDataSource".cstring)

    # Adopt NSTableViewDataSource protocol
    let dsProto = objc_getProtocol("NSTableViewDataSource".cstring)
    if not dsProto.isNil:
      discard class_addProtocol(nimTableDataSourceClass, dsProto)

    # Adopt NSTableViewDelegate protocol
    let delProto = objc_getProtocol("NSTableViewDelegate".cstring)
    if not delProto.isNil:
      discard class_addProtocol(nimTableDataSourceClass, delProto)

    # numberOfRowsInTableView: -> NSInteger
    # Type encoding: l@:@ (long, self, _cmd, tableView)
    discard class_addMethod(nimTableDataSourceClass,
      sel("numberOfRowsInTableView:"),
      cast[Imp](nimNumberOfRows), "l@:@".cstring)

    # tableView:viewForTableColumn:row: -> NSView
    # Type encoding: @@:@@l (id, self, _cmd, tableView, column, row)
    discard class_addMethod(nimTableDataSourceClass,
      sel("tableView:viewForTableColumn:row:"),
      cast[Imp](nimViewForRow), "@@:@@l".cstring)

    objc_registerClassPair(nimTableDataSourceClass)
  result = nimTableDataSourceClass

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc newNimTableDataSource*(numberOfRows: proc(): int;
                             viewForRow: proc(row: int): Id): Id =
  ## Create a NimTableDataSource ObjC object backed by Nim closures.
  let cls = ensureTableDataSourceClass()
  result = msgSend(msgSend(Id(cls), sel("alloc")), sel("init"))
  datasourceCallbacks[pointer(result)] = TableCallbacks(
    numberOfRows: numberOfRows,
    viewForRow: viewForRow
  )

proc newNSTableView*(numberOfRows: proc(): int;
                      viewForRow: proc(row: int): Id): (Id, Id) =
  ## Create an NSTableView with a NimTableDataSource.
  ## Returns (tableView, datasource).
  let table = allocInit("NSTableView")

  # Add a default column
  let colId = toNSString("main")
  let column = msgSend(Id(cls("NSTableColumn")), sel("alloc"))
  let initdCol = msgSend(column, sel("initWithIdentifier:"), colId)
  msgSendVoid(table, sel("addTableColumn:"), initdCol)
  release(colId)

  let ds = newNimTableDataSource(numberOfRows, viewForRow)

  # Set datasource and delegate
  msgSendVoid(table, sel("setDataSource:"), ds)
  msgSendVoid(table, sel("setDelegate:"), ds)

  result = (table, ds)

proc reloadData*(table: Id) =
  ## Tell the table view to reload all data from its datasource.
  msgSendVoid(table, sel("reloadData"))

proc noteNumberOfRowsChanged*(table: Id) =
  ## Notify the table that the number of rows has changed.
  msgSendVoid(table, sel("noteNumberOfRowsChanged"))

# ---------------------------------------------------------------------------
# Reset (for test isolation)
# ---------------------------------------------------------------------------

proc resetTableView*() =
  datasourceCallbacks.clear()
  viewCreationCount = 0
