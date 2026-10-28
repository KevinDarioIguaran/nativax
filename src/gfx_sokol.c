#include "nativax/gfx.h"

#include "nativax/log.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"

#include <stdlib.h>
#include <string.h>

typedef struct TexEntry {
    sg_image img;
    sg_view view;
    bool ready;   /* image created */
    bool white;   /* detached/missing: draw with white texture */
    uint32_t gen; /* registry generation when created */
} TexEntry;

static struct {
    sg_shader shd;
    sg_pipeline pipe_ui;
    sg_pipeline pipe_glyph;
    sg_sampler sampler;
    sg_view white_view;
    sg_buffer vbuf, ibuf;
    size_t vbuf_size, ibuf_size;
    TexEntry* tex;
    int tex_count, tex_cap;
    uint32_t tex_gen;
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

static sg_pipeline make_pipeline(sg_shader shd, bool alpha_only) {
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
                        .src_factor_rgb = SG_BLENDFACTOR_SRC_ALPHA,
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
}

void nx_gfx_init(void) {
    if (g.initialized) return;
    memset(&g, 0, sizeof(g));
    g.shd = make_shader(FS_UI);
    sg_shader shd_glyph = make_shader(FS_GLYPH);
    g.pipe_ui = make_pipeline(g.shd, false);
    g.pipe_glyph = make_pipeline(shd_glyph, true);
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
    g.white_view = sg_make_view(&(sg_view_desc){
        .texture = {.image = img},
    });
    make_buffers(1024 * 1024, 1024 * 1024);
    g.vbuf_size = 1024 * 1024;
    g.tex_gen = nx_tex_generation();
    g.initialized = true;
    NX_DEBUG("gfx init: ui+glyph pipelines, 1MB/1MB buffers");
}

void nx_gfx_shutdown(void) {
    if (!g.initialized) return;
    for (int i = 0; i < g.tex_count; i++) {
        if (g.tex[i].ready) {
            sg_destroy_view(g.tex[i].view);
            sg_destroy_image(g.tex[i].img);
        }
    }
    free(g.tex);
    if (g.vbuf.id) sg_destroy_buffer(g.vbuf);
    if (g.ibuf.id) sg_destroy_buffer(g.ibuf);
    sg_destroy_sampler(g.sampler);
    sg_destroy_view(g.white_view);
    sg_destroy_pipeline(g.pipe_ui);
    sg_destroy_pipeline(g.pipe_glyph);
    sg_destroy_shader(g.shd);
    memset(&g, 0, sizeof(g));
}

void nx_gfx_sync_textures(void) {
    uint32_t gen = nx_tex_generation();
    if (gen != g.tex_gen) {
        for (int i = 0; i < g.tex_count; i++) {
            if (g.tex[i].ready) {
                sg_destroy_view(g.tex[i].view);
                sg_destroy_image(g.tex[i].img);
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
        TexEntry* e = &g.tex[i + 1]; /* registry id = index + 1 */
        const NxTextureInfo* info = nx_tex_info(i);
        if (!info || !info->pixels) {
            if (e->ready) {
                sg_destroy_view(e->view);
                sg_destroy_image(e->img);
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
        g.stats.texture_uploads++;
    }
    if (g.tex_count < n + 1) g.tex_count = n + 1; /* id0=white + n entries */
}

void nx_gfx_render(const NxDisplayList* dl, int fb_w, int fb_h, const float clear_rgba[4]) {
    sg_begin_pass(&(sg_pass){
        .swapchain = sglue_swapchain(),
        .action = {.colors[0] = {.load_action = SG_LOADACTION_CLEAR,
                                 .clear_value = {clear_rgba[0], clear_rgba[1], clear_rgba[2],
                                                 clear_rgba[3]}}},
    });
    if (dl->index_count == 0 || dl->group_count == 0) {
        sg_end_pass();
        return;
    }

    size_t vbytes = (size_t)dl->vert_count * sizeof(NxVertex);
    size_t ibytes = (size_t)dl->index_count * sizeof(uint32_t);
    if (vbytes > g.vbuf_size || ibytes > g.ibuf_size) {
        size_t vs = g.vbuf_size, is = g.ibuf_size;
        while (vs < vbytes) vs *= 2;
        while (is < ibytes) is *= 2;
        make_buffers(vs, is);
    }
    sg_write_buffer_transient(&(sg_write_buffer_desc){
        .src = {.data = {.ptr = dl->verts, .size = vbytes}},
        .dst = {.buffer = g.vbuf, .offset = 0},
        .size = vbytes,
    });
    sg_write_buffer_transient(&(sg_write_buffer_desc){
        .src = {.data = {.ptr = dl->indices, .size = ibytes}},
        .dst = {.buffer = g.ibuf, .offset = 0},
        .size = ibytes,
    });

    struct {
        float w, h;
    } u = {(float)fb_w, (float)fb_h};

    bool glyph_active = false;
    sg_pipeline cur = {0};
    sg_view cur_view = {0};

    for (uint32_t gi = 0; gi < dl->group_count; gi++) {
        const NxDrawGroup* grp = &dl->groups[gi];
        if (grp->index_count == 0) continue;

        sg_pipeline want = grp->alpha_only ? g.pipe_glyph : g.pipe_ui;
        if (want.id != cur.id) {
            sg_apply_pipeline(want);
            cur = want;
            glyph_active = grp->alpha_only;
            sg_apply_uniforms(0, &(sg_range){&u, sizeof(u)});
            cur_view.id = 0;
        }
        (void)glyph_active;

        sg_view view = g.white_view;
        if (grp->texture > 0 && (int)grp->texture < g.tex_count && g.tex[grp->texture].ready) {
            view = g.tex[grp->texture].view;
        }
        if (view.id != cur_view.id) {
            sg_bindings b = {0};
            b.vertex_buffers[0] = g.vbuf;
            b.index_buffer = g.ibuf;
            b.views[0] = view;
            b.samplers[0] = g.sampler;
            sg_apply_bindings(&b);
            cur_view = view;
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
    sg_end_pass();
}

const NxGfxStats* nx_gfx_stats(void) { return &g.stats; }
void nx_gfx_reset_stats(void) { memset(&g.stats, 0, sizeof(g.stats)); }
