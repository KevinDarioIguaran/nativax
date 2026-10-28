/*
    sokol_app backend for include/nativax/platform.h.

    This is the only translation unit that includes sokol_app.h on the runtime
    side. It owns the OS window and translates the backend event struct into
    NxPlatformEvent: CSS-pixel coordinates, NxKey values, touch points and
    clipboard payloads. The rest of the runtime never sees a sokol type.
*/
#include "nativax/platform.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <GL/gl.h>

#include "sokol_app.h"
#include "sokol_log.h"

static NxPlatformDesc g_desc;
static char g_clipboard[4096];

/* ---- queries ------------------------------------------------------------- */

static float platform_dpi(void) {
    float dpi = sapp_dpi_scale();
    return dpi > 0.0f ? dpi : 1.0f;
}

int nx_platform_width(void) {
    float dpi = platform_dpi();
    return (int)lroundf((float)sapp_width() / dpi);
}

int nx_platform_height(void) {
    float dpi = platform_dpi();
    return (int)lroundf((float)sapp_height() / dpi);
}

int nx_platform_framebuffer_width(void) { return sapp_width(); }
int nx_platform_framebuffer_height(void) { return sapp_height(); }
float nx_platform_dpi(void) { return platform_dpi(); }

void nx_platform_quit(void) { sapp_quit(); }

/* ---- clipboard ----------------------------------------------------------- */

bool nx_platform_set_clipboard(const char* text) {
    if (!text) return false;
    sapp_set_clipboard_string(text);
    return true;
}

const char* nx_platform_clipboard(void) { return g_clipboard[0] ? g_clipboard : NULL; }

/* ---- framebuffer readback ------------------------------------------------ */

bool nx_platform_read_pixels(uint8_t* rgba, int width, int height) {
    if (!rgba || width <= 0 || height <= 0) return false;
    int fb_w = sapp_width();
    int fb_h = sapp_height();
    if (width > fb_w || height > fb_h) return false;
    uint8_t* row = (uint8_t*)malloc((size_t)fb_w * 4);
    if (!row) return false;
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, rgba); /* y-up */
    for (int y = 0; y < height / 2; y++) {
        uint8_t* top = rgba + (size_t)y * (size_t)width * 4;
        uint8_t* bottom = rgba + (size_t)(height - 1 - y) * (size_t)width * 4;
        memcpy(row, top, (size_t)width * 4);
        memcpy(top, bottom, (size_t)width * 4);
        memcpy(bottom, row, (size_t)width * 4);
    }
    free(row);
    return true;
}

/* ---- event translation --------------------------------------------------- */

static NxKey map_key(sapp_keycode k) {
    /* printable keys keep their ASCII value */
    if (k >= 32 && k <= 126) return (NxKey)k;
    switch (k) {
        case SAPP_KEYCODE_ESCAPE: return NX_KEY_ESCAPE;
        case SAPP_KEYCODE_ENTER: return NX_KEY_ENTER;
        case SAPP_KEYCODE_TAB: return NX_KEY_TAB;
        case SAPP_KEYCODE_BACKSPACE: return NX_KEY_BACKSPACE;
        case SAPP_KEYCODE_INSERT: return NX_KEY_INSERT;
        case SAPP_KEYCODE_DELETE: return NX_KEY_DELETE;
        case SAPP_KEYCODE_RIGHT: return NX_KEY_RIGHT;
        case SAPP_KEYCODE_LEFT: return NX_KEY_LEFT;
        case SAPP_KEYCODE_DOWN: return NX_KEY_DOWN;
        case SAPP_KEYCODE_UP: return NX_KEY_UP;
        case SAPP_KEYCODE_PAGE_UP: return NX_KEY_PAGE_UP;
        case SAPP_KEYCODE_PAGE_DOWN: return NX_KEY_PAGE_DOWN;
        case SAPP_KEYCODE_HOME: return NX_KEY_HOME;
        case SAPP_KEYCODE_END: return NX_KEY_END;
        case SAPP_KEYCODE_CAPS_LOCK: return NX_KEY_CAPS_LOCK;
        case SAPP_KEYCODE_SCROLL_LOCK: return NX_KEY_SCROLL_LOCK;
        case SAPP_KEYCODE_NUM_LOCK: return NX_KEY_NUM_LOCK;
        case SAPP_KEYCODE_PRINT_SCREEN: return NX_KEY_PRINT_SCREEN;
        case SAPP_KEYCODE_PAUSE: return NX_KEY_PAUSE;
        case SAPP_KEYCODE_F1: return NX_KEY_F1;
        case SAPP_KEYCODE_F2: return NX_KEY_F2;
        case SAPP_KEYCODE_F3: return NX_KEY_F3;
        case SAPP_KEYCODE_F4: return NX_KEY_F4;
        case SAPP_KEYCODE_F5: return NX_KEY_F5;
        case SAPP_KEYCODE_F6: return NX_KEY_F6;
        case SAPP_KEYCODE_F7: return NX_KEY_F7;
        case SAPP_KEYCODE_F8: return NX_KEY_F8;
        case SAPP_KEYCODE_F9: return NX_KEY_F9;
        case SAPP_KEYCODE_F10: return NX_KEY_F10;
        case SAPP_KEYCODE_F11: return NX_KEY_F11;
        case SAPP_KEYCODE_F12: return NX_KEY_F12;
        case SAPP_KEYCODE_LEFT_SHIFT: return NX_KEY_LEFT_SHIFT;
        case SAPP_KEYCODE_LEFT_CONTROL: return NX_KEY_LEFT_CONTROL;
        case SAPP_KEYCODE_LEFT_ALT: return NX_KEY_LEFT_ALT;
        case SAPP_KEYCODE_LEFT_SUPER: return NX_KEY_LEFT_SUPER;
        case SAPP_KEYCODE_RIGHT_SHIFT: return NX_KEY_RIGHT_SHIFT;
        case SAPP_KEYCODE_RIGHT_CONTROL: return NX_KEY_RIGHT_CONTROL;
        case SAPP_KEYCODE_RIGHT_ALT: return NX_KEY_RIGHT_ALT;
        case SAPP_KEYCODE_RIGHT_SUPER: return NX_KEY_RIGHT_SUPER;
        case SAPP_KEYCODE_MENU: return NX_KEY_MENU;
        case SAPP_KEYCODE_KP_0: return (NxKey)'0';
        case SAPP_KEYCODE_KP_1: return (NxKey)'1';
        case SAPP_KEYCODE_KP_2: return (NxKey)'2';
        case SAPP_KEYCODE_KP_3: return (NxKey)'3';
        case SAPP_KEYCODE_KP_4: return (NxKey)'4';
        case SAPP_KEYCODE_KP_5: return (NxKey)'5';
        case SAPP_KEYCODE_KP_6: return (NxKey)'6';
        case SAPP_KEYCODE_KP_7: return (NxKey)'7';
        case SAPP_KEYCODE_KP_8: return (NxKey)'8';
        case SAPP_KEYCODE_KP_9: return (NxKey)'9';
        case SAPP_KEYCODE_KP_ENTER: return NX_KEY_ENTER;
        case SAPP_KEYCODE_KP_DECIMAL: return (NxKey)'.';
        case SAPP_KEYCODE_KP_DIVIDE: return (NxKey)'/';
        case SAPP_KEYCODE_KP_MULTIPLY: return (NxKey)'*';
        case SAPP_KEYCODE_KP_SUBTRACT: return (NxKey)'-';
        case SAPP_KEYCODE_KP_ADD: return (NxKey)'+';
        default: return NX_KEY_UNKNOWN;
    }
}

static void init_event(NxPlatformEvent* e, const sapp_event* ev) {
    memset(e, 0, sizeof(*e));
    e->window_width = ev->window_width;
    e->window_height = ev->window_height;
    e->framebuffer_width = ev->framebuffer_width;
    e->framebuffer_height = ev->framebuffer_height;
    e->dpi = platform_dpi();
    e->touch_id = -1;
}

static void deliver(const NxPlatformEvent* e) {
    if (g_desc.callbacks.event) g_desc.callbacks.event(e, g_desc.user);
}

static void translate_touch(const sapp_event* ev, NxPlatformEventType type) {
    float dpi = platform_dpi();
    int delivered = 0;
    for (int i = 0; i < ev->num_touches; i++) {
        const sapp_touchpoint* t = &ev->touches[i];
        if (!t->changed && ev->num_touches > 1) continue;
        NxPlatformEvent e;
        init_event(&e, ev);
        e.type = type;
        e.x = nx_platform_css_coord(t->pos_x, dpi);
        e.y = nx_platform_css_coord(t->pos_y, dpi);
        e.touch_id = (int)t->identifier;
        deliver(&e);
        delivered++;
    }
    if (!delivered && ev->num_touches > 0) {
        const sapp_touchpoint* t = &ev->touches[0];
        NxPlatformEvent e;
        init_event(&e, ev);
        e.type = type;
        e.x = nx_platform_css_coord(t->pos_x, dpi);
        e.y = nx_platform_css_coord(t->pos_y, dpi);
        e.touch_id = (int)t->identifier;
        deliver(&e);
    }
}

static void on_event(const sapp_event* ev) {
    NxPlatformEvent e;
    init_event(&e, ev);
    e.ctrl = (ev->modifiers & SAPP_MODIFIER_CTRL) != 0;
    e.shift = (ev->modifiers & SAPP_MODIFIER_SHIFT) != 0;
    e.alt = (ev->modifiers & SAPP_MODIFIER_ALT) != 0;
    e.super = (ev->modifiers & SAPP_MODIFIER_SUPER) != 0;
    e.key = NX_KEY_UNKNOWN;

    switch (ev->type) {
        case SAPP_EVENTTYPE_RESIZED:
            e.type = NX_PLATFORM_EVENT_RESIZE;
            break;
        case SAPP_EVENTTYPE_FOCUSED:
            e.type = NX_PLATFORM_EVENT_FOCUS;
            break;
        case SAPP_EVENTTYPE_UNFOCUSED:
            e.type = NX_PLATFORM_EVENT_BLUR;
            break;
        case SAPP_EVENTTYPE_RESUMED:
            e.type = NX_PLATFORM_EVENT_RESUME;
            break;
        case SAPP_EVENTTYPE_SUSPENDED:
            e.type = NX_PLATFORM_EVENT_SUSPEND;
            break;
        case SAPP_EVENTTYPE_QUIT_REQUESTED:
            e.type = NX_PLATFORM_EVENT_QUIT_REQUESTED;
            break;
        case SAPP_EVENTTYPE_MOUSE_DOWN:
            e.type = NX_PLATFORM_EVENT_POINTER_DOWN;
            e.x = nx_platform_css_coord(ev->mouse_x, e.dpi);
            e.y = nx_platform_css_coord(ev->mouse_y, e.dpi);
            break;
        case SAPP_EVENTTYPE_MOUSE_UP:
            e.type = NX_PLATFORM_EVENT_POINTER_UP;
            e.x = nx_platform_css_coord(ev->mouse_x, e.dpi);
            e.y = nx_platform_css_coord(ev->mouse_y, e.dpi);
            break;
        case SAPP_EVENTTYPE_MOUSE_MOVE:
            e.type = NX_PLATFORM_EVENT_POINTER_MOVE;
            e.x = nx_platform_css_coord(ev->mouse_x, e.dpi);
            e.y = nx_platform_css_coord(ev->mouse_y, e.dpi);
            break;
        case SAPP_EVENTTYPE_TOUCHES_BEGAN:
            translate_touch(ev, NX_PLATFORM_EVENT_TOUCH_BEGIN);
            return;
        case SAPP_EVENTTYPE_TOUCHES_MOVED:
            translate_touch(ev, NX_PLATFORM_EVENT_TOUCH_MOVE);
            return;
        case SAPP_EVENTTYPE_TOUCHES_ENDED:
        case SAPP_EVENTTYPE_TOUCHES_CANCELLED:
            translate_touch(ev, NX_PLATFORM_EVENT_TOUCH_END);
            return;
        case SAPP_EVENTTYPE_KEY_DOWN:
        case SAPP_EVENTTYPE_KEY_UP:
            e.type = ev->type == SAPP_EVENTTYPE_KEY_DOWN ? NX_PLATFORM_EVENT_KEY_DOWN
                                                         : NX_PLATFORM_EVENT_KEY_UP;
            e.key = map_key(ev->key_code);
            e.repeat = ev->key_repeat;
            break;
        case SAPP_EVENTTYPE_CHAR:
            e.type = NX_PLATFORM_EVENT_CHAR;
            e.codepoint = ev->char_code;
            e.repeat = ev->key_repeat;
            break;
        case SAPP_EVENTTYPE_CLIPBOARD_PASTED: {
            const char* text = sapp_get_clipboard_string();
            g_clipboard[0] = '\0';
            if (text) {
                strncpy(g_clipboard, text, sizeof(g_clipboard) - 1);
                g_clipboard[sizeof(g_clipboard) - 1] = '\0';
            }
            e.type = NX_PLATFORM_EVENT_CLIPBOARD_PASTE;
            break;
        }
        default:
            return; /* events the runtime does not consume yet */
    }
    deliver(&e);
}

/* ---- sokol callbacks ----------------------------------------------------- */

static void sokol_init(void) {
    if (g_desc.callbacks.init) g_desc.callbacks.init(g_desc.user);
}

static void sokol_frame(void) {
    if (g_desc.callbacks.frame) g_desc.callbacks.frame(g_desc.user);
}

static void sokol_cleanup(void) {
    if (g_desc.callbacks.cleanup) g_desc.callbacks.cleanup(g_desc.user);
}

static void sokol_event(const sapp_event* ev) { on_event(ev); }

/* ---- entry --------------------------------------------------------------- */

bool nx_platform_run(const NxPlatformDesc* desc) {
    if (!desc || desc->width <= 0 || desc->height <= 0) return false;
    g_desc = *desc;
    sapp_run(&(sapp_desc){
        .init_cb = sokol_init,
        .frame_cb = sokol_frame,
        .cleanup_cb = sokol_cleanup,
        .event_cb = sokol_event,
        .width = desc->width,
        .height = desc->height,
        .high_dpi = true,
        .depth_format = SAPP_PIXELFORMAT_NONE,
        .window_title = desc->title ? desc->title : "NativaX",
        .swap_interval = desc->vsync ? 1 : 0,
        .logger.func = slog_func,
    });
    return true;
}