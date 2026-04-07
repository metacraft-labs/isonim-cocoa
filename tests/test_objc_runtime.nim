## Tests for objc_runtime.nim — ObjC runtime bindings (M0).

import unittest
import isonim_cocoa/objc_runtime

suite "ObjC Runtime - Class Lookup":
  test "objc_getClass returns non-nil for NSObject":
    let c = cls("NSObject")
    check not c.isNil

  test "objc_lookUpClass returns nil for unknown class":
    let c = objc_lookUpClass("ThisClassDoesNotExist_XYZ".cstring)
    check c.isNil

  test "class_getName returns correct name":
    let c = cls("NSObject")
    let name = class_getName(c)
    check $name == "NSObject"

  test "class_getSuperclass of NSObject is nil":
    let c = cls("NSObject")
    let super = class_getSuperclass(c)
    check super.isNil

suite "ObjC Runtime - Selector Registration":
  test "sel_registerName returns non-nil for init":
    let s = sel("init")
    check not s.isNil

  test "sel_getName round-trips":
    let s = sel("description")
    let name = sel_getName(s)
    check $name == "description"

  test "same name produces same selector":
    let s1 = sel("init")
    let s2 = sel("init")
    check s1 == s2

  test "different names produce different selectors":
    let s1 = sel("init")
    let s2 = sel("alloc")
    check s1 != s2

suite "ObjC Runtime - Object Creation & Messaging":
  test "allocate and init NSObject":
    let obj = allocInit("NSObject")
    check not obj.isNil
    release(obj)

  test "new NSObject":
    let obj = new("NSObject")
    check not obj.isNil
    release(obj)

  test "object class is NSObject":
    let obj = new("NSObject")
    let c = object_getClass(obj)
    check $class_getName(c) == "NSObject"
    release(obj)

  test "isKindOfClass: returns YES":
    let obj = new("NSObject")
    let nsObjectClass = cls("NSObject")
    let result = msgSendBool(obj, sel("isKindOfClass:"), Id(nsObjectClass))
    check result == YES
    release(obj)

  test "respondsToSelector: returns YES for init":
    let obj = new("NSObject")
    let result = msgSendBool(obj, sel("respondsToSelector:"), sel("init"))
    check result == YES
    release(obj)

  test "hash returns non-zero":
    let obj = new("NSObject")
    let h = msgSendInt(obj, sel("hash"))
    check h != 0
    release(obj)

  test "description returns non-nil":
    let obj = new("NSObject")
    let desc = msgSend(obj, sel("description"))
    check not desc.isNil
    release(obj)

  test "retain and release cycle":
    let obj = new("NSObject")
    let count1 = msgSendInt(obj, sel("retainCount"))
    retain(obj)
    let count2 = msgSendInt(obj, sel("retainCount"))
    check count2 == count1 + 1
    release(obj)
    let count3 = msgSendInt(obj, sel("retainCount"))
    check count3 == count1
    release(obj)

suite "ObjC Runtime - Dynamic Class Creation":
  test "create and register a custom class":
    let superclass = cls("NSObject")
    let newClass = objc_allocateClassPair(superclass, "NimTestClass_1".cstring)
    check not newClass.isNil
    objc_registerClassPair(newClass)

    let found = cls("NimTestClass_1")
    check found == newClass
    check $class_getName(found) == "NimTestClass_1"
    check class_getSuperclass(found) == superclass

  test "instantiate a dynamically created class":
    let superclass = cls("NSObject")
    let newClass = objc_allocateClassPair(superclass, "NimTestClass_2".cstring)
    check not newClass.isNil
    objc_registerClassPair(newClass)

    let obj = msgSend(Id(newClass), sel("alloc"))
    check not obj.isNil
    let initialized = msgSend(obj, sel("init"))
    check not initialized.isNil

    let c = object_getClass(initialized)
    check $class_getName(c) == "NimTestClass_2"
    release(initialized)

  test "add a method to a dynamic class":
    let superclass = cls("NSObject")
    let newClass = objc_allocateClassPair(superclass, "NimTestClass_3".cstring)
    check not newClass.isNil

    proc testMethod(self: Id; cmd: Sel): Id {.cdecl.} =
      return self

    let added = class_addMethod(
      newClass,
      sel("testMethod"),
      cast[Imp](testMethod),
      "@@:".cstring
    )
    check added == YES
    objc_registerClassPair(newClass)

    let obj = msgSend(msgSend(Id(newClass), sel("alloc")), sel("init"))
    let result = msgSend(obj, sel("testMethod"))
    check result == obj
    release(obj)

  test "duplicate class name returns nil":
    let superclass = cls("NSObject")
    let c1 = objc_allocateClassPair(superclass, "NimTestClass_Dup".cstring)
    check not c1.isNil
    objc_registerClassPair(c1)

    let c2 = objc_allocateClassPair(superclass, "NimTestClass_Dup".cstring)
    check c2.isNil

  test "add instance variable and read/write it":
    let superclass = cls("NSObject")
    let newClass = objc_allocateClassPair(superclass, "NimTestClass_Ivar".cstring)
    check not newClass.isNil

    let added = class_addIvar(
      newClass,
      "nimData".cstring,
      csize_t(sizeof(pointer)),
      uint8(3),
      "^v".cstring
    )
    check added == YES
    objc_registerClassPair(newClass)

    let obj = msgSend(msgSend(Id(newClass), sel("alloc")), sel("init"))

    var testValue: int = 42
    discard object_setInstanceVariable(obj, "nimData".cstring, cast[pointer](testValue))

    var readBack: pointer
    discard object_getInstanceVariable(obj, "nimData".cstring, addr readBack)
    check cast[int](readBack) == 42
    release(obj)
