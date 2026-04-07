## Objective-C runtime bindings for Nim.
##
## Provides direct FFI to Apple's Objective-C runtime C API:
## objc_msgSend, objc_getClass, sel_registerName, class creation, etc.
##
## These are the foundation for all Cocoa/UIKit interactions — every
## AppKit or UIKit call goes through objc_msgSend at the C level.

# ---------------------------------------------------------------------------
# Core types
# ---------------------------------------------------------------------------

type
  Id* = distinct pointer
    ## Opaque handle to an Objective-C object instance.
  Class* = distinct pointer
    ## Opaque handle to an Objective-C class.
  Sel* = distinct pointer
    ## Opaque handle to a selector (method name).
  Ivar* = distinct pointer
    ## Opaque handle to an instance variable.
  Method* = distinct pointer
    ## Opaque handle to a method.
  Imp* = pointer
    ## A function pointer (implementation of a method).
  Protocol* = distinct pointer
    ## Opaque handle to a protocol.

proc `==`*(a, b: Id): bool {.borrow.}
proc `==`*(a, b: Class): bool {.borrow.}
proc `==`*(a, b: Sel): bool {.borrow.}
proc `==`*(a, b: Ivar): bool {.borrow.}

proc isNil*(x: Id): bool {.inline.} = pointer(x) == nil
proc isNil*(x: Class): bool {.inline.} = pointer(x) == nil
proc isNil*(x: Sel): bool {.inline.} = pointer(x) == nil
proc isNil*(x: Ivar): bool {.inline.} = pointer(x) == nil

type
  ObjcBool* = bool
    ## Objective-C BOOL type. On ARM64, BOOL is _Bool; on x86_64, signed char.
    ## Nim's `bool` maps to C `_Bool` which matches ARM64 ABI correctly.

const
  YES*: ObjcBool = true
  NO*: ObjcBool = false

let NilId*: Id = Id(nil)
    ## The nil object reference.

# ---------------------------------------------------------------------------
# Runtime functions — class and selector lookup
# ---------------------------------------------------------------------------

proc objc_getClass*(name: cstring): Class
  {.importc, header: "<objc/runtime.h>".}
  ## Returns the class definition for the named class, or nil if not found.

proc objc_lookUpClass*(name: cstring): Class
  {.importc, header: "<objc/runtime.h>".}
  ## Like objc_getClass but returns nil instead of aborting for unknown classes.

proc object_getClass*(obj: Id): Class
  {.importc, header: "<objc/runtime.h>".}
  ## Returns the class of the given object instance.

proc class_getName*(cls: Class): cstring
  {.importc, header: "<objc/runtime.h>".}
  ## Returns the name of the class.

proc class_getSuperclass*(cls: Class): Class
  {.importc, header: "<objc/runtime.h>".}
  ## Returns the superclass of the class.

proc sel_registerName*(name: cstring): Sel
  {.importc, header: "<objc/runtime.h>".}
  ## Registers a method name and returns the corresponding selector.

proc sel_getName*(sel: Sel): cstring
  {.importc, header: "<objc/runtime.h>".}
  ## Returns the string name of a selector.

# ---------------------------------------------------------------------------
# Runtime functions — message sending
# ---------------------------------------------------------------------------
#
# On ARM64, variadic and non-variadic calling conventions differ.
# objc_msgSend MUST be cast to an exact function pointer type matching
# the target method's full signature. Using (...) varargs is broken on ARM64.
#
# We provide overloaded procs for common signatures:
#   msgSend(obj, sel) -> Id / void / bool / clong / culong / cdouble
#   msgSend(obj, sel, arg: Id) -> Id / void / bool / clong
#   msgSend(obj, sel, arg: Sel) -> Id / bool
#   msgSend(obj, sel, a1, a2: Id) -> Id / void
# etc.

{.passL: "-lobjc -framework Foundation -framework CoreGraphics".}

{.emit: """
#include <CoreGraphics/CGGeometry.h>
#include <objc/message.h>
""".}

const objcSendH* = currentSourcePath()[0..^(len("objc_runtime.nim") + 1)] & "objc_send.h"

# ---- 0 extra args ----

proc msgSend*(self: Id; op: Sel): Id
  {.importc: "nim_msg_id_0", header: objcSendH.}
proc msgSendVoid*(self: Id; op: Sel)
  {.importc: "nim_msg_void_0", header: objcSendH.}
proc msgSendBool*(self: Id; op: Sel): ObjcBool
  {.importc: "nim_msg_bool_0", header: objcSendH.}
proc msgSendInt*(self: Id; op: Sel): clong
  {.importc: "nim_msg_long_0", header: objcSendH.}
proc msgSendUint*(self: Id; op: Sel): culong
  {.importc: "nim_msg_ulong_0", header: objcSendH.}
proc msgSendFloat*(self: Id; op: Sel): cdouble
  {.importc: "nim_msg_double_0", header: objcSendH.}

# ---- 1 extra Id arg ----

proc msgSend*(self: Id; op: Sel; a1: Id): Id
  {.importc: "nim_msg_id_1", header: objcSendH.}
proc msgSendVoid*(self: Id; op: Sel; a1: Id)
  {.importc: "nim_msg_void_1", header: objcSendH.}
proc msgSendBool*(self: Id; op: Sel; a1: Id): ObjcBool
  {.importc: "nim_msg_bool_1", header: objcSendH.}
proc msgSendInt*(self: Id; op: Sel; a1: Id): clong
  {.importc: "nim_msg_long_1", header: objcSendH.}

# ---- 1 extra Sel arg ----

proc msgSend*(self: Id; op: Sel; a1: Sel): Id
  {.importc: "nim_msg_id_1_sel", header: objcSendH.}
proc msgSendBool*(self: Id; op: Sel; a1: Sel): ObjcBool
  {.importc: "nim_msg_bool_1_sel", header: objcSendH.}

# ---- 1 extra cstring arg ----

proc msgSend*(self: Id; op: Sel; a1: cstring): Id
  {.importc: "nim_msg_id_1_cstr", header: objcSendH.}
proc msgSendVoid*(self: Id; op: Sel; a1: cstring)
  {.importc: "nim_msg_void_1_cstr", header: objcSendH.}

# ---- 1 extra long arg ----

proc msgSend*(self: Id; op: Sel; a1: clong): Id
  {.importc: "nim_msg_id_1_long", header: objcSendH.}
proc msgSendVoid*(self: Id; op: Sel; a1: clong)
  {.importc: "nim_msg_void_1_long", header: objcSendH.}

# ---- 1 extra double arg ----

proc msgSend*(self: Id; op: Sel; a1: cdouble): Id
  {.importc: "nim_msg_id_1_double", header: objcSendH.}
proc msgSendVoid*(self: Id; op: Sel; a1: cdouble)
  {.importc: "nim_msg_void_1_double", header: objcSendH.}

# ---- 2 extra Id args ----

proc msgSend*(self: Id; op: Sel; a1, a2: Id): Id
  {.importc: "nim_msg_id_2", header: objcSendH.}
proc msgSendVoid*(self: Id; op: Sel; a1, a2: Id)
  {.importc: "nim_msg_void_2", header: objcSendH.}

# ---- 3 extra Id args ----

proc msgSend*(self: Id; op: Sel; a1, a2, a3: Id): Id
  {.importc: "nim_msg_id_3", header: objcSendH.}
proc msgSendVoid*(self: Id; op: Sel; a1, a2, a3: Id)
  {.importc: "nim_msg_void_3", header: objcSendH.}

# ---- 1 Id + 1 long ----

proc msgSendVoid*(self: Id; op: Sel; a1: Id; a2: clong)
  {.importc: "nim_msg_void_id_long", header: objcSendH.}

# ---- 1 pointer arg ----

proc msgSendVoid*(self: Id; op: Sel; a1: pointer)
  {.importc: "nim_msg_void_1_ptr", header: objcSendH.}
proc msgSend*(self: Id; op: Sel; a1: pointer): Id
  {.importc: "nim_msg_id_1_ptr", header: objcSendH.}

# ---- CGRect return (struct returned in registers on ARM64) ----

type
  CGFloat* = cdouble
  CGPoint* {.importc: "CGPoint", header: "<CoreGraphics/CGGeometry.h>".} = object
    x*, y*: CGFloat
  CGSize* {.importc: "CGSize", header: "<CoreGraphics/CGGeometry.h>".} = object
    width*, height*: CGFloat
  CGRect* {.importc: "CGRect", header: "<CoreGraphics/CGGeometry.h>".} = object
    origin*: CGPoint
    size*: CGSize

proc msgSendCGRect*(self: Id; op: Sel): CGRect =
  ## Return a CGRect from an objc_msgSend call.
  ## On ARM64, CGRect fits in registers so objc_msgSend (not _stret) is used.
  ## We use emit because Nim's C backend passes struct returns as out params.
  {.emit: """
  `result` = ((CGRect(*)(id, SEL))objc_msgSend)((id)`self`, (SEL)`op`);
  """.}

# ---------------------------------------------------------------------------
# Runtime functions — dynamic class creation
# ---------------------------------------------------------------------------

proc objc_allocateClassPair*(superclass: Class; name: cstring;
                              extraBytes: csize_t = 0): Class
  {.importc, header: "<objc/runtime.h>".}
  ## Creates a new class/metaclass pair. Returns nil if the name is already taken.
  ## Call class_addMethod / class_addIvar before objc_registerClassPair.

proc objc_registerClassPair*(cls: Class)
  {.importc, header: "<objc/runtime.h>".}
  ## Registers a class pair created with objc_allocateClassPair.
  ## After this call the class can be used to instantiate objects.

proc objc_disposeClassPair*(cls: Class)
  {.importc, header: "<objc/runtime.h>".}
  ## Destroys a class and its metaclass. Do not call if instances exist.

proc class_addMethod*(cls: Class; name: Sel; imp: Imp;
                       types: cstring): ObjcBool
  {.importc, header: "<objc/runtime.h>".}
  ## Adds a new method to a class. Returns YES on success.
  ## `types` is an ObjC type encoding string (e.g. "v@:" for void method).

proc class_addIvar*(cls: Class; name: cstring; size: csize_t;
                     alignment: uint8; types: cstring): ObjcBool
  {.importc, header: "<objc/runtime.h>".}
  ## Adds an instance variable to a class (before registration).

proc class_getInstanceVariable*(cls: Class; name: cstring): Ivar
  {.importc, header: "<objc/runtime.h>".}
  ## Returns the Ivar for the named instance variable.

proc object_setInstanceVariable*(obj: Id; name: cstring;
                                  value: pointer): Ivar
  {.importc, header: "<objc/runtime.h>".}
  ## Sets the value of an instance variable.

proc object_getInstanceVariable*(obj: Id; name: cstring;
                                  outValue: ptr pointer): Ivar
  {.importc, header: "<objc/runtime.h>".}
  ## Gets the value of an instance variable.

proc class_addProtocol*(cls: Class; protocol: Protocol): ObjcBool
  {.importc, header: "<objc/runtime.h>".}
  ## Adds a protocol to a class.

proc objc_getProtocol*(name: cstring): Protocol
  {.importc, header: "<objc/runtime.h>".}
  ## Returns the protocol for the given name.

# ---------------------------------------------------------------------------
# Convenience helpers
# ---------------------------------------------------------------------------

template sel*(name: string): Sel =
  ## Shorthand for sel_registerName.
  sel_registerName(name.cstring)

template cls*(name: string): Class =
  ## Shorthand for objc_getClass.
  objc_getClass(name.cstring)

# ---------------------------------------------------------------------------
# Memory management
# ---------------------------------------------------------------------------

proc retain*(obj: Id): Id {.discardable.} =
  ## Increment the reference count.
  result = msgSend(obj, sel_registerName("retain".cstring))

proc release*(obj: Id) =
  ## Decrement the reference count.
  msgSendVoid(obj, sel_registerName("release".cstring))

proc autorelease*(obj: Id): Id {.discardable.} =
  ## Add to the current autorelease pool.
  result = msgSend(obj, sel_registerName("autorelease".cstring))

template alloc*(className: string): Id =
  ## Allocate an instance: [ClassName alloc]
  msgSend(Id(cls(className)), sel("alloc"))

template allocInit*(className: string): Id =
  ## Allocate and initialize: [[ClassName alloc] init]
  msgSend(msgSend(Id(cls(className)), sel("alloc")), sel("init"))

template new*(className: string): Id =
  ## Shorthand for [ClassName new] (alloc + init).
  msgSend(Id(cls(className)), sel("new"))
