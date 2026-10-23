# Physics-Render Interpolation

Smooth motion between 60Hz physics and variable render rate.

## Problem

Physics: 60Hz fixed. Rendering: variable (display refresh). Naive approach causes stutter on frame boundary.

## Solution: Timestamp-Based Interpolation

Store two physics frames (prev + current) with timestamps. Render interpolates using timing.

```
Physics Worker              Render Worker
Write transforms            Read timing
(current→prev, new→current) Calculate alpha
Write timing                Interpolate(prev, current, alpha)
Signal frame                Render
```

### Alpha Calculation

```typescript
const timing = sharedBuffer.readFrameTiming();
const alpha = clamp((now - timing.currentTime) / timing.interval, 0, 1);
position = lerp(previous, current, alpha);
```

## SharedArrayBuffer Layout

```
Timing (Float64Array):
[CurrentTime, PreviousTime, Interval]

Transform (Float32Array) - 14 floats/entity:
[Entity0 Current(7), Entity0 Previous(7), Entity1...]
```

## Why This Works

- Alpha smoothly 0→1 between frames
- No discontinuity on new frames
- Self-correcting when physics slow

## Known Issues

### Subtle Movement Vibration

`setTimeout` jitter in physics causes timing variance.

**Root causes**:
1. setTimeout not guaranteed exact timing
2. Possible race between timing write and read
3. Camera follow compounds jitter

**Current state**: Using measured interval, consistent across environments.

### Potential Fixes

1. **Fixed timestep accumulator** - rAF + accumulator instead of setTimeout
2. **Velocity extrapolation** - Extrapolate when alpha > 1
3. **Exponential smoothing** - Dampen high-frequency jitter
4. **Separate camera smoothing** - More aggressive camera damping

## Testing

- [ ] 60Hz and 120Hz+ displays
- [ ] CPU throttling (4x slowdown)
- [ ] Production deploy
- [ ] Many physics objects (500 cubes)
- [ ] Camera follow vs stationary

## Files

| File | Purpose |
|------|---------|
| `shared/buffers/transform-buffer.ts` | SharedArrayBuffer, timing |
| `physics/physics-world.ts` | Write transforms + timing |
| `renderer/sync/transform-sync.ts` | Read, interpolate |

## References

- [Fix Your Timestep! - Glenn Fiedler](https://gafferongames.com/post/fix_your_timestep/)
- [Game Loop - Game Programming Patterns](https://gameprogrammingpatterns.com/game-loop.html)
