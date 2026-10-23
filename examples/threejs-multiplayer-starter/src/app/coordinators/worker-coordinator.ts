import * as Comlink from "comlink";
import type { RenderApi, PhysicsApi, ViewportSize } from "~/shared/types";
import {
  SharedTransformBuffer,
  isSharedArrayBufferSupported,
} from "~/shared/buffers/transform-buffer";
import { config } from "~/shared/config";
import LoadProgressTracker from "../utils/load-progress-tracker";
import AudioBridge from "../bridges/audio-bridge";

export interface WorkerCallbacks {
  onProgress?: (progress: number) => void;
  onReady?: () => void;
  onFrameTiming?: (deltaMs: number) => void;
}

/**
 * WorkerCoordinator - Manages worker lifecycle and loading coordination
 *
 * Responsibilities:
 * - Create, initialize, and dispose of workers
 * - Coordinate loading progress from audio, physics, and render
 * - Own AudioBridge (bridges main thread audio to worker events)
 */
export default class WorkerCoordinator {
  private renderWorker: Worker | null = null;
  private physicsWorker: Worker | null = null;
  private renderApi: Comlink.Remote<RenderApi> | null = null;
  private physicsApi: Comlink.Remote<PhysicsApi> | null = null;
  private sharedBuffer: SharedTransformBuffer | null = null;
  private audioBridge: AudioBridge;

  constructor() {
    this.audioBridge = new AudioBridge();
  }

  /**
   * Initialize audio, physics, and render workers with coordinated progress tracking
   */
  async init(
    canvas: OffscreenCanvas,
    viewport: ViewportSize,
    debug: boolean,
    callbacks: WorkerCallbacks,
  ): Promise<void> {
    // SharedArrayBuffer is required - no fallback
    if (!isSharedArrayBufferSupported()) {
      throw new Error(
        "SharedArrayBuffer is not supported. " +
          "Please use a modern browser with cross-origin isolation enabled.",
      );
    }

    // Create shared buffer for zero-copy transform sync
    this.sharedBuffer = new SharedTransformBuffer();
    const buffers = this.sharedBuffer.getBuffers();

    // Set up progress tracking with weighted sources
    const progressTracker = new LoadProgressTracker((progress) => {
      callbacks.onProgress?.(progress);
    });
    progressTracker.addSource("audio", 1);
    progressTracker.addSource("physics", 1);
    progressTracker.addSource("render", 4);

    // Initialize audio, physics, and render in parallel
    await Promise.all([
      this.audioBridge.init(progressTracker.createCallback("audio")),
      this.initPhysicsWorker(
        buffers,
        progressTracker.createCallback("physics"),
      ),
      this.initRenderWorker(
        canvas,
        viewport,
        debug,
        callbacks,
        buffers,
        progressTracker.createCallback("render"),
      ),
    ]);
  }

  private async initRenderWorker(
    canvas: OffscreenCanvas,
    viewport: ViewportSize,
    debug: boolean,
    callbacks: WorkerCallbacks,
    sharedBuffers: {
      control: SharedArrayBuffer;
      transform: SharedArrayBuffer;
      timing: SharedArrayBuffer;
      flags: SharedArrayBuffer;
    },
    onProgress: (progress: number) => void,
  ): Promise<void> {
    this.renderWorker = new Worker(
      new URL("../../workers/render.worker.ts", import.meta.url),
      { type: "module" },
    );

    this.renderApi = Comlink.wrap<RenderApi>(this.renderWorker);

    await this.renderApi.init(
      Comlink.transfer(canvas, [canvas]),
      viewport,
      debug,
      sharedBuffers,
      Comlink.proxy(onProgress),
      callbacks.onReady ? Comlink.proxy(callbacks.onReady) : undefined,
      callbacks.onFrameTiming
        ? Comlink.proxy(callbacks.onFrameTiming)
        : undefined,
    );
  }

  private async initPhysicsWorker(
    sharedBuffers: {
      control: SharedArrayBuffer;
      transform: SharedArrayBuffer;
      timing: SharedArrayBuffer;
      flags: SharedArrayBuffer;
    },
    onProgress: (progress: number) => void,
  ): Promise<void> {
    this.physicsWorker = new Worker(
      new URL("../../workers/physics.worker.ts", import.meta.url),
      { type: "module" },
    );

    this.physicsApi = Comlink.wrap<PhysicsApi>(this.physicsWorker);

    await this.physicsApi.init(
      config.physics.gravity,
      sharedBuffers,
      Comlink.proxy(onProgress),
    );
  }

  /**
   * Get the Render worker API
   */
  getRenderApi(): Comlink.Remote<RenderApi> {
    if (!this.renderApi) {
      throw new Error("WorkerCoordinator not initialized");
    }
    return this.renderApi;
  }

  /**
   * Get the Physics worker API
   */
  getPhysicsApi(): Comlink.Remote<PhysicsApi> {
    if (!this.physicsApi) {
      throw new Error("WorkerCoordinator not initialized");
    }
    return this.physicsApi;
  }

  /**
   * Get the shared transform buffer
   */
  getSharedBuffer(): SharedTransformBuffer {
    if (!this.sharedBuffer) {
      throw new Error("WorkerCoordinator not initialized");
    }
    return this.sharedBuffer;
  }

  /**
   * Get the audio bridge for setting up callbacks and unlocking audio
   */
  getAudioBridge(): AudioBridge {
    return this.audioBridge;
  }

  /**
   * Start physics simulation
   */
  startPhysics(): void {
    if (!this.physicsApi) {
      throw new Error("WorkerCoordinator not initialized");
    }
    this.physicsApi.start();
  }

  /**
   * Resize the render viewport
   */
  resize(viewport: ViewportSize): void {
    this.renderApi?.resize(viewport);
  }

  /**
   * Dispose of all workers and resources
   *
   * Uses direct postMessage for cleanup instead of Comlink because
   * Comlink calls are async and won't complete during beforeunload.
   * The direct message triggers synchronous GPU device destruction.
   */
  dispose(): void {
    // Send direct cleanup message to render worker (bypasses async Comlink)
    // This ensures GPU device.destroy() is called synchronously before page unloads
    this.renderWorker?.postMessage({ type: "cleanup" });

    // Comlink dispose calls (may not complete during beforeunload, but good for normal cleanup)
    this.physicsApi?.dispose();
    this.renderApi?.dispose();

    this.physicsWorker?.terminate();
    this.renderWorker?.terminate();

    // Dispose audio bridge
    this.audioBridge.dispose();

    this.physicsWorker = null;
    this.renderWorker = null;
    this.physicsApi = null;
    this.renderApi = null;
    this.sharedBuffer = null;
  }
}
