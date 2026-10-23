# WebGPU Context Exhaustion Issue

**Status**: Resolved - reverted to WebGL.

## Problem

WebGPU + OffscreenCanvas + Worker: rapid page refresh (~5x) exhausts Chrome's GPU adapter pool.

```
Failed to create WebGPU Context Provider
TypeError: Cannot read properties of null (reading 'getSupportedExtensions')
```

## Cause

Chrome limits GPU adapters after failures:

| Failures | Result |
|----------|--------|
| 2 in 2min | Page blocked |
| 3 in 2min | All pages blocked |
| 3-6 in 5min | Browser restart needed |

Page refresh terminates worker before GPU cleanup → Chrome sees as "crash".

## Resolution

Reverted to WebGL. No application-level fix exists for the race condition.

Changes:
- `three/webgpu` → `three`
- `WebGPURenderer` → `WebGLRenderer`
- Removed async `renderer.init()`
- `MeshStandardNodeMaterial` → `MeshStandardMaterial`

## Workarounds (for WebGPU)

Users: Wait 2min or restart browser.

Dev: `chrome --disable-domain-blocking-for-3d-apis`

## Future

Revisit when Chrome/Dawn improves worker termination cleanup.
