# Orbital Motion — Gravitational Attraction (openFrameworks → WebAssembly)

A Nature of Code orbital-motion sketch (openFrameworks 0.12.1 + ofxGui),
compiled to WebAssembly with Emscripten and hosted on GitHub Pages.

**Live:** see the repo's Pages URL (Settings → Pages).

## How it's served

The Emscripten build is pthread-enabled, so it needs
[cross-origin isolation](https://web.dev/articles/coop-coep)
(`COOP`/`COEP`). GitHub Pages can't send custom headers, so
[`coi-serviceworker`](https://github.com/gzuidhof/coi-serviceworker) supplies
them client-side. The first visit registers the service worker and reloads
once automatically; after that the app runs normally.

## Contents

```
index.html            oF/emscripten shell (coi-serviceworker injected in <head>)
index.js / .wasm      the compiled sketch (~26 MB total)
index.data            preloaded data package
index.wasm.map        source map (REQUIRED — the build links with LOAD_SOURCE_MAP=1)
app.js, style.css     oF emscripten runtime glue + styling
coi-serviceworker.js  cross-origin isolation shim for GitHub Pages
.nojekyll             serve files verbatim (no Jekyll)
.github/workflows/    deploys this folder to Pages on push to main
```

## Updating

Replace the bundle files with a fresh Emscripten build (keep `coi-serviceworker.js`,
`.nojekyll`, and `index.wasm.map`), commit, and push to `main`. The Action redeploys.
