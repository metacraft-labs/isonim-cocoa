## Foundation framework wrappers — NSString, NSArray, NSDictionary, NSNumber.
##
## Provides Nim-idiomatic wrappers around commonly used Foundation types.
## All wrappers use the objc_runtime.nim FFI layer.

import isonim_cocoa/objc_runtime

{.passL: "-framework Foundation".}

# ---------------------------------------------------------------------------
# NSString
# ---------------------------------------------------------------------------

proc toNSString*(s: string): Id =
  ## Create an NSString from a Nim string (UTF-8).
  let nsStringClass = Id(cls("NSString"))
  result = msgSend(nsStringClass, sel("alloc"))
  result = msgSend(result, sel("initWithUTF8String:"), s.cstring)

proc toNSString*(s: cstring): Id =
  ## Create an NSString from a C string.
  let nsStringClass = Id(cls("NSString"))
  result = msgSend(nsStringClass, sel("alloc"))
  result = msgSend(result, sel("initWithUTF8String:"), s)

proc toNimString*(nsStr: Id): string =
  ## Extract a Nim string from an NSString (UTF-8).
  if nsStr.isNil:
    return ""
  let cstr = cast[cstring](msgSend(nsStr, sel("UTF8String")))
  if cstr == nil:
    return ""
  result = $cstr

proc nsStringLength*(nsStr: Id): int =
  ## Return the number of UTF-16 code units in an NSString.
  int(msgSendInt(nsStr, sel("length")))

# ---------------------------------------------------------------------------
# NSNumber
# ---------------------------------------------------------------------------

proc toNSNumber*(value: clong): Id =
  ## Create an NSNumber from an integer.
  result = msgSend(Id(cls("NSNumber")), sel("numberWithLong:"), value)

proc toNSNumber*(value: cdouble): Id =
  ## Create an NSNumber from a double.
  result = msgSend(Id(cls("NSNumber")), sel("numberWithDouble:"), value)

proc toNSNumber*(value: bool): Id =
  ## Create an NSNumber from a bool.
  result = msgSend(Id(cls("NSNumber")), sel("numberWithLong:"),
                   clong(if value: 1 else: 0))

proc nsNumberToInt*(nsNum: Id): clong =
  ## Extract an integer from an NSNumber.
  msgSendInt(nsNum, sel("longValue"))

proc nsNumberToFloat*(nsNum: Id): cdouble =
  ## Extract a double from an NSNumber.
  msgSendFloat(nsNum, sel("doubleValue"))

# ---------------------------------------------------------------------------
# NSMutableArray
# ---------------------------------------------------------------------------

proc newNSMutableArray*(capacity: int = 0): Id =
  ## Create a new empty NSMutableArray.
  if capacity > 0:
    result = msgSend(Id(cls("NSMutableArray")), sel("arrayWithCapacity:"),
                     clong(capacity))
  else:
    result = msgSend(Id(cls("NSMutableArray")), sel("array"))
  retain(result)

proc nsArrayCount*(arr: Id): int =
  ## Return the number of elements in an NSArray.
  int(msgSendInt(arr, sel("count")))

proc nsArrayObjectAtIndex*(arr: Id; index: int): Id =
  ## Return the object at the given index.
  msgSend(arr, sel("objectAtIndex:"), clong(index))

proc nsArrayAddObject*(arr: Id; obj: Id) =
  ## Append an object to an NSMutableArray.
  msgSendVoid(arr, sel("addObject:"), obj)

proc nsArrayInsertObject*(arr: Id; obj: Id; index: int) =
  ## Insert an object at the given index in an NSMutableArray.
  msgSendVoid(arr, sel("insertObject:atIndex:"), obj, clong(index))

proc nsArrayRemoveObjectAtIndex*(arr: Id; index: int) =
  ## Remove the object at the given index from an NSMutableArray.
  msgSendVoid(arr, sel("removeObjectAtIndex:"), clong(index))

# ---------------------------------------------------------------------------
# NSMutableDictionary
# ---------------------------------------------------------------------------

proc newNSMutableDictionary*(): Id =
  ## Create a new empty NSMutableDictionary.
  result = msgSend(Id(cls("NSMutableDictionary")), sel("dictionary"))
  retain(result)

proc nsDictCount*(dict: Id): int =
  ## Return the number of key-value pairs.
  int(msgSendInt(dict, sel("count")))

proc nsDictObjectForKey*(dict: Id; key: Id): Id =
  ## Return the value for the given key, or nil if not found.
  msgSend(dict, sel("objectForKey:"), key)

proc nsDictSetObject*(dict: Id; value: Id; key: Id) =
  ## Set a key-value pair in an NSMutableDictionary.
  msgSendVoid(dict, sel("setObject:forKey:"), value, key)

proc nsDictRemoveObjectForKey*(dict: Id; key: Id) =
  ## Remove the value for the given key.
  msgSendVoid(dict, sel("removeObjectForKey:"), key)

# ---------------------------------------------------------------------------
# Color parsing (for style support)
# ---------------------------------------------------------------------------

proc parseHexColor*(hex: string): tuple[r, g, b, a: cdouble] =
  ## Parse a CSS hex color string to normalized RGBA (0.0-1.0).
  ## Supports #RGB, #RGBA, #RRGGBB, #RRGGBBAA.
  var s = hex
  if s.len > 0 and s[0] == '#':
    s = s[1..^1]

  proc hexVal(c: char): int =
    case c
    of '0'..'9': ord(c) - ord('0')
    of 'a'..'f': ord(c) - ord('a') + 10
    of 'A'..'F': ord(c) - ord('A') + 10
    else: 0

  case s.len
  of 3:
    result.r = cdouble(hexVal(s[0]) * 17) / 255.0
    result.g = cdouble(hexVal(s[1]) * 17) / 255.0
    result.b = cdouble(hexVal(s[2]) * 17) / 255.0
    result.a = 1.0
  of 4:
    result.r = cdouble(hexVal(s[0]) * 17) / 255.0
    result.g = cdouble(hexVal(s[1]) * 17) / 255.0
    result.b = cdouble(hexVal(s[2]) * 17) / 255.0
    result.a = cdouble(hexVal(s[3]) * 17) / 255.0
  of 6:
    result.r = cdouble(hexVal(s[0]) * 16 + hexVal(s[1])) / 255.0
    result.g = cdouble(hexVal(s[2]) * 16 + hexVal(s[3])) / 255.0
    result.b = cdouble(hexVal(s[4]) * 16 + hexVal(s[5])) / 255.0
    result.a = 1.0
  of 8:
    result.r = cdouble(hexVal(s[0]) * 16 + hexVal(s[1])) / 255.0
    result.g = cdouble(hexVal(s[2]) * 16 + hexVal(s[3])) / 255.0
    result.b = cdouble(hexVal(s[4]) * 16 + hexVal(s[5])) / 255.0
    result.a = cdouble(hexVal(s[6]) * 16 + hexVal(s[7])) / 255.0
  else:
    result = (0.0, 0.0, 0.0, 1.0)
