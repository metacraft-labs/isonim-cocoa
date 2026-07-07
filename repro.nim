## Reprobuild project file for isonim-cocoa.
##
## **Typed-Cross-Project-Deps rollout.** ``isonim-cocoa`` is the IsoNim
## Apple-platform renderer (AppKit/UIKit ``RendererBackend`` on top of a
## direct Objective-C runtime FFI). Its ``src/`` tree — and every test that
## reaches ``isonim_cocoa/objc_runtime`` (directly or transitively through
## ``isonim_cocoa/renderer`` / ``isonim_cocoa/foundation`` /
## ``isonim_cocoa/appkit/*`` / ``isonim_cocoa/testing/fake_clock`` etc.) —
## is **macOS-only by construction**: ``src/isonim_cocoa/objc_runtime.nim``
## FFI-imports ``<objc/runtime.h>`` / ``<objc/message.h>`` unconditionally,
## which do not exist on a Linux host (verified: ``nim c`` fails at the C
## back-end with ``fatal error: objc/runtime.h: No such file or directory``).
## The macOS test corpus additionally consumes the ``isonim`` sibling (via
## ``nim.cfg``'s ``--path:../isonim/src`` and ``import isonim/...`` in
## ``test_cross_renderer`` / ``test_scenario_snapshots`` / ``test_theme_cocoa``).
##
## **What runs on THIS Linux host — the LEAF corpus.** Six test files gate
## their entire AppKit/objc/isonim-touching body behind a
## ``when defined(macosx): <macOS body> else: <suite … check true>`` at the
## file's own top level, so on a non-macOS host they compile with NO
## ``isonim_cocoa/*`` and NO ``isonim`` import at all and run their
## ``else:`` arm — a real ``unittest`` ``suite`` whose one ``test`` asserts
## ``check true`` (an exit-0 body the file itself authors for non-macOS
## hosts, NOT a ``skip()`` and NOT a disabled test). These six are the only
## host-runnable tests; each compiles + runs to exit 0 on this Linux host
## (verified). Because their Linux arm imports neither ``isonim_cocoa`` nor
## ``isonim``, the host-runnable closure reaches NO workspace sibling —
## exactly the situation the landed ``isonim-render-serve`` recipe records
## for its cocoa/gpui/freya adapter tests. So on this host the recipe is a
## **LEAF**: the ``uses:`` block is just the toolchain floor, there is no
## ``uses: "<sibling>"`` edge, and the lock is self-only. (The ``isonim``
## sibling edge would only be needed by the macOS-only tests below, which
## are host-gated OUT of the Linux graph — mirroring the repo's own
## per-file ``when defined(macosx)`` guards; it is NOT dropped or weakened,
## just absent on the wrong OS, and would be added by a macOS extraction.)
##
## A Mode 1 / Mode 3 hybrid (per
## ``reprobuild-specs/Three-Mode-Convention-System.md``) modelled on the
## canonical ``runquota/repro.nim`` / ``codetracer-trace-format-nim/repro.nim``
## / ``nim-stackable-hooks/repro.nim`` / ``isonim-render-serve/repro.nim``
## recipes:
##
## * Declares the upstream tool floor via ``uses:`` so any consumer that
##   depends on this repo (via ``uses: "isonim_cocoa"``) picks up the same
##   toolchain floor the nimble file's ``requires "nim >= 2.0.0"`` implies.
## * Declares ``library isonim_cocoa`` so a consumer (e.g.
##   ``isonim-render-serve``'s deferred cocoa-adapter tests) can express a
##   workspace dependency on this repo. The importable umbrella is
##   ``src/isonim_cocoa/renderer.nim`` and the ``src/`` tree beneath it
##   (consumers ``import isonim_cocoa/renderer`` etc.); this ``library``
##   marker is the facade — like ``isonim-render-serve``'s own it is a
##   consumption anchor, not a standalone src-compile edge (the src is
##   macOS-only and threaded onto consumers' ``nim c --path`` by the
##   engine, not built here).
## * Emits, per HOST-RUNNABLE test file under ``tests/``, a BUILD edge
##   (``buildNimUnittest.build``) that compiles ``build/test-bin/<stem>``
##   and an EXECUTE edge (``edge.testBinary.run``) that runs it — the
##   two-edge test template from ``reprobuild-specs/Package-Model.md``
##   §"The test template". BUILD halves collect into ``test-builds``;
##   EXECUTE halves into ``test`` so ``repro build test`` / ``repro test``
##   materialise the runnable closure.
##
## **Per-test platform gating.** Re-derived from each file's imports and
## its own ``when defined(...)`` head-guard (the nimble file has no test
## task; the ``Justfile``'s ``test`` target lists only a macOS subset and
## is not authoritative for the Linux graph):
##
##   * HOST-RUNNABLE on Linux (the six below). Each opens with a top-level
##     ``import std/[...]`` ONLY, then ``when defined(macosx): <body that
##     imports isonim_cocoa/*> else: suite "…": test "skipped on non-macOS
##     hosts": check true``. On Linux the ``else:`` arm is the whole
##     program: no objc, no isonim, real ``unittest`` suite, exit 0.
##       - ``tests/test_metal_capture_frame_budget.nim``   (EPP-M4)
##       - ``tests/test_metal_capture_round_trip.nim``     (EPP-M4)
##       - ``tests/test_videotoolbox_bitrate.nim``         (EPP-M5)
##       - ``tests/test_videotoolbox_dim_envelope.nim``    (EPP-M9)
##       - ``tests/test_videotoolbox_resize_lifecycle.nim``(EPP-M5)
##       - ``tests/test_videotoolbox_round_trip.nim``      (EPP-M5)
##
##   * macOS-ONLY — host-gated OUT of the Linux graph (NOT weakened, NOT
##     deleted; they run under the repo's own macOS ``just test`` and would
##     get edges on a macOS extraction, consuming ``library isonim_cocoa``
##     and — for the ``isonim``-importing ones — a ``uses: "isonim"`` edge).
##     Each ``import``s ``isonim_cocoa/objc_runtime`` (or a module that
##     does: ``renderer`` / ``foundation`` / ``appkit/*`` / ``testing/*``)
##     UNCONDITIONALLY at top level, so it fails to COMPILE off macOS
##     (missing ``<objc/runtime.h>``):
##       - ``tests/test_objc_runtime.nim``       (imports objc_runtime)
##       - ``tests/test_appkit_views.nim``       (objc_runtime + appkit/views)
##       - ``tests/test_accessibility.nim``      (appkit/accessibility)
##       - ``tests/test_autolayout.nim``         (appkit/autolayout)
##       - ``tests/test_dialogs.nim``            (appkit/dialogs)
##       - ``tests/test_lifecycle.nim``          (appkit/lifecycle + window)
##       - ``tests/test_media.nim``              (appkit/media)
##       - ``tests/test_navigation.nim``         (appkit/navigation)
##       - ``tests/test_progress.nim``           (appkit/progress)
##       - ``tests/test_renderer.nim``           (objc_runtime + renderer)
##       - ``tests/test_scrollview.nim``         (appkit/scrollview + tableview)
##       - ``tests/test_selectioncontrols.nim``  (appkit/selectioncontrols)
##       - ``tests/test_snapshots.nim``          (appkit/views + snapshots)
##       - ``tests/test_textcontrols.nim``       (appkit/textcontrols)
##       - ``tests/test_theme_cocoa.nim``        (isonim/theming + renderer)
##       - ``tests/test_fake_clock.nim``         (testing/fake_clock → objc_runtime)
##       - ``tests/test_cross_renderer.nim``     (isonim/* + renderer)
##       - ``tests/test_scenario_snapshots.nim`` (isonim/* + renderer)
##
## **Module search path + compile flags.** The six host-runnable tests
## import ONLY ``std/*`` on Linux, so no ``--path`` is strictly required to
## build them; ``paths = @["src"]`` (matching the repo's ``nim.cfg``
## ``--path:src``) is threaded for consistency with the repo's own build
## and is harmless (nothing under ``src`` is reached by the ``else:`` arm).
## Each BUILD edge reproduces the repo's DEFAULT matrix point —
## ``nim c … --mm:orc -d:release --threads:on`` (``just test`` /
## ``test-orc`` shape used across the IsoNim rollout): ``--mm:orc`` via
## ``mm:``, ``-d:release`` via ``defines:``, ``--threads:on`` via the
## wrapper's default ``threadsOn``.
##
## **Tool provisioning.** ``defaultToolProvisioning "path"`` matches the
## canonical recipes: the nix dev shell puts ``nim`` + ``gcc`` on ``PATH``,
## so the weak-local PATH resolver is the right default. Without it
## ``repro build`` refuses to run with "typed tool provisioning is required
## for uses declarations".

import repro_project_dsl

# ``ct_test_nim_unittest`` supplies the ``buildNimUnittest.build(...)``
# typed-tool used by every test BUILD edge below, and the
# ``edge.testBinary.run(...)`` UFCS dispatch for the EXECUTE edges. It
# re-exports ``repro_project_dsl`` so the import order is unimportant. Like
# the other IsoNim leaf recipes this file does NOT import
# ``ct_test_runner_install`` (engine-coupled, reprobuild-internal): the
# execute edges route through the engine's default direct-binary runner
# (run the binary, key on exit status), which is exactly the exit-0
# verification this corpus needs — Nim ``unittest`` prints per-suite
# results and exits non-zero on failure.
import ct_test_nim_unittest

type
  CocoaTestSpec = object
    ## One entry per host-runnable test file. ``source`` is the
    ## repo-relative ``.nim`` path; ``binary`` is the
    ## ``build/test-bin/<stem>`` output.
    source: string
    binary: string

const hostRunnableTestSpecs: seq[CocoaTestSpec] = @[
  # The six ``when defined(macosx): … else: suite/check true`` tests. On a
  # non-macOS host the ``else:`` arm is the whole program — no objc, no
  # isonim import — so they compile + run to exit 0 on this Linux host.
  CocoaTestSpec(source: "tests/test_metal_capture_frame_budget.nim",
    binary: "build/test-bin/test_metal_capture_frame_budget"),
  CocoaTestSpec(source: "tests/test_metal_capture_round_trip.nim",
    binary: "build/test-bin/test_metal_capture_round_trip"),
  CocoaTestSpec(source: "tests/test_videotoolbox_bitrate.nim",
    binary: "build/test-bin/test_videotoolbox_bitrate"),
  CocoaTestSpec(source: "tests/test_videotoolbox_dim_envelope.nim",
    binary: "build/test-bin/test_videotoolbox_dim_envelope"),
  CocoaTestSpec(source: "tests/test_videotoolbox_resize_lifecycle.nim",
    binary: "build/test-bin/test_videotoolbox_resize_lifecycle"),
  CocoaTestSpec(source: "tests/test_videotoolbox_round_trip.nim",
    binary: "build/test-bin/test_videotoolbox_round_trip"),
]

package isonim_cocoa:
  defaultToolProvisioning "path"

  uses:
    # Toolchain floor — the PATH-resolvable binaries the build needs.
    # ``nim`` compiles every host-runnable test binary (the
    # ``buildNimUnittest.build`` edges below, matching the nimble file's
    # ``requires "nim >= 2.0.0"``); ``gcc`` is the C back-end ``nim c``
    # shells out to and links through. ``gcc >=12`` matches the workspace
    # toolchain floor. Sufficient for the path-mode resolver under
    # ``nix develop``.
    #
    # No ``uses: "isonim"`` here: the ``isonim`` sibling is reached only by
    # the macOS-only tests (host-gated OUT above), never by the six
    # host-runnable ``else:``-arm tests. A macOS extraction — where the
    # AppKit corpus is in the graph — would add ``uses: "isonim"``.
    "nim >=2.0"
    "gcc >=12"

  # Library declaration — the importable ``src/`` surface when this package
  # is consumed via ``uses: "isonim_cocoa"`` (e.g. the deferred cocoa-adapter
  # tests in ``isonim-render-serve``). The umbrella entry is
  # ``src/isonim_cocoa/renderer.nim`` (consumers ``import
  # isonim_cocoa/renderer``); the ``appkit/*`` / ``foundation`` /
  # ``objc_runtime`` submodules are importable too. Like
  # ``isonim-render-serve``'s ``library`` marker this is a consumption
  # facade, not a standalone src-compile edge (the src is macOS-only; the
  # engine threads it onto a macOS consumer's ``nim c --path``).
  library isonim_cocoa

  build:
    # Two-edge test template (Package-Model.md §"The test template"): one
    # compile BUILD edge + one EXECUTE edge per host-runnable test file.
    # BUILD halves collect into ``test-builds`` (compile verification);
    # EXECUTE halves into ``test`` so ``repro test`` / ``repro build test``
    # materialise the runnable closure (each execute edge transitively
    # depends on its build edge).
    #
    # Compile flags reproduce the IsoNim default matrix point
    # (``--mm:orc -d:release --threads:on``): ``mm = "orc"``,
    # ``defines = @["release"]``, ``threadsOn`` (wrapper default true).
    # ``paths = @["src"]`` mirrors the repo's ``nim.cfg`` ``--path:src``
    # (harmless — the ``else:`` arm reaches nothing under ``src``); ``src``
    # is an ``extraInput`` so the tree is a declared input of the compile.
    var testBuildActions: seq[BuildActionDef] = @[]
    var testExecuteActions: seq[BuildActionDef] = @[]

    proc emitTestPair(source, binary: string;
                      buildActions, executeActions: var seq[BuildActionDef]) =
      var lastSlash = -1
      for i in 0 ..< binary.len:
        if binary[i] == '/' or binary[i] == '\\':
          lastSlash = i
      let stem =
        if lastSlash >= 0: binary[lastSlash + 1 .. ^1]
        else: binary
      let edge = buildNimUnittest.build(
        source = source,
        binary = binary,
        defines = @["release"],
        paths = @["src"],
        mm = "orc",
        extraInputs = @["src"],
        actionId = "isonim_cocoa.test_build." & stem)
      buildActions.add(edge.action)
      # ``registerImplicitName = false`` because the BUILD edge already owns
      # the binary basename as the implicit target name; the explicit
      # ``actionId`` is the execute edge's selector (two-edge shape).
      let executeEdge = edge.testBinary.run(
        actionId = "isonim_cocoa.test_execute." & stem,
        registerImplicitName = false)
      executeActions.add(executeEdge)

    for spec in hostRunnableTestSpecs:
      emitTestPair(spec.source, spec.binary,
        testBuildActions, testExecuteActions)

    discard collect("test", testExecuteActions)
    discard collect("test-builds", testBuildActions)
