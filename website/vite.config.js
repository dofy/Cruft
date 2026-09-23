import { resolve } from "node:path";
import { defineConfig } from "vite";

// Three static pages, one per language. English sits at the root so that
// `/` is the x-default; the Chinese pages live in directories whose names match
// the hreflang codes, which is what the `<link rel="alternate">` tags point at.
//
// Vite needs every HTML entry listed explicitly — without this config only
// index.html gets built and the two Chinese pages silently vanish from dist/.
export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        en: resolve(import.meta.dirname, "index.html"),
        "zh-Hans": resolve(import.meta.dirname, "zh-Hans/index.html"),
        "zh-Hant": resolve(import.meta.dirname, "zh-Hant/index.html"),
      },
    },
  },
});
