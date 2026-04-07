/* objc_send.h — Typed function-pointer casts for objc_msgSend.
 *
 * On ARM64, variadic and non-variadic calling conventions differ.
 * objc_msgSend must be cast to an EXACT function pointer type matching
 * the target method's signature. No varargs (...) allowed.
 *
 * Naming: nim_msg_{ret}_{nargs}[_{arg_types}]
 *   ret:       id, void, bool, long, ulong, double
 *   nargs:     0, 1, 2, 3
 *   arg_types: id, sel, long, double, cstr (defaults to id if omitted)
 */
#ifndef ISONIM_OBJC_SEND_H
#define ISONIM_OBJC_SEND_H

#include <objc/message.h>
#include <objc/runtime.h>

/* ---- 0 extra args ---- */
#define nim_msg_id_0     ((id(*)(id, SEL))objc_msgSend)
#define nim_msg_void_0   ((void(*)(id, SEL))objc_msgSend)
#define nim_msg_bool_0   ((_Bool(*)(id, SEL))objc_msgSend)
#define nim_msg_long_0   ((long(*)(id, SEL))objc_msgSend)
#define nim_msg_ulong_0  ((unsigned long(*)(id, SEL))objc_msgSend)
#define nim_msg_double_0 ((double(*)(id, SEL))objc_msgSend)

/* ---- 1 extra id arg ---- */
#define nim_msg_id_1     ((id(*)(id, SEL, id))objc_msgSend)
#define nim_msg_void_1   ((void(*)(id, SEL, id))objc_msgSend)
#define nim_msg_bool_1   ((_Bool(*)(id, SEL, id))objc_msgSend)
#define nim_msg_long_1   ((long(*)(id, SEL, id))objc_msgSend)

/* ---- 1 extra SEL arg ---- */
#define nim_msg_id_1_sel   ((id(*)(id, SEL, SEL))objc_msgSend)
#define nim_msg_bool_1_sel ((_Bool(*)(id, SEL, SEL))objc_msgSend)

/* ---- 1 extra cstring arg ---- */
#define nim_msg_id_1_cstr  ((id(*)(id, SEL, const char*))objc_msgSend)

/* ---- 1 extra cstring arg ---- */
#define nim_msg_void_1_cstr ((void(*)(id, SEL, const char*))objc_msgSend)

/* ---- 1 extra long arg ---- */
#define nim_msg_id_1_long   ((id(*)(id, SEL, long))objc_msgSend)
#define nim_msg_void_1_long ((void(*)(id, SEL, long))objc_msgSend)

/* ---- 1 extra double arg ---- */
#define nim_msg_id_1_double  ((id(*)(id, SEL, double))objc_msgSend)
#define nim_msg_void_1_double ((void(*)(id, SEL, double))objc_msgSend)

/* ---- 2 extra id args ---- */
#define nim_msg_id_2     ((id(*)(id, SEL, id, id))objc_msgSend)
#define nim_msg_void_2   ((void(*)(id, SEL, id, id))objc_msgSend)

/* ---- 3 extra id args ---- */
#define nim_msg_id_3     ((id(*)(id, SEL, id, id, id))objc_msgSend)
#define nim_msg_void_3   ((void(*)(id, SEL, id, id, id))objc_msgSend)

/* ---- 1 id + 1 long ---- */
#define nim_msg_void_id_long ((void(*)(id, SEL, id, long))objc_msgSend)

/* ---- Special: pointer arg (for ivar operations etc.) ---- */
#define nim_msg_void_1_ptr  ((void(*)(id, SEL, void*))objc_msgSend)
#define nim_msg_id_1_ptr    ((id(*)(id, SEL, void*))objc_msgSend)

#endif /* ISONIM_OBJC_SEND_H */
