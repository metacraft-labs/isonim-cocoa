## Selection control wrappers — NSSwitch, NSSlider, NSPopUpButton,
## NSSegmentedControl, NSDatePicker, NSStepper.

import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

{.passL: "-framework AppKit".}

# ---------------------------------------------------------------------------
# NSSwitch (macOS 10.15+)
# ---------------------------------------------------------------------------

proc newNSSwitch*(): Id =
  ## Create an NSSwitch control (on/off toggle).
  result = allocInit("NSSwitch")

proc switchState*(sw: Id): bool =
  ## Get the on/off state. NSControlStateValueOn = 1.
  msgSendInt(sw, sel("state")) == 1

proc setSwitchState*(sw: Id, on: bool) =
  ## Set the on/off state.
  let state = clong(if on: 1 else: 0)
  msgSendVoid(sw, sel("setState:"), state)

# ---------------------------------------------------------------------------
# NSSlider
# ---------------------------------------------------------------------------

proc newNSSlider*(min, max, value: cdouble): Id =
  ## Create a continuous NSSlider with the given range and initial value.
  result = allocInit("NSSlider")
  msgSendVoid(result, sel("setMinValue:"), min)
  msgSendVoid(result, sel("setMaxValue:"), max)
  msgSendVoid(result, sel("setDoubleValue:"), value)

proc sliderValue*(sl: Id): cdouble =
  ## Get the current slider value.
  msgSendFloat(sl, sel("doubleValue"))

proc setSliderValue*(sl: Id, v: cdouble) =
  ## Set the slider value.
  msgSendVoid(sl, sel("setDoubleValue:"), v)

proc setSliderMin*(sl: Id, v: cdouble) =
  ## Set the slider minimum value.
  msgSendVoid(sl, sel("setMinValue:"), v)

proc setSliderMax*(sl: Id, v: cdouble) =
  ## Set the slider maximum value.
  msgSendVoid(sl, sel("setMaxValue:"), v)

proc sliderMin*(sl: Id): cdouble =
  ## Get the slider minimum value.
  msgSendFloat(sl, sel("minValue"))

proc sliderMax*(sl: Id): cdouble =
  ## Get the slider maximum value.
  msgSendFloat(sl, sel("maxValue"))

# ---------------------------------------------------------------------------
# NSPopUpButton
# ---------------------------------------------------------------------------

proc newNSPopUpButton*(items: seq[string]): Id =
  ## Create an NSPopUpButton with the given menu items.
  ## Uses emit to call initWithFrame:pullsDown: (CGRect + BOOL signature).
  {.emit: """
  id cls = (id)objc_getClass("NSPopUpButton");
  id alloc = ((id(*)(id, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
  CGRect frame = {{0, 0}, {200, 25}};
  `result` = ((id(*)(id, SEL, CGRect, _Bool))objc_msgSend)(
    alloc, sel_registerName("initWithFrame:pullsDown:"), frame, (_Bool)0);
  """.}
  # Remove default item
  msgSendVoid(result, sel("removeAllItems"))
  for item in items:
    let nsStr = toNSString(item)
    msgSendVoid(result, sel("addItemWithTitle:"), nsStr)
    release(nsStr)

proc popUpSelectedIndex*(btn: Id): int =
  ## Get the index of the selected item.
  int(msgSendInt(btn, sel("indexOfSelectedItem")))

proc popUpSelectIndex*(btn: Id, idx: int) =
  ## Select the item at the given index.
  msgSendVoid(btn, sel("selectItemAtIndex:"), clong(idx))

proc popUpSelectedTitle*(btn: Id): string =
  ## Get the title of the selected item.
  toNimString(msgSend(btn, sel("titleOfSelectedItem")))

proc popUpItemCount*(btn: Id): int =
  ## Get the number of items.
  int(msgSendInt(btn, sel("numberOfItems")))

proc popUpAddItem*(btn: Id, title: string) =
  ## Add an item to the popup button.
  let nsStr = toNSString(title)
  msgSendVoid(btn, sel("addItemWithTitle:"), nsStr)
  release(nsStr)

# ---------------------------------------------------------------------------
# NSSegmentedControl
# ---------------------------------------------------------------------------

proc newNSSegmentedControl*(labels: seq[string]): Id =
  ## Create an NSSegmentedControl with the given segment labels.
  result = allocInit("NSSegmentedControl")
  msgSendVoid(result, sel("setSegmentCount:"), clong(labels.len))
  for i, label in labels:
    let nsStr = toNSString(label)
    msgSendVoid(result, sel("setLabel:forSegment:"), nsStr, clong(i))
    release(nsStr)

proc segmentSelectedIndex*(sc: Id): int =
  ## Get the index of the selected segment (-1 if none).
  int(msgSendInt(sc, sel("selectedSegment")))

proc segmentSelect*(sc: Id, idx: int) =
  ## Select the segment at the given index.
  msgSendVoid(sc, sel("setSelectedSegment:"), clong(idx))

proc segmentLabel*(sc: Id, idx: int): string =
  ## Get the label of the segment at the given index.
  toNimString(msgSend(sc, sel("labelForSegment:"), clong(idx)))

proc segmentCount*(sc: Id): int =
  ## Get the number of segments.
  int(msgSendInt(sc, sel("segmentCount")))

# ---------------------------------------------------------------------------
# NSDatePicker
# ---------------------------------------------------------------------------

proc newNSDatePicker*(): Id =
  ## Create an NSDatePicker with default date (now).
  result = allocInit("NSDatePicker")

proc datePickerValue*(dp: Id): Id =
  ## Get the date value as an NSDate.
  msgSend(dp, sel("dateValue"))

proc setDatePickerValue*(dp: Id, date: Id) =
  ## Set the date value from an NSDate.
  msgSendVoid(dp, sel("setDateValue:"), date)

proc setDatePickerMinDate*(dp: Id, date: Id) =
  ## Set the minimum date constraint.
  msgSendVoid(dp, sel("setMinDate:"), date)

proc setDatePickerMaxDate*(dp: Id, date: Id) =
  ## Set the maximum date constraint.
  msgSendVoid(dp, sel("setMaxDate:"), date)

proc datePickerMinDate*(dp: Id): Id =
  ## Get the minimum date constraint.
  msgSend(dp, sel("minDate"))

proc datePickerMaxDate*(dp: Id): Id =
  ## Get the maximum date constraint.
  msgSend(dp, sel("maxDate"))

# ---------------------------------------------------------------------------
# NSDate helpers (for testing)
# ---------------------------------------------------------------------------

proc newNSDateFromComponents*(year, month, day: int): Id =
  ## Create an NSDate from year/month/day components via NSCalendar.
  let calendar = msgSend(Id(cls("NSCalendar")), sel("currentCalendar"))
  let components = allocInit("NSDateComponents")
  msgSendVoid(components, sel("setYear:"), clong(year))
  msgSendVoid(components, sel("setMonth:"), clong(month))
  msgSendVoid(components, sel("setDay:"), clong(day))
  result = msgSend(calendar, sel("dateFromComponents:"), components)
  release(components)

proc dateComponents*(date: Id): tuple[year, month, day: int] =
  ## Extract year, month, day from an NSDate via NSCalendar.
  let calendar = msgSend(Id(cls("NSCalendar")), sel("currentCalendar"))
  # NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay = 4|8|16 = 28
  let unitFlags = culong(28)
  {.emit: """
  id comps = ((id(*)(id, SEL, unsigned long, id))objc_msgSend)(
    `calendar`, sel_registerName("components:fromDate:"),
    (unsigned long)`unitFlags`, `date`);
  `result`.Field0 = (int)((long(*)(id, SEL))objc_msgSend)(comps, sel_registerName("year"));
  `result`.Field1 = (int)((long(*)(id, SEL))objc_msgSend)(comps, sel_registerName("month"));
  `result`.Field2 = (int)((long(*)(id, SEL))objc_msgSend)(comps, sel_registerName("day"));
  """.}

# ---------------------------------------------------------------------------
# NSStepper
# ---------------------------------------------------------------------------

proc newNSStepper*(min, max, value, increment: cdouble): Id =
  ## Create an NSStepper with the given range, initial value, and increment.
  result = allocInit("NSStepper")
  msgSendVoid(result, sel("setMinValue:"), min)
  msgSendVoid(result, sel("setMaxValue:"), max)
  msgSendVoid(result, sel("setDoubleValue:"), value)
  msgSendVoid(result, sel("setIncrement:"), increment)

proc stepperValue*(st: Id): cdouble =
  ## Get the current stepper value.
  msgSendFloat(st, sel("doubleValue"))

proc setStepperValue*(st: Id, v: cdouble) =
  ## Set the stepper value.
  msgSendVoid(st, sel("setDoubleValue:"), v)

proc stepperIncrement*(st: Id) =
  ## Simulate a click (increment) on the stepper via performClick:nil.
  msgSendVoid(st, sel("performClick:"), NilId)

proc setStepperWraps*(st: Id, wraps: bool) =
  ## Set whether the stepper wraps around at min/max boundaries.
  msgSendVoidBool(st, sel("setValueWraps:"), wraps)

proc stepperWraps*(st: Id): bool =
  ## Get whether the stepper wraps around.
  msgSendBool(st, sel("valueWraps"))
