/*
    Dev server tests: HTTP static serving (200/304/404), the WebSocket
    handshake (RFC 6455 accept key), broadcast delivery and inotify-driven
    reload messages. Everything runs on loopback against a temporary copy of
    the example app, with no external dependencies.
*/
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include "nativax/devserver.h"

static int g_checks = 0;
static int g_failures = 0;

#define CHECK(cond, ...)                                \
    do {                                                \
        g_checks++;                                     \
        if (!(cond)) {                                  \
            g_failures++;                               \
            printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            printf(__VA_ARGS__);                        \
            printf("\n");                               \
        }                                               \
    } while (0)

static int dial(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((uint16_t)port);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static bool send_str(int fd, const char* s) {
    size_t len = strlen(s), sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, s + sent, len - sent, 0);
        if (n <= 0) return false;
        sent += (size_t)n;
    }
    return true;
}

static bool readable(int fd, int timeout_ms) {
    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);
    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    return select(fd + 1, &rfds, NULL, NULL, &tv) > 0;
}

/* Pump the single-threaded server while waiting for bytes from a client. */
static int pump_read(NxDevServer* srv, int fd, char* buf, size_t cap, const char* needle,
                     int rounds) {
    size_t got = 0;
    buf[0] = '\0';
    for (int i = 0; i < rounds; i++) {
        nx_dev_server_poll(srv, 20);
        if (!readable(fd, 20)) continue;
        ssize_t n = recv(fd, buf + got, cap - 1 - got, 0);
        if (n <= 0) break;
        got += (size_t)n;
        buf[got] = '\0';
        if (!needle || strstr(buf, needle)) break;
    }
    return (int)got;
}

static void sleep_ms(int ms) { usleep((useconds_t)ms * 1000); }

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof(tmp), "/tmp/nativax-devtest-%d", (int)getpid());
    char cmd[1600];
    snprintf(cmd, sizeof(cmd), "rm -rf %s && cp -r %s/examples/counter %s", tmp,
             NATIVAX_SOURCE_DIR, tmp);
    if (system(cmd) != 0) {
        printf("FAIL could not stage example app\n");
        return 1;
    }

    char err[256] = {0};
    NxDevServerConfig cfg;
    cfg.root = tmp;
    cfg.port = 0;
    cfg.verbose = false;
    NxDevServer* srv = nx_dev_server_start(&cfg, err, sizeof(err));
    CHECK(srv != NULL, "dev server started: %s", err);
    if (!srv) return 1;
    int port = nx_dev_server_port(srv);
    CHECK(port > 0, "ephemeral port assigned (%d)", port);
    CHECK(nx_dev_server_watchers(srv) > 0, "watchers installed (%d)",
          nx_dev_server_watchers(srv));

    /* ---- HTTP 200 ------------------------------------------------------- */
    char response[8192];
    int fd = dial(port);
    CHECK(fd >= 0, "http connect");
    send_str(fd, "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
    int n = pump_read(srv, fd, response, sizeof(response), "\r\n\r\n", 50);
    CHECK(n > 0 && strstr(response, "200 OK"), "GET / -> 200: %.40s", response);
    CHECK(strstr(response, "<!DOCTYPE html>") != NULL, "served index.html body");

    /* content type + etag */
    CHECK(strstr(response, "text/html") != NULL, "html content type");
    char etag[64] = {0};
    char* e = strstr(response, "ETag: ");
    if (e) {
        e += 6;
        size_t i = 0;
        while (e[i] && e[i] != '\r' && i + 1 < sizeof(etag)) {
            etag[i] = e[i];
            i++;
        }
        etag[i] = '\0';
    }
    CHECK(etag[0] != '\0', "ETag present: %s", etag);
    close(fd);

    /* ---- conditional GET -> 304 ---------------------------------------- */
    fd = dial(port);
    char req[512];
    snprintf(req, sizeof(req),
             "GET /index.html HTTP/1.1\r\nHost: localhost\r\nIf-None-Match: %s\r\n\r\n", etag);
    send_str(fd, req);
    n = pump_read(srv, fd, response, sizeof(response), "\r\n\r\n", 50);
    CHECK(n > 0 && strstr(response, "304 Not Modified"), "If-None-Match -> 304: %.40s", response);
    close(fd);

    /* ---- 404 ------------------------------------------------------------ */
    fd = dial(port);
    send_str(fd, "GET /does-not-exist.html HTTP/1.1\r\nHost: localhost\r\n\r\n");
    n = pump_read(srv, fd, response, sizeof(response), "\r\n\r\n", 50);
    CHECK(n > 0 && strstr(response, "404 Not Found"), "missing file -> 404: %.40s", response);
    close(fd);

    /* ---- WebSocket handshake (RFC 6455 example key) --------------------- */
    int ws = dial(port);
    CHECK(ws >= 0, "ws connect");
    send_str(ws,
             "GET /__nativax_ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
             "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
             "Sec-WebSocket-Version: 13\r\n\r\n");
    n = pump_read(srv, ws, response, sizeof(response), "\r\n\r\n", 50);
    CHECK(n > 0 && strstr(response, "101 Switching Protocols"), "ws upgrade -> 101: %.40s",
          response);
    CHECK(strstr(response, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=") != NULL,
          "ws accept key matches RFC 6455 example");
    CHECK(nx_dev_server_clients(srv) == 1, "one ws client tracked");

    /* ---- explicit broadcast is delivered as a text frame --------------- */
    nx_dev_server_broadcast(srv, "css", "/style.css");
    pump_read(srv, ws, response, sizeof(response), "css", 20);
    CHECK(strstr(response, "{\"type\":\"change\"") != NULL, "broadcast frame received: %.60s",
          response);
    CHECK(strstr(response, "\"kind\":\"css\"") != NULL, "broadcast carries the css kind");

    /* ---- watcher: editing a file produces a reload message -------------- */
    char css_path[512];
    snprintf(css_path, sizeof(css_path), "%s/style.css", tmp);
    FILE* f = fopen(css_path, "ab");
    if (f) {
        fputs("\nfooter { color: #333333; }\n", f);
        fclose(f);
    }
    bool saw_change = false;
    for (int i = 0; i < 60 && !saw_change; i++) {
        sleep_ms(40);
        nx_dev_server_poll(srv, 0);
        if (!readable(ws, 10)) continue;
        ssize_t r = recv(ws, response, sizeof(response) - 1, 0);
        if (r <= 0) continue;
        response[r] = '\0';
        if (strstr(response, "\"kind\":\"css\"") && strstr(response, "style.css"))
            saw_change = true;
    }
    CHECK(saw_change, "inotify change broadcast for style.css");
    CHECK(nx_dev_server_reloads(srv) >= 2, "reload counter advanced (%ld)",
          nx_dev_server_reloads(srv));
    CHECK(nx_dev_server_requests(srv) >= 3, "requests counted (%ld)",
          nx_dev_server_requests(srv));

    close(ws);
    nx_dev_server_stop(srv);

    snprintf(cmd, sizeof(cmd), "rm -rf %s", tmp);
    if (system(cmd) != 0) printf("note: could not remove %s\n", tmp);

    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
