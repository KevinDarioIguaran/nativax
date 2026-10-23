/**
 * Application configuration constants
 *
 * Centralized config for renderer, physics, and shared systems.
 * Keep this file free of DOM or Three.js dependencies.
 */

export const config = {
  // Renderer
  renderer: {
    clearColor: "#ffffff",
    toneMapping: "cineon" as const,
    toneMappingExposure: 1.75,
    maxPixelRatio: 2,
  },

  // Camera
  camera: {
    fov: 35,
    near: 0.1,
    far: 500, // Increased for larger terrain (beyond fog)

    // Follow camera settings
    follow: {
      distance: 10,
      height: 4,
      lookAtHeight: 1.5,
      damping: 0.1,
    },
  },

  // Fog
  fog: {
    enabled: true,
    color: "#ffffff",
    near: 10, // Pushed further for larger terrain
    far: 60, // Less foggy, see further
  },

  // Sun light (directional light with shadows)
  sunLight: {
    color: "#ffffff",
    intensity: 4,
    // Offset from follow target (maintains consistent shadow direction)
    offset: { x: 20, y: 4, z: -15 },
    // Shadow settings
    shadow: {
      enabled: true,
      mapSize: 4096, // High resolution shadow map
      cameraSize: 25, // Half-size of shadow coverage (smaller = sharper shadows)
      normalBias: 0.05,
      near: 0.1,
      far: 200, // Increased for larger terrain
    },
  },

  // Environment map
  environmentMap: {
    intensity: 0.4,
  },

  // Physics
  physics: {
    gravity: { x: 0, y: -20, z: 0 },
    interval: 1000 / 60, // 16.667ms for 60Hz
    density: 1.0, // Default density for spawned bodies (mass = density × volume)
  },

  // Player movement
  player: {
    moveSpeed: 3,
    sprintMultiplier: 2,
    turnSpeed: 3,
  },

  // Floating capsule controller (dynamic rigidbody with spring-damper hover)
  // Inspired by Toyful Games' Very Very Valet and pmndrs/ecctrl
  floatingCapsule: {
    // Capsule dimensions
    radius: 0.35,
    halfHeight: 0.25,

    // Floating spring-damper system
    floatingDistance: 0.3, // Target hover distance from ground
    rayLength: 0.8, // Ground detection ray length
    springStrength: 1.2, // Spring constant (higher = snappier)
    springDamping: 0.08, // Damping coefficient (higher = less bouncy)

    // Movement forces
    moveForce: 30, // Base movement force
    sprintMultiplier: 1.8, // Sprint force multiplier
    airControlMultiplier: 0.3, // Air control reduction
    maxVelocity: 8, // Maximum horizontal velocity (walking)
    sprintMaxVelocity: 14, // Maximum horizontal velocity (sprinting)

    // Jump
    jumpForce: 12, // Impulse force for jump
    coyoteTime: 150, // ms grace period after leaving ground
    jumpBufferTime: 100, // ms to buffer jump input before landing

    // Ground detection
    groundedThreshold: 0.05, // Additional threshold for grounded state
    slopeLimit: 50, // Max slope angle in degrees

    // Physics properties
    mass: 1,
    friction: 0.0, // Low friction for smooth sliding
    linearDamping: 0.5, // Air resistance
    angularDamping: 1.0, // Prevent spinning
  },

  // Terrain configuration
  terrain: {
    size: 500, // World units (X and Z) - 10x scale
    segments: 256, // Grid resolution (256x256 = 65,536 vertices)
    noiseScale: 0.01, // Frequency scaled down 10x for same hill density
    amplitude: 15, // Taller hills for larger scale
    octaves: 5, // Detail layers
    persistence: 0.45, // Amplitude falloff per octave
    seed: 42, // Deterministic seed for reproducible terrain
  },

  // Entity limits
  entities: {
    maxCount: 1000,
  },

  // Entity spawner (click-to-spawn)
  spawner: {
    // Spawn position offset from camera
    spawnOffset: 4, // meters in front of camera

    // Projectile speed
    projectileSpeed: 40, // m/s

    // Size limits
    minSize: 0.3, // Minimum size (smaller falls through terrain)
    maxSize: 3.0, // Maximum size

    // Default values
    defaultSize: 1.0,
  },

  // Buffer configuration
  buffers: {
    maxEntities: 1024, // Increased for instanced mesh stress testing
    floatsPerEntity: 14, // current (7) + previous (7)
    controlHeaderSize: 2, // frameCounter, entityCount
  },

  // Animation settings
  animations: {
    crossFadeDuration: 0.5,
    speeds: {
      idle: 1.0,
      walking: 1.0,
      running: 1.5, // Faster animation for running
      jumping: 0.7, // Moderate run animation for airborne
    },
  },

  // Resource loading
  resources: {
    loadTimeout: 30000,
  },

  // Debug visualization
  debug: {
    colliderColor: 0x00ff00,
    colliderOpacity: 0.5,
  },

  // Audio system
  audio: {
    master: {
      volume: 1.0,
    },
    footsteps: {
      volume: 0.4,
      walkInterval: 400, // ms between footsteps when walking
      runInterval: 250, // ms between footsteps when running
      poolSize: 4, // Number of audio sources for overlapping sounds
    },
    collisions: {
      volume: 0.4, // Reduced from 0.8 - impacts were too loud
      minImpulse: 4.0, // Increased from 2.0 - filters gentle rolling/bouncing
      poolSize: 8,
    },
    player: {
      jumpVolume: 0.5,
      landVolume: 0.6,
      landIntensityThreshold: 2.0, // Fall speed for max volume landing
    },
    spatial: {
      refDistance: 5, // Distance at which volume is full
      maxDistance: 50, // Distance beyond which sound is inaudible
      rolloffFactor: 1,
    },
  },
} as const;

export type Config = typeof config;
