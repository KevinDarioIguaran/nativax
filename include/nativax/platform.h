#ifndef NATIVAX_PLATFORM_H
#define NATIVAX_PLATFORM_H

/*
    Native platform layer (Phase 2).

    One small C interface for the OS window, application lifecycle, input and
    platform services. `platform_sokol.c` is the first backend: sokol_app owns
    the window and the event loop, this layer normalizes its events and hides
    backend types from the runtime entry point.

    Contract:

      - callbacks run on the main thread in this order:
        init -> frame (repeated) -> cleanup
      - pointer and touch coordinates are CSS px (framebuffer px / dpi);
        window sizes are CSS px, framebuffer sizes are physical px;
      - key events use NxKey; printable keys keep their ASCII value
        (uppercase), text input arrives separately as NX_PLATFORM_EVENT_CHAR;
      - nx_platform_run() blocks until the window closes or
        nx_platform_quit() is called;
      - a backend that cannot provide readback returns false from
        nx_platform_read_pixels(); it is a diagnostics/testing service.

    Porting: implement this header for the target. Nothing above this layer
    includes sokol_app.h or any platform SDK header.
*/

#include <stdbool.h>
#include <stdint.h>

typedef enum NxPlatformEventType {
    NX_PLATFORM_EVENT_NONE = 0,
    NX_PLATFORM_EVENT_RESIZE,
    NX_PLATFORM_EVENT_FOCUS,
    NX_PLATFORM_EVENT_BLUR,
    NX_PLATFORM_EVENT_POINTER_DOWN,
    NX_PLATFORM_EVENT_POINTER_UP,
    NX_PLATFORM_EVENT_POINTER_MOVE,
    NX_PLATFORM_EVENT_TOUCH_BEGIN,
    NX_PLATFORM_EVENT_TOUCH_MOVE,
    NX_PLATFORM_EVENT_TOUCH_END,
    NX_PLATFORM_EVENT_KEY_DOWN,
    NX_PLATFORM_EVENT_KEY_UP,
    NX_PLATFORM_EVENT_CHAR,
    NX_PLATFORM_EVENT_RESUME,
    NX_PLATFORM_EVENT_SUSPEND,
    NX_PLATFORM_EVENT_QUIT_REQUESTED,
    NX_PLATFORM_EVENT_CLIPBOARD_PASTE,
} NxPlatformEventType;

/* Printable keys keep their ASCII code (see the contract above). Special
   keys start at 256 so they never collide with ASCII. */
typedef enum NxKey {
    NX_KEY_UNKNOWN = 0,
    NX_KEY_ESCAPE = 256,
    NX_KEY_ENTER = 257,
    NX_KEY_TAB = 258,
    NX_KEY_BACKSPACE = 259,
    NX_KEY_INSERT = 260,
    NX_KEY_DELETE = 261,
    NX_KEY_RIGHT = 262,
    NX_KEY_LEFT = 263,
    NX_KEY_DOWN = 264,
    NX_KEY_UP = 265,
    NX_KEY_PAGE_UP = 266,
    NX_KEY_PAGE_DOWN = 267,
    NX_KEY_HOME = 268,
    NX_KEY_END = 269,
    NX_KEY_CAPS_LOCK = 280,
    NX_KEY_SCROLL_LOCK = 281,
    NX_KEY_NUM_LOCK = 282,
    NX_KEY_PRINT_SCREEN = 283,
    NX_KEY_PAUSE = 284,
    NX_KEY_F1 = 290,
    NX_KEY_F2 = 291,
    NX_KEY_F3 = 292,
    NX_KEY_F4 = 293,
    NX_KEY_F5 = 294,
    NX_KEY_F6 = 295,
    NX_KEY_F7 = 296,
    NX_KEY_F8 = 297,
    NX_KEY_F9 = 298,
    NX_KEY_F10 = 299,
    NX_KEY_F11 = 300,
    NX_KEY_F12 = 301,
    NX_KEY_LEFT_SHIFT = 340,
    NX_KEY_LEFT_CONTROL = 341,
    NX_KEY_LEFT_ALT = 342,
    NX_KEY_LEFT_SUPER = 343,
    NX_KEY_RIGHT_SHIFT = 344,
    NX_KEY_RIGHT_CONTROL = 345,
    NX_KEY_RIGHT_ALT = 346,
    NX_KEY_RIGHT_SUPER = 347,
    NX_KEY_MENU = 348,
} NxKey;

typedef struct NxPlatformEvent {
    NxPlatformEventType type;
    int window_width, window_height;           /* CSS px */
    int framebuffer_width, framebuffer_height; /* physical px */
    float dpi;
    float x, y;         /* pointer/touch position, CSS px */
    int touch_id;       /* touch identifier, -1 for mouse */
    NxKey key;
    uint32_t codepoint; /* NX_PLATFORM_EVENT_CHAR */
    bool repeat;
    bool ctrl, shift, alt, super;
} NxPlatformEvent;

typedef struct NxPlatformCallbacks {
    void (*init)(void* user);
    void (*frame)(void* user);
    void (*cleanup)(void* user);
    void (*event)(const NxPlatformEvent* ev, void* user);
} NxPlatformCallbacks;

typedef struct NxPlatformDesc {
    const char* title;
    int width, height; /* window size in CSS px */
    bool vsync;
    NxPlatformCallbacks callbacks;
    void* user;
} NxPlatformDesc;

/* Create the window and run the event loop. Returns false when the backend
   cannot start (no display, unsupported environment). */
bool nx_platform_run(const NxPlatformDesc* desc);

/* Ask the loop to stop after the current callback (safe from any callback). */
void nx_platform_quit(void);

int nx_platform_width(void);             /* CSS px */
int nx_platform_height(void);            /* CSS px */
int nx_platform_framebuffer_width(void); /* physical px */
int nx_platform_framebuffer_height(void);
float nx_platform_dpi(void);

/* Clipboard: write replaces the OS clipboard; the read side returns the last
   NX_PLATFORM_EVENT_CLIPBOARD_PASTE payload (NULL when none). */
bool nx_platform_set_clipboard(const char* text);
const char* nx_platform_clipboard(void);

/* Copy the current framebuffer into tightly packed RGBA8, top row first.
   Must be called on the render thread between frame begin/end. */
bool nx_platform_read_pixels(uint8_t* rgba, int width, int height);

/* ---- pure helpers (backend-independent, unit-tested) --------------------- */

/* Physical pixels -> CSS px (dpi <= 0 is treated as 1). */
float nx_platform_css_coord(float pixels, float dpi);
/* CSS px -> physical pixels, rounded to the nearest whole pixel. */
int nx_platform_physical_size(int css_px, float dpi);

#endif /* NATIVAX_PLATFORM_H */
