import * as THREE from "three";

/**
 * SoundPool - Pooled audio sources for efficient sound playback
 *
 * Uses round-robin allocation to reuse audio sources, preventing
 * garbage collection stalls from creating new Audio objects.
 */

export interface SoundPoolConfig {
  poolSize: number;
  volume: number;
  refDistance: number;
  maxDistance: number;
  rolloffFactor: number;
}

export class SoundPool {
  private sounds: THREE.PositionalAudio[] = [];
  private currentIndex = 0;
  private buffers: AudioBuffer[] = [];
  private baseVolume: number;
  private listener: THREE.AudioListener;
  private scene: THREE.Scene;
  private config: SoundPoolConfig;

  constructor(
    listener: THREE.AudioListener,
    scene: THREE.Scene,
    config: SoundPoolConfig,
  ) {
    this.listener = listener;
    this.scene = scene;
    this.config = config;
    this.baseVolume = config.volume;
    this.createPool();
  }

  private createPool(): void {
    for (let i = 0; i < this.config.poolSize; i++) {
      const sound = new THREE.PositionalAudio(this.listener);
      sound.setRefDistance(this.config.refDistance);
      sound.setMaxDistance(this.config.maxDistance);
      sound.setRolloffFactor(this.config.rolloffFactor);
      sound.setVolume(this.baseVolume);
      this.sounds.push(sound);
      this.scene.add(sound);
    }
  }

  /**
   * Set audio buffers (multiple for variation)
   */
  setBuffers(buffers: AudioBuffer[]): void {
    this.buffers = buffers;
  }

  /**
   * Play a sound at a position with optional volume/pitch modifiers
   */
  play(
    position: { x: number; y: number; z: number },
    options?: {
      volume?: number;
      playbackRate?: number;
    },
  ): void {
    if (this.buffers.length === 0) return;

    const sound = this.sounds[this.currentIndex];
    this.currentIndex = (this.currentIndex + 1) % this.config.poolSize;

    // Stop if already playing
    if (sound.isPlaying) {
      sound.stop();
    }

    // Select random buffer for variation
    const buffer =
      this.buffers[Math.floor(Math.random() * this.buffers.length)];
    sound.setBuffer(buffer);

    // Update position and world matrix for spatial audio
    sound.position.set(position.x, position.y, position.z);
    sound.updateMatrixWorld();

    // Apply options
    const volume = options?.volume ?? 1.0;
    sound.setVolume(volume * this.baseVolume);

    if (options?.playbackRate !== undefined) {
      sound.setPlaybackRate(options.playbackRate);
    } else {
      // Add slight random pitch variation for natural feel
      sound.setPlaybackRate(0.95 + Math.random() * 0.1);
    }

    sound.play();
  }

  /**
   * Update base volume (for master volume changes)
   */
  setVolume(volume: number): void {
    this.baseVolume = volume;
  }

  dispose(): void {
    for (const sound of this.sounds) {
      if (sound.isPlaying) {
        sound.stop();
      }
      this.scene.remove(sound);
    }
    this.sounds = [];
    this.buffers = [];
  }
}
