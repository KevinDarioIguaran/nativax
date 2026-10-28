/*
    nativax — command line interface for the native runtime.

    Commands (all run without Flutter or Dart):
      nativax init [dir]     scaffold a project (HTML/CSS/JS + nativax.json)
      nativax dev [dir]      dev server + hot reload + incremental native rebuild
      nativax build [dir]    configure + build the native runtime (incremental)
      nativax run [dir]      build if needed, then run the app
      nativax test           run the runtime test suite (ctest)
      nativax bench [dir]    run the renderer benchmark, archive JSON results
      nativax clean          remove the native build directory
*/
#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "nativax/devserver.h"
#include "nativax/log.h"

#ifndef NATIVAX_SOURCE_DIR
#define NATIVAX_SOURCE_DIR "."
#endif

#define MAX_PATH 1400

typedef struct Project {
    char root[MAX_PATH];
    char entry[512];
    char build_dir[MAX_PATH];
    int width, height;
    int port;
} Project;

static volatile sig_atomic_t g_stop = 0;

static void on_signal(int sig) {
    (void)sig;
    g_stop = 1;
}

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

static bool file_exists(const char* path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static bool dir_exists(const char* path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static void mkdir_p(const char* path) {
    char tmp[MAX_PATH];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char* p = tmp + 1; *p; p++) {
        if (*p != '/') continue;
        *p = '\0';
        mkdir(tmp, 0755);
        *p = '/';
    }
    mkdir(tmp, 0755);
}

static char* read_text(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0 || size > 4 * 1024 * 1024) {
        fclose(f);
        return NULL;
    }
    char* buf = (char*)malloc((size_t)size + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    size_t rd = fread(buf, 1, (size_t)size, f);
    fclose(f);
    buf[rd] = '\0';
    return buf;
}

/* Minimal config reader for nativax.json (flat string/number values). */
static bool json_string(const char* json, const char* key, char* out, size_t cap) {
    char pattern[64];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    const char* p = strstr(json, pattern);
    if (!p) return false;
    p = strchr(p + strlen(pattern), ':');
    if (!p) return false;
    p++;
    while (*p == ' ' || *p == '\t') p++;
    if (*p != '"') return false;
    p++;
    size_t o = 0;
    while (*p && *p != '"' && o + 1 < cap) out[o++] = *p++;
    out[o] = '\0';
    return true;
}

static bool json_int(const char* json, const char* key, int* out) {
    char pattern[64];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    const char* p = strstr(json, pattern);
    if (!p) return false;
    p = strchr(p + strlen(pattern), ':');
    if (!p) return false;
    *out = atoi(p + 1);
    return true;
}

static void load_project(Project* p, const char* dir) {
    snprintf(p->root, sizeof(p->root), "%s", dir && *dir ? dir : ".");
    snprintf(p->entry, sizeof(p->entry), "index.html");
    snprintf(p->build_dir, sizeof(p->build_dir), "%s/build", NATIVAX_SOURCE_DIR);
    p->width = 1024;
    p->height = 768;
    p->port = 8788;

    char config_path[MAX_PATH + 32];
    snprintf(config_path, sizeof(config_path), "%s/nativax.json", p->root);
    char* cfg = read_text(config_path);
    if (!cfg) return;
    char buf[512];
    if (json_string(cfg, "entry", buf, sizeof(buf))) snprintf(p->entry, sizeof(p->entry), "%s", buf);
    json_int(cfg, "width", &p->width);
    json_int(cfg, "height", &p->height);
    json_int(cfg, "port", &p->port);
    free(cfg);
}

static char* run_capture(const char* cmd, int* status) {
    FILE* f = popen(cmd, "r");
    if (!f) {
        if (status) *status = -1;
        return NULL;
    }
    char* out = NULL;
    size_t len = 0, cap = 0;
    char line[512];
    while (fgets(line, sizeof(line), f)) {
        size_t n = strlen(line);
        if (len + n + 1 > cap) {
            cap = (cap ? cap * 2 : 4096);
            while (cap < len + n + 1) cap *= 2;
            char* grown = (char*)realloc(out, cap);
            if (!grown) break;
            out = grown;
        }
        memcpy(out + len, line, n);
        len += n;
        out[len] = '\0';
    }
    int rc = pclose(f);
    if (status) *status = WIFEXITED(rc) ? WEXITSTATUS(rc) : -1;
    return out;
}

static int build_runtime(Project* p, bool quiet) {
    char cmd[4096];
    char stamp[MAX_PATH + 32];
    snprintf(stamp, sizeof(stamp), "%s/CMakeCache.txt", p->build_dir);
    if (!file_exists(stamp) && !dir_exists(p->build_dir)) {
        mkdir_p(p->build_dir);
        snprintf(cmd, sizeof(cmd), "cmake -S \"%s\" -B \"%s\" -G Ninja%s", NATIVAX_SOURCE_DIR,
                 p->build_dir, quiet ? " > /dev/null 2>&1" : "");
        if (system(cmd) != 0) {
            fprintf(stderr, "nativax: cmake configure failed\n");
            return 1;
        }
    }
    snprintf(cmd, sizeof(cmd), "cmake --build \"%s\" -j%ld%s", p->build_dir,
             (long)sysconf(_SC_NPROCESSORS_ONLN), quiet ? " > /dev/null 2>&1" : "");
    int rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "nativax: build failed\n");
        return 1;
    }
    snprintf(stamp, sizeof(stamp), "%s/nativax-runtime", p->build_dir);
    if (!file_exists(stamp)) {
        fprintf(stderr, "nativax: runtime binary missing after build (%s)\n", stamp);
        return 1;
    }
    return 0;
}

static pid_t spawn_runtime(Project* p, const char* ws_url) {
    pid_t pid = fork();
    if (pid != 0) return pid;
    char bin[MAX_PATH + 32];
    snprintf(bin, sizeof(bin), "%s/nativax-runtime", p->build_dir);
    char size[32];
    snprintf(size, sizeof(size), "%dx%d", p->width, p->height);
    (void)size;
    char w[16], h[16];
    snprintf(w, sizeof(w), "%d", p->width);
    snprintf(h, sizeof(h), "%d", p->height);
    if (ws_url)
        execl(bin, bin, "--root", p->root, "--entry", p->entry, "--size", w, h, "--dev", ws_url,
              (char*)NULL);
    else
        execl(bin, bin, "--root", p->root, "--entry", p->entry, "--size", w, h, (char*)NULL);
    fprintf(stderr, "nativax: cannot exec %s: %s\n", bin, strerror(errno));
    _exit(127);
}

/* ---- native source change detection ------------------------------------- */

static unsigned long long hash_dir(const char* dir, unsigned long long acc, int depth) {
    if (depth > 3) return acc;
    DIR* d = opendir(dir);
    if (!d) return acc;
    struct dirent* de;
    while ((de = readdir(d)) != NULL) {
        if (de->d_name[0] == '.') continue;
        char path[MAX_PATH];
        snprintf(path, sizeof(path), "%s/%s", dir, de->d_name);
        struct stat st;
        if (stat(path, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            acc = hash_dir(path, acc, depth + 1);
            continue;
        }
        acc ^= (unsigned long long)st.st_mtime * 1099511628211ull;
        for (const char* c = de->d_name; *c; c++) acc = (acc ^ (unsigned char)*c) * 1099511628211ull;
    }
    closedir(d);
    return acc;
}

static unsigned long long native_signature(void) {
    unsigned long long h = 1469598103934665603ull;
    h = hash_dir(NATIVAX_SOURCE_DIR "/src", h, 0);
    h = hash_dir(NATIVAX_SOURCE_DIR "/include", h, 0);
    struct stat st;
    if (stat(NATIVAX_SOURCE_DIR "/CMakeLists.txt", &st) == 0)
        h ^= (unsigned long long)st.st_mtime * 31ull;
    return h;
}

/* ---- commands ------------------------------------------------------------ */

static const char* SCAFFOLD_HTML =
    "<!DOCTYPE html>\n"
    "<html>\n"
    "<head>\n"
    "  <meta charset=\"utf-8\">\n"
    "  <title>NativaX app</title>\n"
    "  <link rel=\"stylesheet\" href=\"style.css\">\n"
    "</head>\n"
    "<body>\n"
    "  <header><h1>NativaX</h1></header>\n"
    "  <main>\n"
    "    <div class=\"card\">\n"
    "      <h2 id=\"title\">Native HTML/CSS/JS</h2>\n"
    "      <p>C11 + Sokol GFX + JavaScriptCore. No Flutter, no WebView.</p>\n"
    "      <button id=\"count\">Clicked 0 times</button>\n"
    "    </div>\n"
    "  </main>\n"
    "  <footer>Edit style.css or app.js and watch it update.</footer>\n"
    "  <script src=\"app.js\"></script>\n"
    "</body>\n"
    "</html>\n";

static const char* SCAFFOLD_CSS =
    "body { margin: 0; background: #f5f5fa; color: #1a1a2e; }\n"
    "header { background: #0f3460; color: #ffffff; padding: 24px; text-align: center; }\n"
    "h1 { font-size: 32px; margin: 0; }\n"
    "main { padding: 24px; }\n"
    ".card { background: #ffffff; padding: 20px; border-width: 1px; border-color: #dddddd;\n"
    "        width: 60%; }\n"
    "h2 { color: #e94560; font-size: 22px; margin-top: 0; }\n"
    "p { font-size: 16px; line-height: 1.5; }\n"
    "#count { background: #0f3460; color: #ffffff; font-size: 16px; padding: 10px;\n"
    "         border-width: 0px; width: 220px; }\n"
    "footer { color: #888888; font-size: 13px; padding: 16px; text-align: center; }\n";

static const char* SCAFFOLD_JS =
    "var clicks = 0;\n"
    "var button = document.getElementById('count');\n"
    "var title = document.getElementById('title');\n"
    "button.addEventListener('click', function () {\n"
    "  clicks++;\n"
    "  button.textContent = 'Clicked ' + clicks + ' times';\n"
    "  title.textContent = clicks % 2 ? 'DOM updated by script' : 'Native HTML/CSS/JS';\n"
    "  button.style.backgroundColor = clicks % 2 ? '#e94560' : '#0f3460';\n"
    "});\n";

static int cmd_init(const char* dir) {
    char root[MAX_PATH];
    snprintf(root, sizeof(root), "%s", dir && *dir ? dir : ".");
    mkdir_p(root);
    struct {
        const char* name;
        const char* data;
    } files[] = {
        {"index.html", SCAFFOLD_HTML},
        {"style.css", SCAFFOLD_CSS},
        {"app.js", SCAFFOLD_JS},
        {"nativax.json",
         "{\n  \"entry\": \"index.html\",\n  \"width\": 1024,\n  \"height\": 768,\n"
         "  \"port\": 8788\n}\n"},
    };
    for (size_t i = 0; i < sizeof(files) / sizeof(files[0]); i++) {
        char path[MAX_PATH + 300];
        snprintf(path, sizeof(path), "%s/%s", root, files[i].name);
        if (file_exists(path)) {
            printf("skip (exists): %s\n", path);
            continue;
        }
        FILE* f = fopen(path, "wb");
        if (!f) {
            fprintf(stderr, "nativax: cannot write %s: %s\n", path, strerror(errno));
            return 1;
        }
        fputs(files[i].data, f);
        fclose(f);
        printf("created %s\n", path);
    }
    printf("\nnext: nativax dev %s\n", root);
    return 0;
}

static int cmd_build(Project* p) {
    printf("nativax: building runtime (%s -> %s)\n", NATIVAX_SOURCE_DIR, p->build_dir);
    return build_runtime(p, false);
}

static int cmd_run(Project* p) {
    if (build_runtime(p, true) != 0) return 1;
    char entry[MAX_PATH * 2 + 32];
    snprintf(entry, sizeof(entry), "%s/%s", p->root, p->entry);
    if (!file_exists(entry)) {
        fprintf(stderr, "nativax: entry document not found: %s\n", entry);
        return 1;
    }
    pid_t pid = spawn_runtime(p, NULL);
    if (pid < 0) return 1;
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static int cmd_test(Project* p) {
    if (build_runtime(p, true) != 0) return 1;
    char cmd[MAX_PATH + 64];
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && ctest --output-on-failure", p->build_dir);
    return system(cmd) == 0 ? 0 : 1;
}

static int cmd_bench(Project* p) {
    if (build_runtime(p, true) != 0) return 1;
    char cmd[2048];
    int status = 0;
    snprintf(cmd, sizeof(cmd), "\"%s/nativax_bench\" --w 1024 --h 768 --iters 20 --cards 6 --text 40",
             p->build_dir);
    char* out = run_capture(cmd, &status);
    if (!out) {
        fprintf(stderr, "nativax: benchmark failed to run\n");
        return 1;
    }
    printf("%s", out);
    char dir[MAX_PATH + 64];
    snprintf(dir, sizeof(dir), "%s/benchmarks/results", p->root);
    mkdir_p(dir);
    char path[MAX_PATH + 160];
    time_t t = time(NULL);
    struct tm tm_buf;
    localtime_r(&t, &tm_buf);
    char stamp[64];
    strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &tm_buf);
    snprintf(path, sizeof(path), "%s/render-%s.json", dir, stamp);
    FILE* f = fopen(path, "wb");
    if (f) {
        fputs(out, f);
        fclose(f);
        printf("\nnativax: results archived to %s\n", path);
    }
    free(out);
    return status == 0 ? 0 : 1;
}

static int cmd_clean(Project* p) {
    char cmd[MAX_PATH + 32];
    snprintf(cmd, sizeof(cmd), "rm -rf \"%s\"", p->build_dir);
    if (system(cmd) != 0) {
        fprintf(stderr, "nativax: clean failed\n");
        return 1;
    }
    printf("nativax: removed %s\n", p->build_dir);
    return 0;
}

static int cmd_dev(Project* p) {
    if (build_runtime(p, false) != 0) return 1;
    char entry[MAX_PATH * 2 + 32];
    snprintf(entry, sizeof(entry), "%s/%s", p->root, p->entry);
    if (!file_exists(entry)) {
        fprintf(stderr, "nativax: entry document not found: %s (run nativax init)\n", entry);
        return 1;
    }

    char err[256];
    NxDevServerConfig cfg;
    cfg.root = p->root;
    cfg.port = p->port;
    cfg.verbose = true;
    NxDevServer* server = nx_dev_server_start(&cfg, err, sizeof(err));
    if (!server) {
        fprintf(stderr, "nativax: dev server failed: %s\n", err);
        return 1;
    }
    int port = nx_dev_server_port(server);
    char ws_url[256];
    snprintf(ws_url, sizeof(ws_url), "ws://127.0.0.1:%d/__nativax_ws", port);
    printf("nativax dev: serving %s at http://127.0.0.1:%d\n", p->root, port);
    printf("nativax dev: hot reload channel %s (%d watchers)\n", ws_url,
           nx_dev_server_watchers(server));

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    pid_t child = spawn_runtime(p, ws_url);
    if (child < 0) {
        nx_dev_server_stop(server);
        return 1;
    }
    unsigned long long signature = native_signature();
    double last_check = now_ms();
    int exit_code = 0;
    int status = 0;

    while (!g_stop) {
        nx_dev_server_poll(server, 100);
        pid_t done = waitpid(child, &status, WNOHANG);
        if (done == child) {
            printf("\nnativax dev: app exited\n");
            exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 0;
            child = -1;
            break;
        }
        if (now_ms() - last_check > 500.0) {
            last_check = now_ms();
            unsigned long long sig = native_signature();
            if (sig != signature) {
                signature = sig;
                printf("\nnativax dev: native source changed -> incremental rebuild\n");
                if (build_runtime(p, false) == 0) {
                    printf("nativax dev: relaunching app\n");
                    if (child > 0) {
                        kill(child, SIGTERM);
                        waitpid(child, &status, 0);
                    }
                    child = spawn_runtime(p, ws_url);
                    if (child < 0) {
                        fprintf(stderr, "nativax dev: relaunch failed\n");
                        exit_code = 1;
                        break;
                    }
                } else {
                    fprintf(stderr, "nativax dev: build failed, keeping the previous process\n");
                }
            }
        }
    }
    if (child > 0) {
        kill(child, SIGTERM);
        waitpid(child, &status, 0);
    }
    long requests = nx_dev_server_requests(server);
    long reloads = nx_dev_server_reloads(server);
    nx_dev_server_stop(server);
    printf("nativax dev: stopped (%ld requests, %ld reloads)\n", requests, reloads);
    return exit_code;
}

static void usage(void) {
    fprintf(stderr,
            "nativax — native HTML/CSS/JS runtime\n\n"
            "usage: nativax <command> [dir] [options]\n\n"
            "commands:\n"
            "  init [dir]     scaffold a project (index.html, style.css, app.js, nativax.json)\n"
            "  dev [dir]      dev server + hot reload + incremental native rebuild\n"
            "  build [dir]    configure and build the native runtime\n"
            "  run [dir]      build if needed and launch the app\n"
            "  test           run the ctest suite\n"
            "  bench [dir]    run the renderer benchmark and archive results\n"
            "  clean          remove the native build directory\n"
            "  version        print the runtime root and build information\n");
}

int main(int argc, char** argv) {
    if (argc < 2) {
        usage();
        return 1;
    }
    const char* command = argv[1];
    const char* dir = argc > 2 && argv[2][0] != '-' ? argv[2] : ".";

    if (!strcmp(command, "help") || !strcmp(command, "--help")) {
        usage();
        return 0;
    }
    if (!strcmp(command, "version")) {
        printf("nativax native runtime\nsource: %s\n", NATIVAX_SOURCE_DIR);
        return 0;
    }

    Project p;
    load_project(&p, dir);

    if (!strcmp(command, "init")) return cmd_init(argc > 2 ? argv[2] : ".");
    if (!strcmp(command, "dev")) return cmd_dev(&p);
    if (!strcmp(command, "build")) return cmd_build(&p);
    if (!strcmp(command, "run")) return cmd_run(&p);
    if (!strcmp(command, "test")) return cmd_test(&p);
    if (!strcmp(command, "bench")) return cmd_bench(&p);
    if (!strcmp(command, "clean")) return cmd_clean(&p);

    usage();
    return 1;
}
