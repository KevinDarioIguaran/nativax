import { fileURLToPath, URL } from "node:url";
import glsl from "vite-plugin-glsl";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [glsl()],
  server: {
    headers: {
      // Required for SharedArrayBuffer
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },
  preview: {
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },
  worker: {
    format: "es",
    plugins: () => [glsl()],
  },
  resolve: {
    alias: {
      "~/app": fileURLToPath(new URL("./src/app", import.meta.url)),
      "~/workers": fileURLToPath(new URL("./src/workers", import.meta.url)),
      "~/shared": fileURLToPath(new URL("./src/shared", import.meta.url)),
      "~/shaders": fileURLToPath(new URL("./src/shaders", import.meta.url)),
    },
  },
});
