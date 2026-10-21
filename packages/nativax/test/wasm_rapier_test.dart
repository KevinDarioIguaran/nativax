import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

/// Serves the real `@dimforge/rapier3d-compat` ES module (its wasm is embedded
/// as base64, exactly like the game's physics worker receives it).
class _Loader extends NativaXResourceLoader {
  _Loader(this.root, [this.files = const {}]);
  final String root;
  final Map<String, String> files;

  @override
  Future<String?> load(String url) async {
    final path = url.split('?').first;
    if (path == '/rapier.mjs') {
      final file = File('$root/@dimforge/rapier3d-compat/rapier.mjs');
      return file.existsSync() ? file.readAsStringSync() : null;
    }
    if (path == '/comlink.mjs') {
      final file = File('$root/comlink/dist/esm/comlink.mjs');
      return file.existsSync() ? file.readAsStringSync() : null;
    }
    if (path == '/assets/physics.worker.js') {
      final file = File('$root/../dist/assets/physics.worker-BFbf6DZ_.js');
      return file.existsSync() ? file.readAsStringSync() : null;
    }
    return files[path];
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    final text = await load(url);
    return text == null ? null : utf8.encode(text);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

void main() {
  final rapier =
      '${Directory.current.path}/../../examples/threejs-multiplayer-starter/node_modules';
  final available = File(
    '$rapier/@dimforge/rapier3d-compat/rapier.mjs',
  ).existsSync();
  final gameWorker = File(
    '$rapier/../dist/assets/physics.worker-BFbf6DZ_.js',
  ).existsSync();

  testWidgets(
    'Rapier 0.19.3 runs its physics world inside NativaX WebAssembly',
    skip: !available,
    (tester) async {
      final errors = <Object>[];
      NativaXRuntime? runtime;
      await tester.runAsync(() async {
        runtime = await NativaXRuntime.create(
          source: '''
<script type="module">
import RAPIER from '/rapier.mjs';
await RAPIER.init();
globalThis.result = { version: RAPIER.version(), stage: 'init' };

const world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
world.timestep = 1 / 60;

// A fixed ground cuboid whose top face is y = 0.
const groundBody = world.createRigidBody(
  RAPIER.RigidBodyDesc.fixed().setTranslation(0, -0.5, 0));
world.createCollider(RAPIER.ColliderDesc.cuboid(10, 0.5, 10), groundBody);

// A dynamic ball dropped from y = 5.
const body = world.createRigidBody(
  RAPIER.RigidBodyDesc.dynamic().setTranslation(0, 5, 0));
const collider = world.createCollider(
  RAPIER.ColliderDesc.ball(0.5).setRestitution(0).setFriction(0.8), body);

globalThis.result.stage = 'world';
for (let i = 0; i < 180; i++) world.step();

const t = body.translation();
globalThis.result = {
  version: RAPIER.version(),
  stage: 'stepped',
  x: t.x,
  y: t.y,
  z: t.z,
  sleeping: body.isSleeping(),
  mass: body.mass(),
  colliders: world.colliders.len(),
};

// A ray straight down from above the ball must hit the ball and ground.
const ray = new RAPIER.Ray({ x: 0, y: 8, z: 0 }, { x: 0, y: -1, z: 0 });
const hit = world.castRay(ray, 20, true);
globalThis.result.rayToi = hit ? hit.timeOfImpact : null;
globalThis.result.ready = true;
world.free();
</script>
''',
          config: NativaXRuntimeConfig(
            engine: const JavaScriptEngineConfig(
              memoryLimitBytes: 512 << 20,
              executionBudget: Duration(seconds: 30),
              maxJobsPerDrain: 1000000,
            ),
            resources: _Loader(rapier),
            onScriptError: errors.add,
          ),
        );
      });
      for (var i = 0; i < 20; i++) {
        await _settle(tester);
        final ready = runtime!.engine.evaluate(
          'globalThis.result && globalThis.result.ready',
        );
        if (ready == true) break;
      }
      expect(errors, isEmpty);
      final result = runtime!.engine.evaluate('globalThis.result') as Map;
      expect(result['version'], '0.19.3');
      expect(result['stage'], 'stepped');
      expect(result['colliders'], 2);
      expect(result['x'], closeTo(0, 1e-6));
      expect(result['z'], closeTo(0, 1e-6));
      expect(result['y'], inInclusiveRange(0.45, 0.6));
      expect(result['sleeping'], isTrue);
      expect(result['mass'], greaterThan(0));
      expect(result['rayToi'], isNotNull);
      expect(result['rayToi'], inInclusiveRange(4.5, 8.0));
      runtime!.dispose();
    },
  );

  testWidgets(
    'Rapier runs in a real worker thread with its own wasm runtime',
    skip: !available,
    (tester) async {
      final errors = <Object>[];
      NativaXRuntime? runtime;
      await tester.runAsync(() async {
        runtime = await NativaXRuntime.create(
          source: '''
<script type="module">
  const worker = new Worker('/physics_worker.js', { type: 'module', name: 'physics' });
  globalThis.result = null;
  worker.onmessage = (event) => { globalThis.result = event.data; worker.terminate(); };
</script>
''',
          config: NativaXRuntimeConfig(
            engine: const JavaScriptEngineConfig(
              memoryLimitBytes: 512 << 20,
              executionBudget: Duration(seconds: 30),
              maxJobsPerDrain: 1000000,
            ),
            resources: _Loader(rapier, {
              '/physics_worker.js': r'''
import RAPIER from '/rapier.mjs';
await RAPIER.init();
const world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
world.timestep = 1 / 60;
const ground = world.createRigidBody(RAPIER.RigidBodyDesc.fixed());
world.createCollider(RAPIER.ColliderDesc.cuboid(10, 0.5, 10), ground);
const ball = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(0, 4, 0));
world.createCollider(RAPIER.ColliderDesc.ball(0.5), ball);
for (let i = 0; i < 120; i++) world.step();
postMessage({ version: RAPIER.version(), y: ball.translation().y, name: self.name });
world.free();
''',
            }),
            onScriptError: errors.add,
          ),
        );
      });
      for (var i = 0; i < 300; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (runtime!.engine.evaluate('globalThis.result') != null) break;
      }
      expect(errors, isEmpty);
      final result = runtime!.engine.evaluate('globalThis.result') as Map;
      expect(result['version'], '0.19.3');
      expect(result['name'], 'physics');
      // The fixed ground is centred at y=0 with half-height 0.5, so its top is
      // y=0.5 and the ball rests at y=1.0.
      expect(result['y'], inInclusiveRange(0.95, 1.05));
      runtime!.dispose();
    },
  );

  testWidgets(
    'the real game physics worker (Comlink + SAB) updates transforms',
    skip: !available || !gameWorker,
    (tester) async {
      final errors = <Object>[];
      NativaXRuntime? runtime;
      await tester.runAsync(() async {
        runtime = await NativaXRuntime.create(
          source: r'''
<script type="module">
import * as Comlink from '/comlink.mjs';
globalThis.result = null;
try {
  const worker = new Worker('/assets/physics.worker.js', { type: 'module', name: 'physics' });
  const api = Comlink.wrap(worker);

  const control = new SharedArrayBuffer((2 + 1024) * 4);
  const transform = new SharedArrayBuffer(1024 * 14 * 4);
  const timing = new SharedArrayBuffer(3 * 8);
  const flags = new SharedArrayBuffer(1024);
  const controlView = new Int32Array(control);
  const transformView = new Float32Array(transform);

  let count = 0;
  const register = (id) => {
    Atomics.store(controlView, 2 + count, id);
    Atomics.store(controlView, 1, count + 1);
    count++;
  };
  register(1); // static ground
  register(2); // dynamic ball
  register(3); // floating player

  await api.init({ x: 0, y: -20, z: 0 }, { control, transform, timing, flags });
  await api.spawnEntity(
    { id: 1, type: 'static', transform: {
        position: { x: 0, y: -0.5, z: 0 },
        rotation: { x: 0, y: 0, z: 0, w: 1 },
        scale: { x: 1, y: 1, z: 1 } } },
    { type: 'static', colliderType: 'cuboid',
      dimensions: { x: 20, y: 1, z: 20 }, friction: 0.8, restitution: 0 });
  await api.spawnEntity(
    { id: 2, type: 'dynamic', transform: {
        position: { x: 0, y: 0.8, z: 0 },
        rotation: { x: 0, y: 0, z: 0, w: 1 },
        scale: { x: 1, y: 1, z: 1 } } },
    { type: 'dynamic', colliderType: 'ball',
      dimensions: { x: 1, y: 1, z: 1 }, radius: 0.5,
      friction: 0.8, restitution: 0 });
  const batchIds = [];
  const positions = new Float32Array(100 * 3);
  const sizes = new Float32Array(100);
  for (let i = 0; i < 100; i++) {
    const id = 10 + i;
    register(id);
    batchIds.push(id);
    positions[i * 3] = (i % 10) * 1.5 - 7;
    positions[i * 3 + 1] = 3 + (i % 5) * 0.5;
    positions[i * 3 + 2] = Math.floor(i / 10) * 1.5 - 7;
    sizes[i] = 0.3;
  }
  await api.spawnBodies(batchIds, positions, { type: 'sphere' }, sizes);
  await api.spawnFloatingPlayer(
    3,
    { position: { x: 3, y: 2, z: 3 },
      rotation: { x: 0, y: 0, z: 0, w: 1 },
      scale: { x: 1, y: 1, z: 1 } },
    { radius: 0.35, halfHeight: 0.25,
      floatingDistance: 0.3, rayLength: 0.8,
      springStrength: 1.2, springDamping: 0.08,
      moveForce: 30, sprintMultiplier: 1.8, airControlMultiplier: 0.3,
      maxVelocity: 8, sprintMaxVelocity: 14,
      jumpForce: 12, coyoteTime: 150, jumpBufferTime: 100,
      groundedThreshold: 0.05, slopeLimit: 50,
      mass: 1, friction: 0, linearDamping: 0.5, angularDamping: 1 });

  await api.start();
  await new Promise((resolve) => setTimeout(resolve, 1200));
  const frames = Atomics.load(controlView, 0);
  const ballY = transformView[1 * 14 + 1];
  const groundY = transformView[0 * 14 + 1];
  const playerY = transformView[2 * 14 + 1];
  const grounded = (new Uint8Array(flags)[2] & 1) === 1;
  await api.dispose();
  worker.terminate();
  globalThis.result = {
    frames, ballY, groundY, playerY, grounded,
    entities: Atomics.load(controlView, 1),
    timing: new Float64Array(timing)[2],
  };
} catch (e) {
  globalThis.result = { error: String(e && e.stack || e) };
}
</script>
''',
          config: NativaXRuntimeConfig(
            engine: const JavaScriptEngineConfig(
              memoryLimitBytes: 512 << 20,
              executionBudget: Duration(seconds: 30),
              maxJobsPerDrain: 1000000,
            ),
            resources: _Loader(rapier),
            onScriptError: errors.add,
          ),
        );
      });
      for (var i = 0; i < 240; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (runtime!.engine.evaluate('globalThis.result') != null) break;
      }
      expect(errors, isEmpty);
      final result = runtime!.engine.evaluate('globalThis.result') as Map;
      expect(result['error'], isNull, reason: '${result['error']}');
      // 103 bodies over 1.2 s. The CI-safe floor is deliberately low; the
      // local measurement is ~50-57 frames (~45 Hz) with the interpreter.
      expect(result['frames'], greaterThan(20));
      expect(result['entities'], 103);
      expect(result['groundY'], closeTo(-0.5, 1e-4));
      expect(result['ballY'], inInclusiveRange(0.45, 0.55));
      expect(result['playerY'], inInclusiveRange(0.0, 0.5));
      expect(result['grounded'], isTrue);
      expect(result['timing'], closeTo(1000 / 60, 1e-6));
      runtime!.dispose();
    },
  );
}
