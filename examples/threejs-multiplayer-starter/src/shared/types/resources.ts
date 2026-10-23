import type * as THREE from "three";
import type {
  GLTF,
  GLTFLoader,
} from "three/examples/jsm/loaders/GLTFLoader.js";

export type ResourceItem = THREE.Texture | THREE.CubeTexture | GLTF;

export type Loader = GLTFLoader | THREE.TextureLoader | THREE.CubeTextureLoader;

export type SourceType = "texture" | "cubeTexture" | "gltfModel";

export type Source = {
  name: string;
  type: SourceType;
  path: string | string[];
};
