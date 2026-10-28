/*
    Development server: HTTP static serving, WebSocket hot-reload channel and
    inotify-based filesystem watching (poll-driven, no threads).
*/
#define _GNU_SOURCE

#include "nativax/devserver.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "nativax/log.h"

#define MAX_CLIENTS 16
#define MAX_WATCH 64
#define MAX_PATH_LEN 1400
#define WS_GUID "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

typedef struct Client {
    int fd;
    bool ws;
    unsigned char in[16384];
    size_t in_len;
} Client;

struct NxDevServer {
    int listen_fd;
    int port;
    int notify_fd;
    char root[1024];
    bool verbose;
    Client clients[MAX_CLIENTS];
    int client_count;
    int watch_count;
    int watch_wd[MAX_WATCH];
    char watch_dir[MAX_WATCH][768];
    long requests;
    long reloads;
    char last_kind[16];
    char last_path[1200];
    double last_broadcast_ms;
};

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

/* ---- SHA-1 (RFC 3174) + base64 for the WebSocket handshake --------------- */

typedef struct {
    uint32_t h[5];
    uint64_t total;
    unsigned char buf[64];
    size_t buflen;
} Sha1;

static uint32_t rol32(uint32_t v, int r) { return (v << r) | (v >> (32 - r)); }

static void sha1_block(Sha1* s, const unsigned char* p) {
    uint32_t w[80];
    for (int i = 0; i < 16; i++)
        w[i] = ((uint32_t)p[i * 4] << 24) | ((uint32_t)p[i * 4 + 1] << 16) |
               ((uint32_t)p[i * 4 + 2] << 8) | (uint32_t)p[i * 4 + 3];
    for (int i = 16; i < 80; i++) w[i] = rol32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    uint32_t a = s->h[0], b = s->h[1], c = s->h[2], d = s->h[3], e = s->h[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) { f = (b & c) | ((~b) & d); k = 0x5A827999u; }
        else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1u; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDCu; }
        else { f = b ^ c ^ d; k = 0xCA62C1D6u; }
        uint32_t tmp = rol32(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol32(b, 30); b = a; a = tmp;
    }
    s->h[0] += a; s->h[1] += b; s->h[2] += c; s->h[3] += d; s->h[4] += e;
}

static void sha1_init(Sha1* s) {
    s->h[0] = 0x67452301u; s->h[1] = 0xEFCDAB89u; s->h[2] = 0x98BADCFEu;
    s->h[3] = 0x10325476u; s->h[4] = 0xC3D2E1F0u;
    s->total = 0;
    s->buflen = 0;
}

static void sha1_update(Sha1* s, const void* data, size_t len) {
    const unsigned char* p = (const unsigned char*)data;
    s->total += len;
    while (len > 0) {
        size_t take = 64 - s->buflen;
        if (take > len) take = len;
        memcpy(s->buf + s->buflen, p, take);
        s->buflen += take;
        p += take;
        len -= take;
        if (s->buflen == 64) {
            sha1_block(s, s->buf);
            s->buflen = 0;
        }
    }
}

static void sha1_final(Sha1* s, unsigned char out[20]) {
    uint64_t bits = s->total * 8;
    unsigned char pad = 0x80;
    sha1_update(s, &pad, 1);
    unsigned char zero = 0;
    while (s->buflen != 56) sha1_update(s, &zero, 1);
    unsigned char len[8];
    for (int i = 0; i < 8; i++) len[i] = (unsigned char)(bits >> (56 - i * 8));
    sha1_update(s, len, 8);
    for (int i = 0; i < 5; i++) {
        out[i * 4] = (unsigned char)(s->h[i] >> 24);
        out[i * 4 + 1] = (unsigned char)(s->h[i] >> 16);
        out[i * 4 + 2] = (unsigned char)(s->h[i] >> 8);
        out[i * 4 + 3] = (unsigned char)(s->h[i]);
    }
}

static void base64_encode(const unsigned char* in, size_t len, char* out, size_t cap) {
    static const char* tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    for (size_t i = 0; i < len && o + 4 < cap; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16;
        if (i + 1 < len) v |= (uint32_t)in[i + 1] << 8;
        if (i + 2 < len) v |= in[i + 2];
        out[o++] = tbl[(v >> 18) & 63];
        out[o++] = tbl[(v >> 12) & 63];
        out[o++] = i + 1 < len ? tbl[(v >> 6) & 63] : '=';
        out[o++] = i + 2 < len ? tbl[v & 63] : '=';
    }
    out[o] = '\0';
}

static void websocket_accept_key(const char* key, char* out, size_t cap) {
    char joined[256];
    snprintf(joined, sizeof(joined), "%s%s", key, WS_GUID);
    Sha1 s;
    sha1_init(&s);
    sha1_update(&s, joined, strlen(joined));
    unsigned char digest[20];
    sha1_final(&s, digest);
    base64_encode(digest, 20, out, cap);
}

/* ---- small helpers ------------------------------------------------------- */

static const char* ext_of(const char* path) {
    const char* dot = strrchr(path, '.');
    return dot ? dot + 1 : "";
}

static const char* content_type(const char* path) {
    const char* e = ext_of(path);
    if (!strcasecmp(e, "html") || !strcasecmp(e, "htm")) return "text/html; charset=utf-8";
    if (!strcasecmp(e, "css")) return "text/css; charset=utf-8";
    if (!strcasecmp(e, "js") || !strcasecmp(e, "mjs")) return "text/javascript; charset=utf-8";
    if (!strcasecmp(e, "json")) return "application/json; charset=utf-8";
    if (!strcasecmp(e, "svg")) return "image/svg+xml";
    if (!strcasecmp(e, "png")) return "image/png";
    if (!strcasecmp(e, "jpg") || !strcasecmp(e, "jpeg")) return "image/jpeg";
    if (!strcasecmp(e, "ttf")) return "font/ttf";
    if (!strcasecmp(e, "woff2")) return "font/woff2";
    return "application/octet-stream";
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

static uint64_t fnv1a(const unsigned char* p, size_t len) {
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < len; i++) {
        h ^= p[i];
        h *= 1099511628211ull;
    }
    return h;
}

/* ---- clients ------------------------------------------------------------- */

static void close_client(NxDevServer* s, int index) {
    if (index < 0 || index >= s->client_count) return;
    close(s->clients[index].fd);
    s->clients[index] = s->clients[s->client_count - 1];
    s->client_count--;
}

static bool ws_send_frame(NxDevServer* s, Client* c, const unsigned char* payload, size_t len,
                          int opcode) {
    unsigned char head[10];
    size_t head_len = 0;
    head[0] = (unsigned char)(0x80 | (opcode & 0x0f));
    if (len < 126) {
        head[1] = (unsigned char)len;
        head_len = 2;
    } else if (len < 65536) {
        head[1] = 126;
        head[2] = (unsigned char)(len >> 8);
        head[3] = (unsigned char)(len & 0xff);
        head_len = 4;
    } else {
        head[1] = 127;
        for (int i = 0; i < 8; i++) head[2 + i] = (unsigned char)((uint64_t)len >> (56 - i * 8));
        head_len = 10;
    }
    if (!send_all(c->fd, head, head_len)) return false;
    if (len > 0 && !send_all(c->fd, payload, len)) return false;
    (void)s;
    return true;
}

static void broadcast_json(NxDevServer* s, const char* json) {
    size_t len = strlen(json);
    for (int i = s->client_count - 1; i >= 0; i--) {
        if (!s->clients[i].ws) continue;
        if (!ws_send_frame(s, &s->clients[i], (const unsigned char*)json, len, 0x1))
            close_client(s, i);
    }
}

void nx_dev_server_broadcast(NxDevServer* s, const char* kind, const char* path) {
    if (!s) return;
    char msg[1200];
    snprintf(msg, sizeof(msg), "{\"type\":\"change\",\"kind\":\"%s\",\"path\":\"%s\"}", kind,
             path ? path : "");
    broadcast_json(s, msg);
    s->reloads++;
    if (s->verbose) NX_INFO("reload broadcast: %s %s (%d client(s))", kind, path ? path : "-",
                            s->client_count);
}

/* ---- HTTP ---------------------------------------------------------------- */

static void percent_decode(const char* in, char* out, size_t cap) {
    size_t o = 0;
    for (size_t i = 0; in[i] && o + 1 < cap; i++) {
        if (in[i] == '%' && in[i + 1] && in[i + 2]) {
            char hex[3] = {in[i + 1], in[i + 2], 0};
            char* end = NULL;
            long v = strtol(hex, &end, 16);
            if (end && *end == '\0') {
                out[o++] = (char)v;
                i += 2;
                continue;
            }
        }
        out[o++] = in[i];
    }
    out[o] = '\0';
}

static const char* find_header(const char* headers, const char* name) {
    size_t name_len = strlen(name);
    const char* p = headers;
    while (p && *p) {
        const char* line_end = strstr(p, "\r\n");
        size_t line_len = line_end ? (size_t)(line_end - p) : strlen(p);
        if (line_len > name_len && p[name_len] == ':' && !strncasecmp(p, name, name_len)) {
            const char* v = p + name_len + 1;
            while (*v == ' ') v++;
            return v;
        }
        if (!line_end) break;
        p = line_end + 2;
    }
    return NULL;
}

static void send_error(int fd, int code, const char* text) {
    char body[256];
    snprintf(body, sizeof(body), "<h1>%d %s</h1>", code, text);
    char header[512];
    snprintf(header, sizeof(header),
             "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\n"
             "Content-Length: %zu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
             code, text, strlen(body));
    send_all(fd, header, strlen(header));
    send_all(fd, body, strlen(body));
}

static bool upgrade_websocket(NxDevServer* s, Client* c, const char* headers) {
    const char* key = find_header(headers, "Sec-WebSocket-Key");
    if (!key) {
        send_error(c->fd, 400, "Bad Request");
        return false;
    }
    char key_copy[128];
    size_t n = 0;
    while (key[n] && key[n] != '\r' && key[n] != '\n' && n + 1 < sizeof(key_copy)) {
        key_copy[n] = key[n];
        n++;
    }
    key_copy[n] = '\0';
    char accept[64];
    websocket_accept_key(key_copy, accept, sizeof(accept));
    char response[256];
    snprintf(response, sizeof(response),
             "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
             "Connection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n",
             accept);
    if (!send_all(c->fd, response, strlen(response))) return false;
    c->ws = true;
    if (s->verbose) NX_INFO("websocket client connected (fd %d)", c->fd);
    return true;
}

static void serve_static(NxDevServer* s, Client* c, const char* method, const char* target,
                         const char* headers) {
    char path_only[1024];
    const char* q = strchr(target, '?');
    size_t plen = q ? (size_t)(q - target) : strlen(target);
    if (plen >= sizeof(path_only)) plen = sizeof(path_only) - 1;
    memcpy(path_only, target, plen);
    path_only[plen] = '\0';

    char decoded[1024];
    percent_decode(path_only, decoded, sizeof(decoded));
    if (strstr(decoded, "..")) {
        send_error(c->fd, 403, "Forbidden");
        return;
    }
    const char* rel = decoded[0] == '/' ? decoded : "/";
    if (strcmp(rel, "/") == 0) rel = "/index.html";

    char fs_path[2200];
    snprintf(fs_path, sizeof(fs_path), "%s%s", s->root, rel);

    struct stat st;
    if (stat(fs_path, &st) != 0 || !S_ISREG(st.st_mode)) {
        send_error(c->fd, 404, "Not Found");
        return;
    }
    FILE* f = fopen(fs_path, "rb");
    if (!f) {
        send_error(c->fd, 404, "Not Found");
        return;
    }
    if (st.st_size < 0 || st.st_size > 32 * 1024 * 1024) {
        fclose(f);
        send_error(c->fd, 413, "Payload Too Large");
        return;
    }
    size_t size = (size_t)st.st_size;
    unsigned char* data = (unsigned char*)malloc(size ? size : 1);
    size_t rd = data ? fread(data, 1, size, f) : 0;
    fclose(f);
    if (!data) {
        send_error(c->fd, 500, "Internal Server Error");
        return;
    }

    char etag[32];
    snprintf(etag, sizeof(etag), "\"%016llx\"", (unsigned long long)fnv1a(data, rd));
    const char* inm = find_header(headers, "If-None-Match");
    if (inm && !strncmp(inm, etag, strlen(etag))) {
        char header[256];
        snprintf(header, sizeof(header),
                 "HTTP/1.1 304 Not Modified\r\nETag: %s\r\nCache-Control: no-store\r\n\r\n",
                 etag);
        send_all(c->fd, header, strlen(header));
        free(data);
        return;
    }

    char header[512];
    snprintf(header, sizeof(header),
             "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %zu\r\n"
             "ETag: %s\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
             content_type(fs_path), rd, etag);
    bool ok = send_all(c->fd, header, strlen(header));
    if (ok && strcmp(method, "HEAD") != 0) ok = send_all(c->fd, data, rd);
    free(data);
    if (!ok && s->verbose) NX_WARN("failed to send %s", fs_path);
}

static void handle_request(NxDevServer* s, Client* c, const char* request) {
    const char* line_end = strstr(request, "\r\n");
    size_t line_len = line_end ? (size_t)(line_end - request) : strlen(request);
    char line[1024];
    if (line_len >= sizeof(line)) line_len = sizeof(line) - 1;
    memcpy(line, request, line_len);
    line[line_len] = '\0';

    char method[16] = {0};
    char target[1024] = {0};
    if (sscanf(line, "%15s %1023s", method, target) != 2) {
        send_error(c->fd, 400, "Bad Request");
        return;
    }
    const char* headers = line_end ? line_end + 2 : "";

    const char* upgrade = find_header(headers, "Upgrade");
    bool is_ws_request = upgrade && !strncasecmp(upgrade, "websocket", 9);
    s->requests++;
    if (is_ws_request && !strncmp(target, "/__nativax_ws", 13)) {
        upgrade_websocket(s, c, headers);
        return;
    }
    serve_static(s, c, method, target, headers);
}

/* ---- watcher ------------------------------------------------------------- */

static const char* kind_for_path(const char* path) {
    const char* e = ext_of(path);
    if (!strcasecmp(e, "css")) return "css";
    if (!strcasecmp(e, "js") || !strcasecmp(e, "mjs")) return "js";
    if (!strcasecmp(e, "html") || !strcasecmp(e, "htm")) return "html";
    return "asset";
}

static void watch_dir(NxDevServer* s, const char* dir, int depth) {
    if (s->notify_fd < 0 || depth > 4 || s->watch_count >= MAX_WATCH) return;
    int wd = inotify_add_watch(s->notify_fd, dir,
                               IN_CLOSE_WRITE | IN_CREATE | IN_DELETE | IN_MOVED_TO |
                                   IN_MOVED_FROM | IN_ATTRIB);
    if (wd < 0) return;
    s->watch_wd[s->watch_count] = wd;
    snprintf(s->watch_dir[s->watch_count], sizeof(s->watch_dir[0]), "%s", dir);
    s->watch_count++;

    DIR* d = opendir(dir);
    if (!d) return;
    struct dirent* de;
    while ((de = readdir(d)) != NULL) {
        if (de->d_name[0] == '.' || !strcmp(de->d_name, "build") ||
            !strcmp(de->d_name, "build-asan"))
            continue;
        char child[MAX_PATH_LEN];
        snprintf(child, sizeof(child), "%s/%s", dir, de->d_name);
        struct stat st;
        if (stat(child, &st) == 0 && S_ISDIR(st.st_mode)) watch_dir(s, child, depth + 1);
    }
    closedir(d);
}

static const char* dir_for_wd(NxDevServer* s, int wd) {
    for (int i = 0; i < s->watch_count; i++)
        if (s->watch_wd[i] == wd) return s->watch_dir[i];
    return NULL;
}

static void drain_watcher(NxDevServer* s) {
    if (s->notify_fd < 0) return;
    char buf[8192] __attribute__((aligned(8)));
    for (;;) {
        ssize_t n = read(s->notify_fd, buf, sizeof(buf));
        if (n <= 0) break;
        for (ssize_t off = 0; off < n;) {
            struct inotify_event* ev = (struct inotify_event*)(buf + off);
            off += (ssize_t)(sizeof(struct inotify_event) + ev->len);
            const char* dir = dir_for_wd(s, ev->wd);
            if (!dir || ev->len == 0) continue;
            if ((ev->mask & IN_ISDIR) && (ev->mask & (IN_CREATE | IN_MOVED_TO))) {
                char child[MAX_PATH_LEN];
                snprintf(child, sizeof(child), "%s/%s", dir, ev->name);
                watch_dir(s, child, 1);
                continue;
            }
            if (!(ev->mask & (IN_CLOSE_WRITE | IN_CREATE | IN_MOVED_TO))) continue;

            char rel[1200];
            size_t root_len = strlen(s->root);
            const char* suffix = dir + (root_len <= strlen(dir) ? root_len : 0);
            snprintf(rel, sizeof(rel), "%s/%s", suffix, ev->name);
            const char* kind = kind_for_path(rel);

            double t = now_ms();
            if (!strcmp(kind, s->last_kind) && !strcmp(rel, s->last_path) &&
                t - s->last_broadcast_ms < 40.0)
                continue;
            snprintf(s->last_kind, sizeof(s->last_kind), "%s", kind);
            snprintf(s->last_path, sizeof(s->last_path), "%s", rel);
            s->last_broadcast_ms = t;
            nx_dev_server_broadcast(s, kind, rel);
        }
    }
}

/* ---- WebSocket reads ----------------------------------------------------- */

static bool handle_ws_frame(NxDevServer* s, Client* c, int opcode, unsigned char* payload,
                            size_t len) {
    if (opcode == 0x8) { /* close */
        ws_send_frame(s, c, NULL, 0, 0x8);
        close_client(s, (int)(c - s->clients));
        return false;
    }
    if (opcode == 0x9) { /* ping */
        ws_send_frame(s, c, payload, len, 0xA);
        return true;
    }
    if (opcode == 0x1) { /* text: client commands ("ping", "hello") */
        char msg[256];
        size_t n = len < sizeof(msg) - 1 ? len : sizeof(msg) - 1;
        memcpy(msg, payload, n);
        msg[n] = '\0';
        if (s->verbose) NX_INFO("ws message: %s", msg);
        if (!strcmp(msg, "ping")) ws_send_frame(s, c, (const unsigned char*)"pong", 4, 0x1);
    }
    return true;
}

static void read_ws(NxDevServer* s, Client* c) {
    for (;;) {
        if (c->in_len >= sizeof(c->in)) {
            close_client(s, (int)(c - s->clients));
            return;
        }
        ssize_t n = recv(c->fd, c->in + c->in_len, sizeof(c->in) - c->in_len, 0);
        if (n <= 0) {
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) break;
            close_client(s, (int)(c - s->clients));
            return;
        }
        c->in_len += (size_t)n;
    }

    for (;;) {
        if (c->in_len < 2) return;
        int opcode = c->in[0] & 0x0f;
        bool masked = (c->in[1] & 0x80) != 0;
        uint64_t len = c->in[1] & 0x7f;
        size_t pos = 2;
        if (len == 126) {
            if (c->in_len < 4) return;
            len = ((uint64_t)c->in[2] << 8) | c->in[3];
            pos = 4;
        } else if (len == 127) {
            if (c->in_len < 10) return;
            len = 0;
            for (int i = 0; i < 8; i++) len = (len << 8) | c->in[2 + i];
            pos = 10;
        }
        if (len > 1024 * 1024) {
            close_client(s, (int)(c - s->clients));
            return;
        }
        unsigned char mask[4] = {0, 0, 0, 0};
        if (masked) {
            if (c->in_len < pos + 4) return;
            memcpy(mask, c->in + pos, 4);
            pos += 4;
        }
        if (c->in_len < pos + len) return;

        unsigned char* payload = c->in + pos;
        if (masked)
            for (size_t i = 0; i < len; i++) payload[i] ^= mask[i % 4];
        if (!handle_ws_frame(s, c, opcode, payload, (size_t)len)) return;
        memmove(c->in, c->in + pos + len, c->in_len - pos - len);
        c->in_len -= pos + (size_t)len;
    }
}

/* ---- public API ---------------------------------------------------------- */

NxDevServer* nx_dev_server_start(const NxDevServerConfig* cfg, char* err, int err_size) {
    if (!cfg || !cfg->root) {
        if (err) snprintf(err, (size_t)err_size, "missing project root");
        return NULL;
    }
    NxDevServer* s = (NxDevServer*)calloc(1, sizeof(*s));
    if (!s) {
        if (err) snprintf(err, (size_t)err_size, "out of memory");
        return NULL;
    }
    snprintf(s->root, sizeof(s->root), "%s", cfg->root);
    s->port = cfg->port;
    s->verbose = cfg->verbose;
    s->listen_fd = -1;
    s->notify_fd = -1;

    s->listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (s->listen_fd < 0) {
        if (err) snprintf(err, (size_t)err_size, "socket: %s", strerror(errno));
        free(s);
        return NULL;
    }
    int one = 1;
    setsockopt(s->listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((uint16_t)cfg->port);
    if (bind(s->listen_fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        if (err) snprintf(err, (size_t)err_size, "bind: %s", strerror(errno));
        close(s->listen_fd);
        free(s);
        return NULL;
    }
    if (listen(s->listen_fd, 16) != 0) {
        if (err) snprintf(err, (size_t)err_size, "listen: %s", strerror(errno));
        close(s->listen_fd);
        free(s);
        return NULL;
    }
    socklen_t alen = sizeof(addr);
    if (getsockname(s->listen_fd, (struct sockaddr*)&addr, &alen) == 0)
        s->port = ntohs(addr.sin_port);
    fcntl(s->listen_fd, F_SETFL, fcntl(s->listen_fd, F_GETFL, 0) | O_NONBLOCK);

    s->notify_fd = inotify_init1(IN_NONBLOCK);
    if (s->notify_fd >= 0) watch_dir(s, s->root, 0);
    return s;
}

int nx_dev_server_port(const NxDevServer* s) { return s ? s->port : 0; }
int nx_dev_server_clients(const NxDevServer* s) { return s ? s->client_count : 0; }
int nx_dev_server_watchers(const NxDevServer* s) { return s ? s->watch_count : 0; }
long nx_dev_server_requests(const NxDevServer* s) { return s ? s->requests : 0; }
long nx_dev_server_reloads(const NxDevServer* s) { return s ? s->reloads : 0; }

int nx_dev_server_poll(NxDevServer* s, int timeout_ms) {
    if (!s) return 0;
    struct pollfd fds[2 + MAX_CLIENTS];
    int nfds = 0;
    fds[nfds].fd = s->listen_fd;
    fds[nfds].events = POLLIN;
    fds[nfds].revents = 0;
    nfds++;
    if (s->notify_fd >= 0) {
        fds[nfds].fd = s->notify_fd;
        fds[nfds].events = POLLIN;
        fds[nfds].revents = 0;
        nfds++;
    }
    int client_base = nfds;
    for (int i = 0; i < s->client_count; i++) {
        fds[nfds].fd = s->clients[i].fd;
        fds[nfds].events = POLLIN;
        fds[nfds].revents = 0;
        nfds++;
    }

    int rc = poll(fds, (nfds_t)nfds, timeout_ms);
    if (rc <= 0) return 0;
    int handled = 0;

    if (fds[0].revents & POLLIN) {
        for (;;) {
            int fd = accept(s->listen_fd, NULL, NULL);
            if (fd < 0) break;
            if (s->client_count >= MAX_CLIENTS) {
                close(fd);
                continue;
            }
            Client* c = &s->clients[s->client_count++];
            c->fd = fd;
            c->ws = false;
            c->in_len = 0;
            fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
            handled++;
        }
    }
    if (s->notify_fd >= 0 && nfds > 1 && (fds[1].revents & POLLIN)) {
        drain_watcher(s);
        handled++;
    }

    for (int i = s->client_count - 1; i >= 0; i--) {
        int idx = client_base + i;
        if (idx >= nfds) continue;
        if (!(fds[idx].revents & (POLLIN | POLLHUP | POLLERR))) continue;
        Client* c = &s->clients[i];
        if (c->ws) {
            read_ws(s, c);
            handled++;
            continue;
        }
        /* HTTP request: read until end of headers */
        for (;;) {
            if (c->in_len >= sizeof(c->in) - 1) break;
            ssize_t n = recv(c->fd, c->in + c->in_len, sizeof(c->in) - c->in_len - 1, 0);
            if (n <= 0) break;
            c->in_len += (size_t)n;
            c->in[c->in_len] = '\0';
            if (strstr((char*)c->in, "\r\n\r\n")) break;
            if (n == 0) break;
        }
        c->in[c->in_len] = '\0';
        if (c->in_len > 0) {
            handle_request(s, c, (char*)c->in);
            handled++;
            if (c->ws) {
                /* keep the socket for WebSocket frames */
                c->in_len = 0;
            } else {
                close_client(s, i);
            }
        }
    }
    return handled;
}

void nx_dev_server_stop(NxDevServer* s) {
    if (!s) return;
    for (int i = s->client_count - 1; i >= 0; i--) close(s->clients[i].fd);
    if (s->listen_fd >= 0) close(s->listen_fd);
    if (s->notify_fd >= 0) close(s->notify_fd);
    free(s);
}
