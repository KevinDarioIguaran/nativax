import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { EventEmitter } from "~/shared/utils";
import type { ResourceItem, Source } from "~/shared/types";

type ResourcesEvents = {
  progress: {
    url: string;
    loaded: number;
    total: number;
    progress: number;
  };
  ready: {
    itemsLoaded: number;
  };
  error: {
    source: string;
    error: Error;
  };
};

/**
 * Resources - Asset loader compatible with worker contexts
 *
 * Uses fetch + createImageBitmap for textures (no DOM dependency).
 * GLTFLoader works natively in workers.
 *
 * Note on ImageBitmap usage:
 * Three.js CanvasTexture and CubeTexture accept ImageBitmap as valid image sources
 * since r128+. The type definitions are overly strict, so we use type assertions.
 * This is safe because ImageBitmap implements the TexImageSource interface.
 *
 * @see https://threejs.org/docs/#api/en/textures/Texture
 */
export default class Resources extends EventEmitter<ResourcesEvents> {
  items: Record<string, ResourceItem>;
  toLoad: number;
  loaded: number;
  isReady: boolean;

  private gltfLoader: GLTFLoader;
  private baseUrl: string;

  constructor(sources: Source[]) {
    super();

    this.items = {};
    this.toLoad = sources.length;
    this.loaded = 0;
    this.isReady = false;

    // Get base URL for resolving relative paths in worker
    this.baseUrl = self.location.origin + "/";

    // GLTFLoader works in workers
    this.gltfLoader = new GLTFLoader();

    this.startLoading(sources);
  }

  private getAbsoluteUrl(path: string): string {
    if (path.startsWith("http://") || path.startsWith("https://")) {
      return path;
    }
    return this.baseUrl + path;
  }

  private startLoading(sources: Source[]): void {
    for (const source of sources) {
      switch (source.type) {
        case "texture":
          this.loadTexture(source);
          break;
        case "cubeTexture":
          this.loadCubeTexture(source);
          break;
        case "gltfModel":
          this.loadGLTF(source);
          break;
        default:
          console.error(`Unknown source type: ${source.type}`);
      }
    }
  }

  private async loadTexture(source: Source): Promise<void> {
    const path = this.getAbsoluteUrl(source.path as string);

    try {
      const response = await fetch(path);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      const blob = await response.blob();
      const imageBitmap = await createImageBitmap(blob, {
        imageOrientation: "flipY",
      });

      // ImageBitmap is a valid TexImageSource for Three.js textures (r128+)
      // Type assertion needed due to overly strict Three.js type definitions
      const texture = new THREE.CanvasTexture(
        imageBitmap as unknown as OffscreenCanvas,
      );
      texture.needsUpdate = true;
      this.sourceLoaded(source, texture);
    } catch (error) {
      console.error(`Failed to load texture: ${path}`, error);
      this.emit("error", {
        source: source.name,
        error: error instanceof Error ? error : new Error(String(error)),
      });
      // Provide fallback texture to prevent rendering errors
      this.sourceLoaded(source, new THREE.Texture());
    }
  }

  private async loadCubeTexture(source: Source): Promise<void> {
    const paths = (source.path as string[]).map((p) => this.getAbsoluteUrl(p));

    try {
      const imageBitmaps = await Promise.all(
        paths.map(async (path) => {
          const response = await fetch(path);
          if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
          }
          const blob = await response.blob();
          return createImageBitmap(blob);
        }),
      );

      // ImageBitmap array is valid for CubeTexture (r128+)
      // Type assertion needed due to overly strict Three.js type definitions
      const cubeTexture = new THREE.CubeTexture(
        imageBitmaps as unknown as HTMLImageElement[],
      );
      cubeTexture.needsUpdate = true;
      this.sourceLoaded(source, cubeTexture);
    } catch (error) {
      console.error(`Failed to load cube texture: ${source.name}`, error);
      this.emit("error", {
        source: source.name,
        error: error instanceof Error ? error : new Error(String(error)),
      });
      // Provide fallback texture to prevent rendering errors
      this.sourceLoaded(source, new THREE.CubeTexture());
    }
  }

  private loadGLTF(source: Source): void {
    const path = this.getAbsoluteUrl(source.path as string);

    this.gltfLoader.load(
      path,
      (gltf) => {
        this.sourceLoaded(source, gltf);
      },
      undefined,
      (error) => {
        console.error(`Failed to load GLTF: ${path}`, error);
        this.emit("error", {
          source: source.name,
          error: error instanceof Error ? error : new Error(String(error)),
        });
        // Still count as loaded to prevent hanging, but with null value
        // Consumers should check for null/undefined models
        this.sourceLoaded(source, null as unknown as ResourceItem);
      },
    );
  }

  private sourceLoaded(source: Source, file: ResourceItem): void {
    this.items[source.name] = file;
    this.loaded++;

    const url = Array.isArray(source.path) ? source.path[0] : source.path;
    this.emit("progress", {
      url,
      loaded: this.loaded,
      total: this.toLoad,
      progress: this.loaded / this.toLoad,
    });

    if (this.loaded === this.toLoad) {
      this.isReady = true;
      this.emit("ready", {
        itemsLoaded: this.loaded,
      });
    }
  }

  /**
   * Dispose of the loader resources
   */
  dispose(): void {
    // GLTFLoader doesn't have a dispose method, but we can clear references
    // Clear items to allow garbage collection of loaded resources
    // Note: Actual Three.js objects (textures, geometries) should be disposed
    // by their consuming components
    this.items = {};
  }
}
