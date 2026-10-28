/*
    Hot-reload client: connects to the dev server, performs the RFC 6455
    handshake, parses server frames and reconnects with a short backoff.
*/
#define _GNU_SOURCE

#include "nativax/hotreload.h"

#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "nativax/log.h"

#define MAX_IN 16384

typedef enum HrState {
    HR_DISCONNECTED = 0,
    HR_HANDSHAKE,
    HR_OPEN,
} HrState;

struct NxHotReload {
    char host[128];
    int port;
    char path[256];
    int fd;
    HrState state;
    double next_attempt_ms;
    unsigned char in[MAX_IN];
    size_t in_len;
    unsigned char out[512];
    size_t out_len;
    NxHotReloadFn cb;
    void* user;
    long messages;
    long reconnects;
};

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

static bool send_all(int fd, const void* data, size_t len) {
    const char* p = (const char*)data;
    while (len > 0) {
        ssize_t n = send(fd, p, len, MSG_NOSIGNAL);
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        p += n;
        len -= (size_t)n;
    }
    return true;
}

static void parse_url(NxHotReload* hr, const char* url) {
    snprintf(hr->host, sizeof(hr->host), "127.0.0.1");
    hr->port = 8787;
    snprintf(hr->path, sizeof(hr->path), "/__nativax_ws");
    if (!url) return;
    const char* p = url;
    if (!strncmp(p, "ws://", 5)) p += 5;
    else if (!strncmp(p, "http://", 7)) p += 7;
    const char* slash = strchr(p, '/');
    char authority[128];
    size_t alen = slash ? (size_t)(slash - p) : strlen(p);
    if (alen >= sizeof(authority)) alen = sizeof(authority) - 1;
    memcpy(authority, p, alen);
    authority[alen] = '\0';
    char* colon = strchr(authority, ':');
    if (colon) {
        *colon = '\0';
        hr->port = atoi(colon + 1);
    }
    if (authority[0]) snprintf(hr->host, sizeof(hr->host), "%s", authority);
    if (slash && slash[1]) snprintf(hr->path, sizeof(hr->path), "%s", slash);
}

static void disconnect(NxHotReload* hr, const char* why) {
    if (hr->fd >= 0) close(hr->fd);
    hr->fd = -1;
    hr->state = HR_DISCONNECTED;
    hr->in_len = 0;
    hr->out_len = 0;
    hr->next_attempt_ms = now_ms() + 500.0;
    if (why && hr->reconnects == 0) NX_WARN("hot reload: %s", why);
}

static void make_key(char* out, size_t cap) {
    static const char* hex = "0123456789abcdef";
    unsigned char raw[16];
    for (int i = 0; i < 16; i++) raw[i] = (unsigned char)(rand() & 0xff);
    size_t o = 0;
    for (int i = 0; i < 16 && o + 2 < cap; i++) {
        out[o++] = hex[raw[i] >> 4];
        out[o++] = hex[raw[i] & 0xf];
    }
    out[o] = '\0';
}

static bool attempt_connect(NxHotReload* hr) {
    hr->next_attempt_ms = now_ms() + 500.0;
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", hr->port);
    struct addrinfo* res = NULL;
    if (getaddrinfo(hr->host, port_str, &hints, &res) != 0 || !res) return false;

    int fd = -1;
    for (struct addrinfo* ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
        int rc = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (rc != 0 && errno != EINPROGRESS) {
            close(fd);
            fd = -1;
            continue;
        }
        if (rc != 0) {
            fd_set wfds;
            FD_ZERO(&wfds);
            FD_SET(fd, &wfds);
            struct timeval tv = {0, 250000};
            if (select(fd + 1, NULL, &wfds, NULL, &tv) <= 0) {
                close(fd);
                fd = -1;
                continue;
            }
            int soerr = 0;
            socklen_t slen = sizeof(soerr);
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen);
            if (soerr != 0) {
                close(fd);
                fd = -1;
                continue;
            }
        }
        break;
    }
    freeaddrinfo(res);
    if (fd < 0) return false;

    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) & ~O_NONBLOCK);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    char key[40];
    make_key(key, sizeof(key));
    char request[512];
    int n = snprintf(request, sizeof(request),
                     "GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\n"
                     "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
                     "Sec-WebSocket-Version: 13\r\n\r\n",
                     hr->path, hr->host, hr->port, key);
    if (!send_all(fd, request, (size_t)n)) {
        close(fd);
        return false;
    }

    /* read the 101 response (bounded) */
    char response[1024];
    size_t got = 0;
    while (got + 1 < sizeof(response)) {
        ssize_t r = recv(fd, response + got, sizeof(response) - 1 - got, 0);
        if (r <= 0) break;
        got += (size_t)r;
        response[got] = '\0';
        if (strstr(response, "\r\n\r\n")) break;
    }
    response[got] = '\0';
    if (!strstr(response, "101")) {
        close(fd);
        return false;
    }

    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    hr->fd = fd;
    hr->state = HR_OPEN;
    hr->in_len = 0;
    hr->reconnects++;
    NX_INFO("hot reload connected: ws://%s:%d%s", hr->host, hr->port, hr->path);
    return true;
}

NxHotReload* nx_hot_reload_connect(const char* ws_url, NxHotReloadFn cb, void* user) {
    NxHotReload* hr = (NxHotReload*)calloc(1, sizeof(*hr));
    if (!hr) return NULL;
    hr->fd = -1;
    hr->state = HR_DISCONNECTED;
    hr->cb = cb;
    hr->user = user;
    parse_url(hr, ws_url);
    srand((unsigned)now_ms());
    if (!attempt_connect(hr)) NX_WARN("hot reload: dev server not reachable yet (%s:%d)",
                                      hr->host, hr->port);
    return hr;
}

static void deliver(NxHotReload* hr, const char* msg) {
    hr->messages++;
    if (hr->cb) hr->cb(msg, hr->user);
}

static bool handle_frame(NxHotReload* hr, int opcode, unsigned char* payload, size_t len) {
    if (opcode == 0x8) return false;
    if (opcode == 0x9) {
        /* pong with the same payload */
        unsigned char head[2] = {0x8A, (unsigned char)(len < 126 ? len : 0)};
        if (len < 126) {
            send_all(hr->fd, head, 2);
            if (len) send_all(hr->fd, payload, len);
        }
        return true;
    }
    if (opcode == 0x1 || opcode == 0x2) {
        char* msg = (char*)malloc(len + 1);
        if (!msg) return true;
        memcpy(msg, payload, len);
        msg[len] = '\0';
        deliver(hr, msg);
        free(msg);
    }
    return true;
}

static void read_frames(NxHotReload* hr) {
    for (;;) {
        ssize_t n = recv(hr->fd, hr->in + hr->in_len, MAX_IN - hr->in_len, 0);
        if (n == 0) {
            disconnect(hr, "dev server closed the connection");
            return;
        }
        if (n < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
                disconnect(hr, "hot reload read failed");
            break;
        }
        hr->in_len += (size_t)n;
        if (hr->in_len >= MAX_IN) break;
    }

    for (;;) {
        if (hr->in_len < 2) return;
        int opcode = hr->in[0] & 0x0f;
        uint64_t len = hr->in[1] & 0x7f;
        size_t pos = 2;
        if (len == 126) {
            if (hr->in_len < 4) return;
            len = ((uint64_t)hr->in[2] << 8) | hr->in[3];
            pos = 4;
        } else if (len == 127) {
            if (hr->in_len < 10) return;
            len = 0;
            for (int i = 0; i < 8; i++) len = (len << 8) | hr->in[2 + i];
            pos = 10;
        }
        if (len > 1024 * 1024) {
            disconnect(hr, "oversized hot reload frame");
            return;
        }
        if (hr->in_len < pos + len) return;
        if (!handle_frame(hr, opcode, hr->in + pos, (size_t)len)) {
            disconnect(hr, "dev server sent close");
            return;
        }
        memmove(hr->in, hr->in + pos + len, hr->in_len - pos - len);
        hr->in_len -= pos + (size_t)len;
    }
}

void nx_hot_reload_poll(NxHotReload* hr) {
    if (!hr) return;
    if (hr->state == HR_DISCONNECTED && now_ms() >= hr->next_attempt_ms) attempt_connect(hr);
    if (hr->state == HR_OPEN && hr->fd >= 0) read_frames(hr);
}

bool nx_hot_reload_connected(const NxHotReload* hr) {
    return hr && hr->state == HR_OPEN && hr->fd >= 0;
}
long nx_hot_reload_messages(const NxHotReload* hr) { return hr ? hr->messages : 0; }

void nx_hot_reload_free(NxHotReload* hr) {
    if (!hr) return;
    if (hr->fd >= 0) close(hr->fd);
    free(hr);
}
