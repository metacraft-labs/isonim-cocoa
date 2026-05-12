# isonim-cocoa

Nim bindings for Apple's Cocoa (macOS / AppKit) and Cocoa Touch (iOS /
UIKit) frameworks. Implements the IsoNim `RendererBackend` interface so
IsoNim's reactive core and DSL can drive a Cocoa-based native GUI
without going through a Rust shim — the bindings call the Objective-C
runtime's C ABI directly from Nim.

## Architecture

```text
Nim (IsoNim DSL / reactive core)
  │
  v
isonim_cocoa/renderer  (CocoaRenderer, RendererBackend impl)
  │
  v
isonim_cocoa/objc_runtime  (objc_msgSend, sel, class lookup, ...)
  │
  v
AppKit / UIKit (linked via {.passL: "-framework AppKit".})
```

The bindings ship two renderer flavours:

- `isonim_cocoa/renderer.nim` — `CocoaRenderer` backed by AppKit
  (macOS). The HTML-like tag set (`div`, `button`, `input`, `ul`,
  `footer`, ...) maps onto `NSView` subclasses.
- `isonim_cocoa/uikit_renderer.nim` — `UIKitRenderer` backed by UIKit
  (iOS). Shares the same `RendererBackend` protocol.

Both renderers track parent/child relationships and per-element
metadata in Nim-side tables so a virtual tree (where text nodes need
their own elements) maps cleanly onto a Cocoa subview hierarchy.

## Prerequisites

- macOS (Apple Silicon or Intel) with Xcode command-line tools, or
  iOS toolchain via Xcode.
- [Nix](https://nixos.org/) with flakes enabled (provides a pinned Nim,
  XcodeGen, ios-deploy, and the AppKit / Foundation / WebKit /
  CoreGraphics / CoreText / QuartzCore / AVKit / MapKit framework
  bundles).
- The `isonim` core library checked out as a sibling: `../isonim/`.

## Quick start

```bash
direnv allow              # or: nix develop
just verify-env           # sanity-check toolchain
just test                 # run the headless Nim suites
```

## Running the Task Manager demo

Since EX-M5, the canonical Task Manager demo lives in the
[`isonim-examples`](../isonim-examples/) repo at
`isonim-examples/task_app/main_cocoa.nim`. It consumes the shared
`TaskAppVM` (Layer 3) + view template (Layer 2) and only the Cocoa-
specific Layer 1 leaves + Layer 4 composition root differ from the
TUI / web / GPUI / Freya flavours.

### Headless mode (no window server)

Builds the UI tree against `CocoaRenderer` and runs through a scripted
sequence (add tasks, toggle, switch filter) programmatically:

```bash
# From this repo's dev shell:
just demo-run

# Or from the isonim-examples repo's dev shell:
cd ../isonim-examples
nim c -r task_app/main_cocoa.nim
```

### Window mode (real NSApplication)

Mounts the same tree as an `NSWindow`'s content view and enters the
AppKit event loop via `nsAppRun`:

```bash
nim c -r -d:cocoaGui --path:../isonim/src --path:../isonim-examples \
  ../isonim-examples/task_app/main_cocoa.nim
```

> Window mode requires a logged-in macOS session (the AppKit event
> loop expects a real window server). RS-M5 supplies the streaming /
> headless capture path that pairs with `isonim-render-serve`.

## Testing

The task-manager demo's end-to-end tests live in
[`isonim-examples/tests/`](../isonim-examples/tests/) since EX-M5
(`test_cocoa_leaves_compile.nim` for the cross-platform leaf surface
gate and `test_cocoa_leaves_macos_only.nim` for the real-AppKit
scripted scenario). Run them via that repo's `just test` recipe.

The renderer + bindings tests in this repo cover the Cocoa-specific
surface (ObjC runtime, AppKit view wrappers, the `RendererBackend`
impl, snapshots, fake clocks):

```bash
just test                 # headless: ObjC runtime + views + renderer + infra
just test-cross           # cross-renderer compatibility with isonim core
just test-scenarios       # branded scenario snapshots
just test-all             # everything above
```

XCTests (iOS Simulator and device):

```bash
just xcode-test-sim       # XCTests on iPhone Simulator
just xcode-build-device   # signed device build
```

## Project structure

```text
isonim-cocoa/
├── flake.nix                       # Nix devShell (Nim + macOS SDK)
├── Justfile                        # Build / test / Xcode / deploy
├── project.yml                     # XcodeGen project descriptor
├── IsoNimCocoa.xcodeproj/          # Generated Xcode project
├── ios-app/                        # Swift / ObjC thin shell for iOS
├── src/isonim_cocoa/
│   ├── objc_runtime.nim            # Raw ObjC runtime bindings
│   ├── foundation.nim              # NSString / NSDictionary helpers
│   ├── renderer.nim                # CocoaRenderer (AppKit, macOS)
│   ├── uikit_renderer.nim          # UIKitRenderer (UIKit, iOS)
│   ├── app_entry.nim               # iOS branded controls entry
│   ├── app_entry_native.nim        # iOS native controls entry
│   ├── appkit/                     # NSView wrappers (window, layout, ...)
│   ├── uikit/                      # UIView wrappers (iOS counterparts)
│   ├── renderer/                   # Renderer-internal helpers
│   └── testing/                    # FakeClock + snapshot utilities
└── tests/                          # Nim test suite
```

The Task Manager demo lives in
[`isonim-examples`](../isonim-examples/) since EX-M5
(`isonim-examples/task_app/{cocoa/leaves.nim,main_cocoa.nim}`). The
canonical shared core (`task_app/core/{vm,views}.nim`) is consumed by
the TUI / web / GPUI / Freya / Cocoa flavours from a single source.

## Specs

- Cross-platform architecture: [`codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`](../codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md).
- Render-streaming milestones: [`codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`](../codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org).
