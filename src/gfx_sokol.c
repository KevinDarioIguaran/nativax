#include "nativax/gfx.h"

#include "nativax/log.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"

#include <stdlib.h>
#include <string.h>

typedef struct TexEntry {
    sg_image img;
    sg_view view;
    bool ready;       /* image created */
    bool white;       /* detached/missing: draw with white texture */
    uint32_t gen;     /* registry generation when created */
    long long bytes;  /* GPU bytes charged for this image */
} TexEntry;

typedef struct LayerTarget {
    sg_image img;
    sg_view view;
    int w, h;
    bool ready;
} LayerTarget;

static struct {
    sg_shader shd;
    sg_shader shd_glyph;
    sg_shader shd_ui_pm;
    sg_shader shd_glyph_pm;
    sg_shader shd_layer;
    sg_pipeline pipe_ui;
    sg_pipeline pipe_glyph;
    sg_pipeline pipe_ui_pm;
    sg_pipeline pipe_glyph_pm;
    sg_pipeline pipe_layer;
    sg_sampler sampler;
    sg_view white_view;
    sg_image white_img;
    sg_buffer vbuf, ibuf;
    size_t vbuf_size, ibuf_size;
    TexEntry* tex;
    int tex_count, tex_cap;
    uint32_t tex_gen;
    LayerTarget* layers;
    int layer_count, layer_cap;
    NxGfxStats stats;
    bool initialized;
} g;

extern uint32_t nx_tex_generation(void);
extern int nx_tex_count(void);

static const char* VS_SRC =
    "#version 330\n"
    "layout(location=0) in vec2 a_pos;\n"
    "layout(location=1) in vec2 a_uv;\n"
    "layout(location=2) in vec4 a_color;\n"
    "uniform vec2 u_screen;\n"
    "out vec2 v_uv;\n"
    "out vec4 v_color;\n"
    "void main(){\n"
    "  vec2 ndc = vec2(a_pos.x/u_screen.x*2.0-1.0, 1.0-a_pos.y/u_screen.y*2.0);\n"
    "  gl_Position = vec4(ndc, 0.0, 1.0);\n"
    "  v_uv = a_uv; v_color = a_color;\n"
    "}\n";

static const char* FS_UI =
    "#version 330\n"
    "in vec2 v_uv;\n"
    "in vec4 v_color;\n"
    "uniform sampler2D u_tex;\n"
    "out vec4 frag_color;\n"
    "void main(){ frag_color = v_color * texture(u_tex, v_uv); }\n";

static const char* FS_GLYPH =
    "#version 330\n"
    "in vec2 v_uv;\n"
    "in vec4 v_color;\n"
    "uniform sampler2D u_tex;\n"
    "out vec4 frag_color;\n"
    "void main(){\n"
    "  float cov = texture(u_tex, v_uv).r;\n"
    "  frag_color = vec4(v_color.rgb, v_color.a * cov);\n"
    "}\n";

/* Premultiplied-alpha variants used when rendering into an offscreen layer
   (and when compositing one). Source color is multiplied by alpha on output. */
static const char* FS_UI_PM =
    "#version 330\n"
    "in vec2 v_uv;\n"
    "in vec4 v_color;\n"
    "uniform sampler2D u_tex;\n"
    "out vec4 frag_color;\n"
    "void main(){\n"
    "  vec4 c = v_color * texture(u_tex, v_uv);\n"
    "  frag_color = vec4(c.rgb * c.a, c.a);\n"
    "}\n";

static const char* FS_GLYPH_PM =
    "#version 330\n"
    "in vec2 v_uv;\n"
    "in vec4 v_color;\n"
    "uniform sampler2D u_tex;\n"
    "out vec4 frag_color;\n"
    "void main(){\n"
    "  float cov = texture(u_tex, v_uv).r;\n"
    "  float a = v_color.a * cov;\n"
    "  frag_color = vec4(v_color.rgb * a, a);\n"
    "}\n";

/* Layer compositing: sample a premultiplied offscreen texture and scale by
   the layer opacity (carried in v_color.a). */
static const char* FS_LAYER =
    "#version 330\n"
    "in vec2 v_uv;\n"
    "in vec4 v_color;\n"
    "uniform sampler2D u_tex;\n"
    "out vec4 frag_color;\n"
    "void main(){\n"
    "  vec4 t = texture(u_tex, v_uv);\n"
    "  frag_color = vec4(t.rgb * v_color.a, t.a * v_color.a);\n"
    "}\n";

static sg_shader make_shader(const char* fs_src) {
    sg_shader_desc d = {
        .vertex_func = {.source = VS_SRC},
        .fragment_func = {.source = fs_src},
        .attrs =
            {
                [0] = {.glsl_name = "a_pos"},
                [1] = {.glsl_name = "a_uv"},
                [2] = {.glsl_name = "a_color"},
            },
        .uniform_blocks =
            {
                [0] = {
                    .stage = SG_SHADERSTAGE_VERTEX,
                    .size = 8,
                    .layout = SG_UNIFORMLAYOUT_NATIVE,
                    .glsl_uniforms = {{.type = SG_UNIFORMTYPE_FLOAT2, .glsl_name = "u_screen"}},
                },
            },
        .views =
            {
                [0] = {.texture = {.stage = SG_SHADERSTAGE_FRAGMENT,
                                   .image_type = SG_IMAGETYPE_2D,
                                   .sample_type = SG_IMAGESAMPLETYPE_FLOAT}},
            },
        .samplers = {[0] = {.stage = SG_SHADERSTAGE_FRAGMENT, .sampler_type = SG_SAMPLERTYPE_FILTERING}},
        .texture_sampler_pairs = {[0] = {.stage = SG_SHADERSTAGE_FRAGMENT,
                                         .view_slot = 0,
                                         .sampler_slot = 0,
                                         .glsl_name = "u_tex"}},
        .label = "nativax-ui",
    };
    return sg_make_shader(&d);
}

static sg_pipeline make_pipeline(sg_shader shd, bool alpha_only, bool premul) {
    sg_pipeline_desc d = {
        .shader = shd,
        .layout =
            {
                .attrs =
                    {
                        [0] = {.format = SG_VERTEXFORMAT_FLOAT2},
                        [1] = {.format = SG_VERTEXFORMAT_FLOAT2},
                        [2] = {.format = SG_VERTEXFORMAT_UBYTE4N},
                    },
            },
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLES,
        .index_type = SG_INDEXTYPE_UINT32,
        .depth = {.compare = SG_COMPAREFUNC_ALWAYS, .write_enabled = false},
        .colors[0] =
            {
                .blend =
                    {
                        .enabled = true,
                        .src_factor_rgb = premul ? SG_BLENDFACTOR_ONE : SG_BLENDFACTOR_SRC_ALPHA,
                        .dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                        .src_factor_alpha = SG_BLENDFACTOR_ONE,
                        .dst_factor_alpha = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    },
            },
        .label = alpha_only ? "nativax-glyph" : "nativax-ui",
    };
    return sg_make_pipeline(&d);
}

static void make_buffers(size_t vsize, size_t isize) {
    if (g.vbuf.id) sg_destroy_buffer(g.vbuf);
    if (g.ibuf.id) sg_destroy_buffer(g.ibuf);
    g.vbuf = sg_make_buffer(&(sg_buffer_desc){
        .size = vsize,
        .usage = {.vertex_buffer = true, .write_transient = true},
        .label = "nativax-vbuf",
    });
    g.ibuf = sg_make_buffer(&(sg_buffer_desc){
        .size = isize,
        .usage = {.index_buffer = true, .write_transient = true},
        .label = "nativax-ibuf",
    });
    g.vbuf_size = vsize;
    g.ibuf_size = isize;
    g.stats.buffer_recreates++;
    g.stats.buffer_bytes = (long long)vsize + (long long)isize;
}

void nx_gfx_init(void) {
    if (g.initialized) return;
    memset(&g, 0, sizeof(g));
    g.shd = make_shader(FS_UI);
    g.shd_glyph = make_shader(FS_GLYPH);
    g.shd_ui_pm = make_shader(FS_UI_PM);
    g.shd_glyph_pm = make_shader(FS_GLYPH_PM);
    g.shd_layer = make_shader(FS_LAYER);
    g.pipe_ui = make_pipeline(g.shd, false, false);
    g.pipe_glyph = make_pipeline(g.shd_glyph, true, false);
    g.pipe_ui_pm = make_pipeline(g.shd_ui_pm, false, true);
    g.pipe_glyph_pm = make_pipeline(g.shd_glyph_pm, true, true);
    g.pipe_layer = make_pipeline(g.shd_layer, false, true);
    g.sampler = sg_make_sampler(&(sg_sampler_desc){
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
        .wrap_u = SG_WRAP_CLAMP_TO_EDGE,
        .wrap_v = SG_WRAP_CLAMP_TO_EDGE,
    });
    static const uint8_t white[4] = {255, 255, 255, 255};
    sg_image img = sg_make_image(&(sg_image_desc){
        .width = 1,
        .height = 1,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .data = {.ptr = white, .size = 4},
        .label = "nativax-white",
    });
    g.white_img = img; /* tracked: views do not own their image */
    g.stats.texture_bytes += 4;
    g.white_view = sg_make_view(&(sg_view_desc){
        .texture = {.image = img},
    });
    make_buffers(1024 * 1024, 1024 * 1024);
    g.vbuf_size = 1024 * 1024;
    g.tex_gen = nx_tex_generation();
    g.initialized = true;
    NX_DEBUG("gfx init: ui+glyph+layer pipelines, 1MB/1MB buffers");
}

void nx_gfx_shutdown(void) {
    if (!g.initialized) return;
    for (int i = 0; i < g.tex_count; i++) {
        if (g.tex[i].ready) {
            sg_destroy_view(g.tex[i].view);
            sg_destroy_image(g.tex[i].img);
            g.stats.texture_bytes -= g.tex[i].bytes;
            g.tex[i].bytes = 0;
        }
    }
    free(g.tex);
    for (int i = 0; i < g.layer_count; i++) {
        if (g.layers[i].ready) {
            sg_destroy_view(g.layers[i].view);
            sg_destroy_image(g.layers[i].img);
            g.stats.layer_bytes -= (long long)g.layers[i].w * g.layers[i].h * 4;
        }
    }
    free(g.layers);
    if (g.vbuf.id) sg_destroy_buffer(g.vbuf);
    if (g.ibuf.id) sg_destroy_buffer(g.ibuf);
    sg_destroy_sampler(g.sampler);
    sg_destroy_view(g.white_view);
    if (g.white_img.id) sg_destroy_image(g.white_img); /* orphan if not destroyed */
    sg_destroy_pipeline(g.pipe_ui);
    sg_destroy_pipeline(g.pipe_glyph);
    sg_destroy_pipeline(g.pipe_ui_pm);
    sg_destroy_pipeline(g.pipe_glyph_pm);
    sg_destroy_pipeline(g.pipe_layer);
    sg_destroy_shader(g.shd);
    sg_destroy_shader(g.shd_glyph);
    sg_destroy_shader(g.shd_ui_pm);
    sg_destroy_shader(g.shd_glyph_pm);
    sg_destroy_shader(g.shd_layer);
    memset(&g, 0, sizeof(g));
}

void nx_gfx_sync_textures(void) {
    uint32_t gen = nx_tex_generation();
    if (gen != g.tex_gen) {
        for (int i = 0; i < g.tex_count; i++) {
            if (g.tex[i].ready) {
                sg_destroy_view(g.tex[i].view);
                sg_destroy_image(g.tex[i].img);
                g.stats.texture_bytes -= g.tex[i].bytes;
                g.tex[i].bytes = 0;
            }
        }
        memset(g.tex, 0, (size_t)g.tex_cap * sizeof(TexEntry));
        g.tex_count = 0;
        g.tex_gen = gen;
    }
    int n = nx_tex_count();
    if (n + 1 > g.tex_cap) {
        int new_cap = n + 17;
        g.tex = realloc(g.tex, (size_t)new_cap * sizeof(TexEntry));
        memset(g.tex + g.tex_cap, 0, (size_t)(new_cap - g.tex_cap) * sizeof(TexEntry));
        g.tex_cap = new_cap;
    }
    for (int i = 0; i < n; i++) {
        TexEntry* e = &g.tex[i + 1];             /* registry id = index + 1 */
        const NxTextureInfo* info = nx_tex_info(i + 1); /* ids are 1-based */
        if (!info || !info->pixels) {
            if (e->ready) {
                sg_destroy_view(e->view);
                sg_destroy_image(e->img);
                g.stats.texture_bytes -= e->bytes;
                e->bytes = 0;
                e->ready = false;
                e->white = true;
            }
            e->white = true;
            continue;
        }
        if (e->ready || e->white) continue;
        sg_pixel_format fmt = info->kind == NX_TEX_IMAGE ? SG_PIXELFORMAT_RGBA8 : SG_PIXELFORMAT_R8;
        e->img = sg_make_image(&(sg_image_desc){
            .width = info->width,
            .height = info->height,
            .pixel_format = fmt,
            .data = {.ptr = info->pixels,
                     .size = (size_t)info->stride * info->height},
            .label = "nativax-tex",
        });
        e->view = sg_make_view(&(sg_view_desc){.texture = {.image = e->img}});
        e->ready = true;
        e->white = false;
        e->bytes = (long long)info->width * (long long)info->height *
                   (fmt == SG_PIXELFORMAT_RGBA8 ? 4 : 1);
        g.stats.texture_bytes += e->bytes;
        g.stats.texture_uploads++;
    }
    if (g.tex_count < n + 1) g.tex_count = n + 1; /* id0=white + n entries */
}


static void ensure_layer_targets(int count, int w, int h) {
    if (count > g.layer_cap) {
        int new_cap = count + 8;
        g.layers = realloc(g.layers, (size_t)new_cap * sizeof(LayerTarget));
        memset(g.layers + g.layer_cap, 0, (size_t)(new_cap - g.layer_cap) * sizeof(LayerTarget));
        g.layer_cap = new_cap;
    }
    int max = g.layer_cap > count ? g.layer_cap : count;
    for (int i = 0; i < max; i++) {
        if (i < count) {
            LayerTarget* t = &g.layers[i];
            if (t->ready && (t->w != w || t->h != h)) {
                sg_destroy_view(t->view);
                sg_destroy_image(t->img);
                g.stats.layer_bytes -= (long long)t->w * t->h * 4;
                t->ready = false;
                t->img.id = 0;
                t->view.id = 0;
            }
            if (!t->ready) {
                t->img = sg_make_image(&(sg_image_desc){
                    .width = w,
                    .height = h,
                    .pixel_format = SG_PIXELFORMAT_RGBA8,
                    .usage = {.color_attachment = true},
                    .label = "nativax-layer",
                });
                t->view = sg_make_view(&(sg_view_desc){.color_attachment = {.image = t->img}});
                t->w = w;
                t->h = h;
                t->ready = true;
                g.stats.layer_bytes += (long long)w * h * 4;
            }
        } else {
            LayerTarget* t = &g.layers[i];
            if (t->ready) {
                sg_destroy_view(t->view);
                sg_destroy_image(t->img);
                g.stats.layer_bytes -= (long long)t->w * t->h * 4;
                t->ready = false;
                t->img.id = 0;
                t->view.id = 0;
                t->w = t->h = 0;
            }
        }
    }
    g.layer_count = count;
}

typedef struct DrawState {
    sg_pipeline pipe;
    sg_view view;
} DrawState;

static void apply_pipeline(DrawState* ds, sg_pipeline p) {
    if (p.id == ds->pipe.id) return;
    sg_apply_pipeline(p);
    ds->pipe = p;
    ds->view.id = 0;
}

static void set_uniforms(int fb_w, int fb_h) {
    struct { float w, h; } u = {(float)fb_w, (float)fb_h};
    sg_apply_uniforms(0, &(sg_range){&u, sizeof(u)});
}

static void draw_group(const NxDisplayList* dl, uint32_t gi, int fb_w, int fb_h, bool premul,
                      DrawState* ds) {
    const NxDrawGroup* grp = &dl->groups[gi];
    if (grp->index_count == 0) return;

    sg_pipeline want = grp->alpha_only
                           ? (premul ? g.pipe_glyph_pm : g.pipe_glyph)
                           : (premul ? g.pipe_ui_pm : g.pipe_ui);
    apply_pipeline(ds, want);
    set_uniforms(fb_w, fb_h);

    sg_view view = g.white_view;
    if (grp->texture > 0 && (int)grp->texture < g.tex_count && g.tex[grp->texture].ready) {
        view = g.tex[grp->texture].view;
    }
    if (view.id != ds->view.id) {
        sg_bindings b = {0};
        b.vertex_buffers[0] = g.vbuf;
        b.index_buffer = g.ibuf;
        b.views[0] = view;
        b.samplers[0] = g.sampler;
        sg_apply_bindings(&b);
        ds->view = view;
    }

    if (grp->has_scissor) {
        int sx = grp->scissor[0];
        int sy = fb_h - (grp->scissor[1] + grp->scissor[3]);
        sg_apply_scissor_rect(sx, sy, grp->scissor[2], grp->scissor[3], false);
    } else {
        sg_apply_scissor_rect(0, 0, fb_w, fb_h, false);
    }
    sg_draw((int)grp->first_index, (int)grp->index_count, 1);
    g.stats.draw_calls++;
}

static void draw_layer_quad(int li, int index_base, int fb_w, int fb_h, DrawState* ds) {
    apply_pipeline(ds, g.pipe_layer);
    set_uniforms(fb_w, fb_h);
    sg_view view = g.layers[li].view;
    if (view.id != ds->view.id) {
        sg_bindings b = {0};
        b.vertex_buffers[0] = g.vbuf;
        b.index_buffer = g.ibuf;
        b.views[0] = view;
        b.samplers[0] = g.sampler;
        sg_apply_bindings(&b);
        ds->view = view;
    }
    sg_apply_scissor_rect(0, 0, fb_w, fb_h, false);
    sg_draw(index_base + li * 6, 6, 1);
    g.stats.draw_calls++;
}

/* placeholder helper defined below via macro-like; instead compute inline */

void nx_gfx_render(const NxDisplayList* dl, int fb_w, int fb_h, const float clear_rgba[4]) {
    if (!g.initialized) return;
    if (dl->index_count == 0 && dl->layer_count == 0) {
        sg_begin_pass(&(sg_pass){
            .swapchain = sglue_swapchain(),
            .action = {.colors[0] = {.load_action = SG_LOADACTION_CLEAR,
                                     .clear_value = {clear_rgba[0], clear_rgba[1], clear_rgba[2],
                                                     clear_rgba[3]}}},
        });
        sg_end_pass();
        return;
    }

    size_t vbytes_dl = (size_t)dl->vert_count * sizeof(NxVertex);
    size_t ibytes_dl = (size_t)dl->index_count * sizeof(uint32_t);
    size_t lq_verts = (size_t)dl->layer_count * 4 * sizeof(NxVertex);
    size_t lq_indices = (size_t)dl->layer_count * 6 * sizeof(uint32_t);
    size_t vbytes = vbytes_dl + lq_verts;
    size_t ibytes = ibytes_dl + lq_indices;
    if (vbytes == 0) vbytes = sizeof(NxVertex);
    if (ibytes == 0) ibytes = sizeof(uint32_t);
    if (vbytes > g.vbuf_size || ibytes > g.ibuf_size) {
        size_t vs = g.vbuf_size ? g.vbuf_size : 1024 * 1024;
        size_t is = g.ibuf_size ? g.ibuf_size : 1024 * 1024;
        while (vs < vbytes) vs *= 2;
        while (is < ibytes) is *= 2;
        make_buffers(vs, is);
    }
    if (dl->vert_count > 0) {
        sg_write_buffer_transient(&(sg_write_buffer_desc){
            .src = {.data = {.ptr = dl->verts, .size = vbytes_dl}},
            .dst = {.buffer = g.vbuf, .offset = 0},
            .size = vbytes_dl,
        });
    }
    if (dl->index_count > 0) {
        sg_write_buffer_transient(&(sg_write_buffer_desc){
            .src = {.data = {.ptr = dl->indices, .size = ibytes_dl}},
            .dst = {.buffer = g.ibuf, .offset = 0},
            .size = ibytes_dl,
        });
    }
    if (dl->layer_count > 0) {
        NxVertex* qv = calloc((size_t)dl->layer_count * 4, sizeof(NxVertex));
        uint32_t* qi = calloc((size_t)dl->layer_count * 6, sizeof(uint32_t));
        for (uint32_t li = 0; li < dl->layer_count; li++) {
            uint32_t base = dl->vert_count + li * 4;
            uint32_t rgba = nx_rgba_pack((NxColor){1, 1, 1, dl->layers[li].opacity});
            qv[li * 4 + 0] = (NxVertex){0, 0, 0, 0, rgba};
            qv[li * 4 + 1] = (NxVertex){(float)fb_w, 0, 1, 0, rgba};
            qv[li * 4 + 2] = (NxVertex){(float)fb_w, (float)fb_h, 1, 1, rgba};
            qv[li * 4 + 3] = (NxVertex){0, (float)fb_h, 0, 1, rgba};
            qi[li * 6 + 0] = base + 0;
            qi[li * 6 + 1] = base + 1;
            qi[li * 6 + 2] = base + 2;
            qi[li * 6 + 3] = base + 0;
            qi[li * 6 + 4] = base + 2;
            qi[li * 6 + 5] = base + 3;
        }
        sg_write_buffer_transient(&(sg_write_buffer_desc){
            .src = {.data = {.ptr = qv, .size = lq_verts}},
            .dst = {.buffer = g.vbuf, .offset = vbytes_dl},
            .size = lq_verts,
        });
        sg_write_buffer_transient(&(sg_write_buffer_desc){
            .src = {.data = {.ptr = qi, .size = lq_indices}},
            .dst = {.buffer = g.ibuf, .offset = ibytes_dl},
            .size = lq_indices,
        });
        free(qv);
        free(qi);
    }

    ensure_layer_targets((int)dl->layer_count, fb_w, fb_h);

    /* ---- render offscreen layers bottom-up ---- */
    for (int li = (int)dl->layer_count - 1; li >= 0; li--) {
        sg_begin_pass(&(sg_pass){
            .attachments = {.colors[0] = g.layers[li].view},
            .action = {.colors[0] = {.load_action = SG_LOADACTION_CLEAR,
                                     .clear_value = {0, 0, 0, 0}}},
        });
        DrawState ds = {0};

        uint32_t g0 = dl->layers[li].first_group;
        uint32_t g1 = g0 + dl->layers[li].group_count;

        int child_idx[256];
        int nc = 0;
        for (uint32_t k = 0; k < dl->layer_count && nc < 256; k++) {
            if (dl->layers[k].parent == li) child_idx[nc++] = (int)k;
        }
        for (int a = 1; a < nc; a++) {
            int key = child_idx[a];
            int b = a - 1;
            while (b >= 0 && dl->layers[child_idx[b]].first_group > dl->layers[key].first_group) {
                child_idx[b + 1] = child_idx[b];
                b--;
            }
            child_idx[b + 1] = key;
        }

        uint32_t cursor = g0;
        for (int ci = 0; ci < nc; ci++) {
            int cidx = child_idx[ci];
            uint32_t clf = dl->layers[cidx].first_group;
            if (clf < cursor) clf = cursor;
            if (clf > g1) clf = g1;
            for (uint32_t g = cursor; g < clf; g++) draw_group(dl, g, fb_w, fb_h, true, &ds);
            if (clf < g1) {
                draw_layer_quad(cidx, (int)ibytes_dl, fb_w, fb_h, &ds);
            }
            cursor = dl->layers[cidx].first_group + dl->layers[cidx].group_count;
            if (cursor > g1) cursor = g1;
        }
        for (uint32_t g = cursor; g < g1; g++) draw_group(dl, g, fb_w, fb_h, true, &ds);
        sg_end_pass();
    }

    /* ---- final swapchain pass ---- */
    sg_begin_pass(&(sg_pass){
        .swapchain = sglue_swapchain(),
        .action = {.colors[0] = {.load_action = SG_LOADACTION_CLEAR,
                                 .clear_value = {clear_rgba[0], clear_rgba[1], clear_rgba[2],
                                                 clear_rgba[3]}}},
    });
    DrawState ds = {0};

    int top_children[256];
    int ntop = 0;
    for (uint32_t k = 0; k < dl->layer_count && ntop < 256; k++) {
        if (dl->layers[k].parent == -1) top_children[ntop++] = (int)k;
    }
    for (int a = 1; a < ntop; a++) {
        int key = top_children[a];
        int b = a - 1;
        while (b >= 0 && dl->layers[top_children[b]].first_group > dl->layers[key].first_group) {
            top_children[b + 1] = top_children[b];
            b--;
        }
        top_children[b + 1] = key;
    }

    uint32_t cursor = 0;
    for (int ci = 0; ci < ntop; ci++) {
        int cidx = top_children[ci];
        uint32_t clf = dl->layers[cidx].first_group;
        if (clf < cursor) clf = cursor;
        if (clf > dl->group_count) clf = dl->group_count;
        for (uint32_t g = cursor; g < clf; g++) draw_group(dl, g, fb_w, fb_h, false, &ds);
        if (clf < dl->group_count || true) {
            draw_layer_quad(cidx, (int)ibytes_dl, fb_w, fb_h, &ds);
        }
        cursor = dl->layers[cidx].first_group + dl->layers[cidx].group_count;
        if (cursor > dl->group_count) cursor = dl->group_count;
    }
    for (uint32_t g = cursor; g < dl->group_count; g++) draw_group(dl, g, fb_w, fb_h, false, &ds);
    sg_end_pass();
}

const NxGfxStats* nx_gfx_stats(void) { return &g.stats; }
void nx_gfx_reset_stats(void) { memset(&g.stats, 0, sizeof(g.stats)); }
