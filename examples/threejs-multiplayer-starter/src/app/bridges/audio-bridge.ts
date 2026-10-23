import * as Comlink from "comlink";
import type {
  RenderApi,
  PhysicsApi,
  CollisionEvent,
  JumpEvent,
  LandEvent,
  FootstepEvent,
  ListenerUpdate,
} from "~/shared/types";
import AudioManager from "../managers/audio-manager";

/**
 * AudioBridge - Connects worker events to AudioManager
 *
 * Single responsibility: Wire up audio callbacks from workers.
 * AudioManager must run on main thread (browser limitation).
 */
export default class AudioBridge {
  private audioManager: AudioManager;

  constructor() {
    this.audioManager = new AudioManager();
  }

  /**
   * Initialize audio assets (async loading)
   * @param onProgress - Optional callback for loading progress (0-1)
   */
  async init(onProgress?: (progress: number) => void): Promise<void> {
    await this.audioManager.init(onProgress);
  }

  /**
   * Set up callbacks from workers to AudioManager
   */
  setupCallbacks(
    physicsApi: Comlink.Remote<PhysicsApi>,
    renderApi: Comlink.Remote<RenderApi>,
  ): void {
    // Physics worker callbacks
    physicsApi.setCollisionCallback(
      Comlink.proxy((event: CollisionEvent) => {
        this.audioManager.onCollision(event);
      }),
    );

    physicsApi.setPlayerStateCallback(
      Comlink.proxy((event: JumpEvent | LandEvent) => {
        if (event.type === "jump") {
          this.audioManager.onJump(event);
        } else {
          this.audioManager.onLand(event);
        }
      }),
    );

    // Render worker callbacks
    renderApi.setFootstepCallback(
      Comlink.proxy((event: FootstepEvent) => {
        this.audioManager.onFootstep(event);
      }),
    );

    renderApi.setListenerCallback(
      Comlink.proxy((update: ListenerUpdate) => {
        this.audioManager.updateListener(update);
      }),
    );
  }

  /**
   * Unlock audio (called from user gesture like loading screen start button)
   * This satisfies the browser's autoplay policy requirement
   */
  async unlockAudio(): Promise<void> {
    await this.audioManager.resume();
  }

  /**
   * Dispose of audio resources
   */
  dispose(): void {
    this.audioManager.dispose();
  }
}
