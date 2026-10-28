#ifndef NATIVAX_HOTRELOAD_H
#define NATIVAX_HOTRELOAD_H

/*
    Hot-reload client for the runtime: connects to the dev server's WebSocket
    endpoint, receives reload messages and reconnects automatically.

    Non-blocking after creation: call nx_hot_reload_poll() once per frame.
*/

#include <stdbool.h>

typedef struct NxHotReload NxHotReload;

/* Message callback: `json` is the raw server message, valid for the call. */
typedef void (*NxHotReloadFn)(const char* json, void* user);

NxHotReload* nx_hot_reload_connect(const char* ws_url, NxHotReloadFn cb, void* user);

/* Read pending messages and maintain the connection. Never blocks. */
void nx_hot_reload_poll(NxHotReload* hr);

bool nx_hot_reload_connected(const NxHotReload* hr);
long nx_hot_reload_messages(const NxHotReload* hr);
void nx_hot_reload_free(NxHotReload* hr);

#endif /* NATIVAX_HOTRELOAD_H */
