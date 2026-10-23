import * as THREE from "three";
import { SoundPool } from "../../audio";
import { config } from "~/shared/config";
import type {
  FootstepEvent,
  CollisionEvent,
  JumpEvent,
  LandEvent,
  ListenerUpdate,
} from "~/shared/types";

/**
 * AudioManager - Main thread audio orchestrator
 *
 * Manages Web Audio API on the main thread (AudioContext cannot run in workers).
 * Receives audio events from physics and render workers via Comlink callbacks.
 *
 * Uses Three.js Audio system for 3D spatial audio with the following pools:
 * - Footsteps: Player movement sounds
 * - Impacts: Collision sounds
 * - Player: Jump/land sounds
 */
export default class AudioManager {
  private context: AudioContext | null = null;
  private listener: THREE.AudioListener;
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;

  // Sound pools
  private footstepPool: SoundPool | null = null;
  private impactPool: SoundPool | null = null;
  private jumpSound: THREE.Audio | null = null;
  private landSound: THREE.Audio | null = null;

  // Audio buffers
  private buffers: Map<string, AudioBuffer[]> = new Map();

  // State
  private isInitialized = false;
  private isResumed = false;

  // Pre-allocated vector for lookAt calculations (avoid allocation in hot path)
  private tempLookAt = new THREE.Vector3();

  constructor() {
    // Create virtual scene for audio positioning
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera();
    this.listener = new THREE.AudioListener();
    this.camera.add(this.listener);
    this.scene.add(this.camera);
  }

  /**
   * Initialize audio system
   * Must be called after user interaction due to browser autoplay policy
   * @param onProgress - Optional callback for loading progress (0-1)
   */
  async init(onProgress?: (progress: number) => void): Promise<void> {
    if (this.isInitialized) return;

    // Get the AudioContext from the listener (created lazily)
    this.context = this.listener.context;

    // Create sound pools
    const spatialConfig = config.audio.spatial;

    this.footstepPool = new SoundPool(this.listener, this.scene, {
      poolSize: config.audio.footsteps.poolSize,
      volume: config.audio.footsteps.volume,
      refDistance: spatialConfig.refDistance,
      maxDistance: spatialConfig.maxDistance,
      rolloffFactor: spatialConfig.rolloffFactor,
    });

    this.impactPool = new SoundPool(this.listener, this.scene, {
      poolSize: config.audio.collisions.poolSize,
      volume: config.audio.collisions.volume,
      refDistance: spatialConfig.refDistance,
      maxDistance: spatialConfig.maxDistance,
      rolloffFactor: spatialConfig.rolloffFactor,
    });

    // Create non-positional sounds for player
    this.jumpSound = new THREE.Audio(this.listener);
    this.jumpSound.setVolume(config.audio.player.jumpVolume);

    this.landSound = new THREE.Audio(this.listener);
    this.landSound.setVolume(config.audio.player.landVolume);

    // Load audio assets
    await this.loadAssets(onProgress);

    this.isInitialized = true;
  }

  /**
   * Load all audio assets
   * @param onProgress - Optional callback for loading progress (0-1)
   */
  private async loadAssets(
    onProgress?: (progress: number) => void,
  ): Promise<void> {
    const loader = new THREE.AudioLoader();

    // Define assets to load
    const assetGroups = [
      {
        name: "footstep",
        paths: [
          "audio/footstep_01.mp3",
          "audio/footstep_02.mp3",
          "audio/footstep_03.mp3",
        ],
      },
      {
        name: "impact",
        paths: ["audio/impact_01.mp3", "audio/impact_02.mp3"],
      },
      { name: "jump", paths: ["audio/jump.mp3"] },
      { name: "land", paths: ["audio/land.mp3"] },
    ];

    // Count total files for progress tracking
    const totalFiles = assetGroups.reduce(
      (sum, group) => sum + group.paths.length,
      0,
    );
    let loadedFiles = 0;

    // Load all assets
    for (const group of assetGroups) {
      const buffers: AudioBuffer[] = [];

      for (const path of group.paths) {
        try {
          const buffer = await loader.loadAsync(path);
          buffers.push(buffer);
        } catch {
          console.warn(`[AudioManager] Failed to load: ${path}`);
        }

        // Update progress after each file (success or failure)
        loadedFiles++;
        onProgress?.(loadedFiles / totalFiles);
      }

      if (buffers.length > 0) {
        this.buffers.set(group.name, buffers);
      }
    }

    // Assign buffers to pools
    const footstepBuffers = this.buffers.get("footstep");
    if (footstepBuffers && this.footstepPool) {
      this.footstepPool.setBuffers(footstepBuffers);
    }

    const impactBuffers = this.buffers.get("impact");
    if (impactBuffers && this.impactPool) {
      this.impactPool.setBuffers(impactBuffers);
    }

    const jumpBuffers = this.buffers.get("jump");
    if (jumpBuffers && jumpBuffers[0] && this.jumpSound) {
      this.jumpSound.setBuffer(jumpBuffers[0]);
    }

    const landBuffers = this.buffers.get("land");
    if (landBuffers && landBuffers[0] && this.landSound) {
      this.landSound.setBuffer(landBuffers[0]);
    }
  }

  /**
   * Resume audio context (required after user interaction)
   */
  async resume(): Promise<void> {
    if (this.isResumed) return;

    if (this.context && this.context.state === "suspended") {
      await this.context.resume();
    }

    this.isResumed = true;
  }

  /**
   * Check if audio is ready to play
   */
  private canPlay(): boolean {
    return (
      this.isInitialized && this.isResumed && this.context?.state === "running"
    );
  }

  /**
   * Handle footstep event from render worker
   */
  onFootstep(event: FootstepEvent): void {
    if (!this.canPlay() || !this.footstepPool) return;

    this.footstepPool.play(event.position, {
      volume: event.intensity,
    });
  }

  /**
   * Handle collision event from physics worker
   */
  onCollision(event: CollisionEvent): void {
    if (!this.canPlay() || !this.impactPool) return;

    // Scale volume by impulse (clamped 0-1)
    const normalizedImpulse = Math.min(event.impulse / 10, 1.0);

    this.impactPool.play(event.position, {
      volume: normalizedImpulse,
    });
  }

  /**
   * Handle jump event from physics worker
   */
  onJump(_event: JumpEvent): void {
    if (!this.canPlay() || !this.jumpSound) return;

    if (this.jumpSound.isPlaying) {
      this.jumpSound.stop();
    }
    this.jumpSound.play();
  }

  /**
   * Handle land event from physics worker
   */
  onLand(event: LandEvent): void {
    if (!this.canPlay() || !this.landSound) return;

    if (this.landSound.isPlaying) {
      this.landSound.stop();
    }

    // Scale volume by landing intensity
    this.landSound.setVolume(
      config.audio.player.landVolume * Math.min(event.intensity, 1.0),
    );
    this.landSound.play();
  }

  /**
   * Update listener position for spatial audio
   */
  updateListener(update: ListenerUpdate): void {
    if (!this.isInitialized) return;

    // Update camera position (listener is attached to camera)
    this.camera.position.set(
      update.position.x,
      update.position.y,
      update.position.z,
    );

    // Calculate look-at target from forward vector (reuse pre-allocated vector)
    this.tempLookAt.set(
      update.position.x + update.forward.x,
      update.position.y + update.forward.y,
      update.position.z + update.forward.z,
    );

    // Set camera up vector and look-at
    this.camera.up.set(update.up.x, update.up.y, update.up.z);
    this.camera.lookAt(this.tempLookAt);

    // Update entire scene's world matrices to ensure listener and all sounds are synced
    this.scene.updateMatrixWorld(true);
  }

  /**
   * Set master volume
   */
  setMasterVolume(volume: number): void {
    if (this.listener) {
      this.listener.setMasterVolume(volume);
    }
  }

  dispose(): void {
    this.footstepPool?.dispose();
    this.impactPool?.dispose();

    if (this.jumpSound) {
      if (this.jumpSound.isPlaying) this.jumpSound.stop();
    }
    if (this.landSound) {
      if (this.landSound.isPlaying) this.landSound.stop();
    }

    if (this.context && this.context.state !== "closed") {
      this.context.close();
    }

    this.buffers.clear();
    this.isInitialized = false;
    this.isResumed = false;
  }
}
