# Phase 3 — Renderer (effects) report

Branch: `native-c-sokol`. Scope chosen as the real renderer gaps: group
opacity, transforms, border-radius and overflow clipping, across the CPU
rasterizer and the Sokol GPU renderer. No existing primitive was duplicated.

## Implemented

- `NxComputedStyle`: `opacity`, `radius[4]`, `overflow_hidden`, `transform`,
  `transform_origin[2]`; parsing in `src/style.c` for `border-radius`
  (1-4 components, longhands), `overflow`, `opacity`, `transform`
  (`translate`/`translateX`/`translateY`/`scale`/`scaleX`/`scaleY`/`rotate`/
  `matrix`, px/unitless only), `transform-origin` (px/%/keywords).
- Display list: real transform stack (`nx_dl_push_transform`/`pop`), layer
  records (`nx_dl_begin_layer`/`nx_dl_end_layer`) with forced group boundaries
  and parent links; `nx_dl_describe` reports layers.
- Paint: transform wraps background/border/text/children about
  transform-origin; border-radius passed to fill/stroke; overflow pushes a clip
  around text and children; opacity < 1 wraps the subtree in a layer.
- CPU rasterizer: recursive range renderer composites child layers into
  offscreen buffers and blends them as a unit (group opacity, not per-primitive).
- GPU renderer: bottom-up offscreen RGBA8 passes into layer textures with
  premultiplied pipelines; final pass composites layer quads with a layer shader
  and opacity carried in vertex color. New `layer_bytes` stat.
- Hit testing (`src/app.c`) inverts the box transform and honours
  `overflow: hidden`.

## Tests

- `unit_render`: transform stack, layer records/nesting, group-opacity compositing
  (right half red at 50%, not blended with blue), rounded corners.
- `unit_layout`: style parsing + paint layer emission.
- `unit_app`: transformed hit testing and overflow clipping.
- `gpu_window_screenshot`, `gpu_effects_screenshot`: GPU path including layers,
  rounded corners and transform.

## Measurements

- GPU effects smoke (Xvfb, llvmpipe): screenshot 1024x768, structural check
  passes (palette, rounded badge corners, shifted moved box, group blend color).
- Layer memory: one 3.0 MB RGBA8 texture per layer at 1024x768 (documented as
  R18); no layer textures retained after teardown in the headless path.

## Known limitations

- Percentage translate and elliptical border radii are intentionally unsupported.
- Overflow clipping is axis-aligned and does not follow border-radius or
  rotations (R19).
- Deep opacity nesting allocates one full-framebuffer texture per layer.
- Per-element font selection and retained render-tree reuse remain open.
EOF
echo done