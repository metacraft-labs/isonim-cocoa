## Auto Layout module — constraint-based layout via NSLayoutConstraint.
##
## Provides helpers to:
## - Disable autoresizing masks on views
## - Create width/height constraints from CSS-like properties
## - Map padding, gap, alignment, distribution to NSStackView properties
## - Activate/deactivate constraints
## - Force synchronous layout via layoutSubtreeIfNeeded

import std/[tables, strutils]
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

{.passL: "-framework AppKit".}

# Ensure the C file that backs this module's inline `{.emit:}`
# blocks (``setFrame``, ``setFrameOrigin``, ``setFrameSize``,
# ``setEdgeInsets``, and the anchor-with-constant constraint
# constructors) sees the AppKit / ObjC headers that declare
# ``CGRect``, ``id``, ``SEL`` and ``objc_msgSend`` /
# ``sel_registerName``. Without this, any caller that actually
# uses one of those procs (e.g. M-EVP-14's cocoa_adapter layout
# pass) triggers a wall of "use of undeclared identifier"
# errors because the per-module C file otherwise pulls in only
# ``nimbase.h``. (The non-emit procs in this module compile
# fine via ``{.importc, header: objcSendH.}`` indirectly through
# the imported modules above.)
{.emit: """
#include <CoreGraphics/CGGeometry.h>
#include <objc/message.h>
""".}

# ---------------------------------------------------------------------------
# Disable autoresizing mask (required before adding Auto Layout constraints)
# ---------------------------------------------------------------------------

proc setTranslatesAutoresizingMaskIntoConstraints*(view: Id; value: bool) =
  msgSendVoidBool(view, sel("setTranslatesAutoresizingMaskIntoConstraints:"), value)

proc disableAutoresizingMask*(view: Id) =
  setTranslatesAutoresizingMaskIntoConstraints(view, false)

# ---------------------------------------------------------------------------
# Anchor accessors
# ---------------------------------------------------------------------------

proc widthAnchor*(view: Id): Id =
  msgSend(view, sel("widthAnchor"))

proc heightAnchor*(view: Id): Id =
  msgSend(view, sel("heightAnchor"))

proc leadingAnchor*(view: Id): Id =
  msgSend(view, sel("leadingAnchor"))

proc trailingAnchor*(view: Id): Id =
  msgSend(view, sel("trailingAnchor"))

proc topAnchor*(view: Id): Id =
  msgSend(view, sel("topAnchor"))

proc bottomAnchor*(view: Id): Id =
  msgSend(view, sel("bottomAnchor"))

proc centerXAnchor*(view: Id): Id =
  msgSend(view, sel("centerXAnchor"))

proc centerYAnchor*(view: Id): Id =
  msgSend(view, sel("centerYAnchor"))

# ---------------------------------------------------------------------------
# Constraint creation
# ---------------------------------------------------------------------------

proc constraintEqualToConstant*(anchor: Id; constant: cdouble): Id =
  ## [anchor constraintEqualToConstant:constant]
  msgSend(anchor, sel("constraintEqualToConstant:"), constant)

proc constraintEqualToAnchor*(anchor, otherAnchor: Id): Id =
  ## [anchor constraintEqualToAnchor:otherAnchor]
  msgSend(anchor, sel("constraintEqualToAnchor:"), otherAnchor)

proc constraintEqualToAnchorWithConstant*(anchor, otherAnchor: Id; constant: cdouble): Id =
  ## [anchor constraintEqualToAnchor:otherAnchor constant:constant]
  {.emit: """
  `result` = ((id(*)(id, SEL, id, double))objc_msgSend)(
    (id)`anchor`, sel_registerName("constraintEqualToAnchor:constant:"),
    (id)`otherAnchor`, `constant`);
  """.}

proc constraintGreaterThanOrEqualToConstant*(anchor: Id; constant: cdouble): Id =
  msgSend(anchor, sel("constraintGreaterThanOrEqualToConstant:"), constant)

# ---------------------------------------------------------------------------
# Constraint multiplier (for proportional sizing)
# ---------------------------------------------------------------------------

proc constraintEqualToAnchorMultiplier*(anchor, otherAnchor: Id; multiplier: cdouble): Id =
  ## [anchor constraintEqualToAnchor:otherAnchor multiplier:multiplier]
  {.emit: """
  `result` = ((id(*)(id, SEL, id, double))objc_msgSend)(
    (id)`anchor`, sel_registerName("constraintEqualToAnchor:multiplier:"),
    (id)`otherAnchor`, `multiplier`);
  """.}

# ---------------------------------------------------------------------------
# Constraint activation / deactivation
# ---------------------------------------------------------------------------

proc setActive*(constraint: Id; active: bool) =
  msgSendVoidBool(constraint, sel("setActive:"), active)

proc isActive*(constraint: Id): bool =
  msgSendBool(constraint, sel("isActive"))

proc activateConstraints*(constraints: openArray[Id]) =
  ## [NSLayoutConstraint activateConstraints:array]
  let arr = newNSMutableArray(constraints.len)
  for c in constraints:
    nsArrayAddObject(arr, c)
  msgSendVoid(Id(cls("NSLayoutConstraint")), sel("activateConstraints:"), arr)
  release(arr)

proc deactivateConstraints*(constraints: openArray[Id]) =
  ## [NSLayoutConstraint deactivateConstraints:array]
  let arr = newNSMutableArray(constraints.len)
  for c in constraints:
    nsArrayAddObject(arr, c)
  msgSendVoid(Id(cls("NSLayoutConstraint")), sel("deactivateConstraints:"), arr)
  release(arr)

# ---------------------------------------------------------------------------
# Constraint properties
# ---------------------------------------------------------------------------

proc constraintConstant*(constraint: Id): cdouble =
  msgSendFloat(constraint, sel("constant"))

proc setConstraintConstant*(constraint: Id; value: cdouble) =
  msgSendVoid(constraint, sel("setConstant:"), value)

proc constraintIsActive*(constraint: Id): bool =
  msgSendBool(constraint, sel("isActive"))

# ---------------------------------------------------------------------------
# Layout forcing
# ---------------------------------------------------------------------------

proc layoutSubtreeIfNeeded*(view: Id) =
  ## Force a synchronous layout pass. Works without a window.
  msgSendVoid(view, sel("layoutSubtreeIfNeeded"))

proc needsLayout*(view: Id) =
  msgSendVoidBool(view, sel("setNeedsLayout:"), true)

# ---------------------------------------------------------------------------
# Frame reading (after layout)
# ---------------------------------------------------------------------------

proc frame*(view: Id): CGRect =
  msgSendCGRect(view, sel("frame"))

proc setFrameSize*(view: Id; width, height: cdouble) =
  {.emit: """
  CGSize sz = { `width`, `height` };
  ((void(*)(id, SEL, CGSize))objc_msgSend)(
    `view`, sel_registerName("setFrameSize:"), sz);
  """.}

proc setFrameOrigin*(view: Id; x, y: cdouble) =
  {.emit: """
  CGPoint pt = { `x`, `y` };
  ((void(*)(id, SEL, CGPoint))objc_msgSend)(
    `view`, sel_registerName("setFrameOrigin:"), pt);
  """.}

proc setFrame*(view: Id; x, y, width, height: cdouble) =
  {.emit: """
  CGRect r = { { `x`, `y` }, { `width`, `height` } };
  ((void(*)(id, SEL, CGRect))objc_msgSend)(
    `view`, sel_registerName("setFrame:"), r);
  """.}

# ---------------------------------------------------------------------------
# NSStackView layout properties
# ---------------------------------------------------------------------------

proc setAlignment*(stackView: Id; alignment: clong) =
  ## NSLayoutAttributeCenterY = 4 (center vertically in horizontal stack)
  ## NSLayoutAttributeCenterX = 3 (center horizontally in vertical stack)
  ## NSLayoutAttributeTop = 1
  ## NSLayoutAttributeLeading = 5
  msgSendVoid(stackView, sel("setAlignment:"), alignment)

proc setDistribution*(stackView: Id; distribution: clong) =
  ## NSStackViewDistribution:
  ##   0 = gravityAreas
  ##   1 = equalCentering
  ##   2 = equalSpacing
  ##   3 = fillEqually
  ##   4 = fillProportionally
  ##   5 = fill
  msgSendVoid(stackView, sel("setDistribution:"), distribution)

# ---------------------------------------------------------------------------
# Edge insets (padding) for NSStackView
# ---------------------------------------------------------------------------

proc setEdgeInsets*(view: Id; top, left, bottom, right: cdouble) =
  ## Set NSEdgeInsets on an NSStackView.
  ## Uses edgeInsets property (macOS 10.11+).
  {.emit: """
  typedef struct { double top; double left; double bottom; double right; } NSEdgeInsets;
  NSEdgeInsets insets = { `top`, `left`, `bottom`, `right` };
  ((void(*)(id, SEL, NSEdgeInsets))objc_msgSend)(
    `view`, sel_registerName("setEdgeInsets:"), insets);
  """.}

# ---------------------------------------------------------------------------
# Constraint tracking per view
# ---------------------------------------------------------------------------

type
  ConstraintSet* = object
    ## Tracks Auto Layout constraints associated with a view, keyed by
    ## CSS property name so they can be updated or deactivated.
    constraints*: Table[string, Id]

var viewConstraints: Table[pointer, ConstraintSet]

proc getConstraintSet*(view: Id): ptr ConstraintSet =
  let p = pointer(view)
  if p notin viewConstraints:
    viewConstraints[p] = ConstraintSet()
  addr viewConstraints[p]

proc hasConstraint*(view: Id; prop: string): bool =
  let p = pointer(view)
  p in viewConstraints and prop in viewConstraints[p].constraints

proc getConstraint*(view: Id; prop: string): Id =
  let p = pointer(view)
  if p in viewConstraints and prop in viewConstraints[p].constraints:
    viewConstraints[p].constraints[prop]
  else:
    NilId

proc setConstraint*(view: Id; prop: string; constraint: Id) =
  let cs = getConstraintSet(view)
  # Deactivate old constraint if exists
  if prop in cs.constraints:
    setActive(cs.constraints[prop], false)
  cs.constraints[prop] = constraint
  setActive(constraint, true)

proc removeConstraint*(view: Id; prop: string) =
  let p = pointer(view)
  if p in viewConstraints and prop in viewConstraints[p].constraints:
    setActive(viewConstraints[p].constraints[prop], false)
    viewConstraints[p].constraints.del(prop)

proc clearConstraints*(view: Id) =
  let p = pointer(view)
  if p in viewConstraints:
    for prop, c in viewConstraints[p].constraints:
      setActive(c, false)
    viewConstraints.del(p)

proc resetConstraintTracking*() =
  ## Clear all constraint tracking (for test isolation).
  viewConstraints.clear()

# ---------------------------------------------------------------------------
# CSS-like style application via Auto Layout
# ---------------------------------------------------------------------------

proc applyLayoutStyle*(view: Id; prop, value: string; isStack: bool = false) =
  ## Apply a CSS-like style property via Auto Layout constraints.
  ## Call disableAutoresizingMask on the view first.
  case prop
  of "width":
    let px = try: parseFloat(value.replace("px", "").strip()) except: 0.0
    if px > 0:
      let c = constraintEqualToConstant(widthAnchor(view), px)
      setConstraint(view, "width", c)
  of "height":
    let px = try: parseFloat(value.replace("px", "").strip()) except: 0.0
    if px > 0:
      let c = constraintEqualToConstant(heightAnchor(view), px)
      setConstraint(view, "height", c)
  of "gap":
    if isStack:
      let spacing = try: parseFloat(value.replace("px", "").strip()) except: 0.0
      setSpacing(view, spacing)
  of "padding":
    if isStack:
      let px = try: parseFloat(value.replace("px", "").strip()) except: 0.0
      setEdgeInsets(view, px, px, px, px)
  of "padding-top", "padding-left", "padding-bottom", "padding-right":
    discard  # Would need per-side tracking; handled by "padding" shorthand
  of "align-items":
    if isStack:
      case value
      of "center":
        # NSLayoutAttributeCenterY = 4 for horizontal, CenterX = 3 for vertical
        # We use centerX (3) as default since stacks are vertical by default
        setAlignment(view, 9)  # NSLayoutAttributeCenterY = 9 in newer API
      of "flex-start", "start":
        setAlignment(view, 5)  # NSLayoutAttributeLeading
      of "flex-end", "end":
        setAlignment(view, 6)  # NSLayoutAttributeTrailing
      of "stretch":
        setAlignment(view, 0)  # Default (width of stack)
      else:
        discard
  of "justify-content":
    if isStack:
      case value
      of "space-between":
        setDistribution(view, 2)  # equalSpacing
      of "space-around", "space-evenly":
        setDistribution(view, 1)  # equalCentering
      of "center":
        setDistribution(view, 0)  # gravityAreas
      of "flex-start", "start":
        setDistribution(view, 0)  # gravityAreas
      of "flex-end", "end":
        setDistribution(view, 0)  # gravityAreas
      else:
        discard
  of "flex":
    discard  # Handled at parent level during layout
  else:
    discard

# ---------------------------------------------------------------------------
# Pin edges helpers (for child-in-parent constraints)
# ---------------------------------------------------------------------------

proc pinEdges*(child, parent: Id; inset: cdouble = 0.0) =
  ## Pin all four edges of child to parent with optional inset.
  disableAutoresizingMask(child)
  let cTop = constraintEqualToAnchorWithConstant(topAnchor(child), topAnchor(parent), inset)
  let cLeading = constraintEqualToAnchorWithConstant(leadingAnchor(child), leadingAnchor(parent), inset)
  let cBottom = constraintEqualToAnchorWithConstant(bottomAnchor(parent), bottomAnchor(child), inset)
  let cTrailing = constraintEqualToAnchorWithConstant(trailingAnchor(parent), trailingAnchor(child), inset)
  activateConstraints([cTop, cLeading, cBottom, cTrailing])

proc pinToParentWithPadding*(child, parent: Id; top, left, bottom, right: cdouble) =
  ## Pin child edges to parent with per-side padding.
  disableAutoresizingMask(child)
  let cTop = constraintEqualToAnchorWithConstant(topAnchor(child), topAnchor(parent), top)
  let cLeading = constraintEqualToAnchorWithConstant(leadingAnchor(child), leadingAnchor(parent), left)
  let cBottom = constraintEqualToAnchorWithConstant(bottomAnchor(parent), bottomAnchor(child), bottom)
  let cTrailing = constraintEqualToAnchorWithConstant(trailingAnchor(parent), trailingAnchor(child), right)
  activateConstraints([cTop, cLeading, cBottom, cTrailing])
