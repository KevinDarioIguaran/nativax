#ifndef NATIVAX_DEVSERVER_H
#define NATIVAX_DEVSERVER_H

/*
    Development server: HTTP + WebSocket + filesystem watching.

    Serves the project directory over HTTP (content types, ETag/304, no-store),
    accepts WebSocket clients on /__nativax_ws and broadcasts reload messages
    when project files change:

        {"type":"change","kind":"css|js|html|asset","path":"/style.css"}

    The server is poll-driven (no threads): the CLI/orchestrator calls
    nx_dev_server_poll() in its own loop. Linux uses inotify; on platforms
    without it the server still serves files but reports 0 watchers.
*/

#include <stdbool.h>

typedef struct NxDevServer NxDevServer;

typedef struct NxDevServerConfig {
    const char* root; /* project directory to serve and watch */
    int port;         /* 0 = ephemeral port */
    bool verbose;
} NxDevServerConfig;

/* Start listening on 127.0.0.1. Returns NULL on failure with a message in
   err (may also be truncated into err). */
NxDevServer* nx_dev_server_start(const NxDevServerConfig* cfg, char* err, int err_size);

int nx_dev_server_port(const NxDevServer* srv);

/* Serve pending HTTP requests, read WebSocket frames and drain watcher events.
   timeout_ms < 0 blocks until something happens, 0 returns immediately.
   Returns the number of handled events. */
int nx_dev_server_poll(NxDevServer* srv, int timeout_ms);

/* Broadcast a reload message to every connected WebSocket client. */
void nx_dev_server_broadcast(NxDevServer* srv, const char* kind, const char* path);

int nx_dev_server_clients(const NxDevServer* srv);
int nx_dev_server_watchers(const NxDevServer* srv);
long nx_dev_server_requests(const NxDevServer* srv);
long nx_dev_server_reloads(const NxDevServer* srv);

void nx_dev_server_stop(NxDevServer* srv);

#endif /* NATIVAX_DEVSERVER_H */
