# OpenFrameworks Web Converter

Compile an [openFrameworks](https://openframeworks.cc) project to a WebAssembly
bundle you can embed on any website — built for a classroom workflow where
students upload a sketch and get back an embeddable webpage.

It's a Docker **build worker**: the slow parts (the emsdk toolchain, the oF core,
and the allowlisted addons) are baked into the image once, so each project build
only compiles that project's `src/` — seconds, not minutes. Output is a static
bundle (`index.html` + `.js` + `.wasm` + `.data`) that runs in any modern browser.

**Live demo:** an orbital-motion sketch run through this pipeline →
<https://maxfishman.github.io/orbital-motion-web/>
(source in [`examples/orbital-motion/`](examples/orbital-motion/), hosted from the
[orbital-motion-web](https://github.com/MaxFishman/orbital-motion-web) repo).

## Layout

```
docker/      the build-worker image: Dockerfile + entrypoint + run helper
             → see docker/README.md for build/run and the security sandbox
docs/        build-web.md — the manual recipe + every gotcha, pinned versions
examples/    orbital-motion/ — a sample oF sketch to feed the worker
```

## Quick start

```bash
cd docker
docker build --platform linux/amd64 -t of-web-worker .      # once (amd64 base)
./run.sh ../examples/orbital-motion ./out                   # compile a project
# ./out/ is a GitHub-Pages-ready bundle — push it to a Pages repo and embed it
```

Pinned, verified combination: **openFrameworks 0.12.1 + emsdk 4.0.4**.

## How it works (and the hard-won details)

A faithful C++→JS port isn't mechanically automatable; compiling the real code
with Emscripten is. The worker runs that compile and handles the gotchas that
otherwise make it fail — documented in [`docs/build-web.md`](docs/build-web.md):

- the platform string must be lowercase `emscripten`, built through `emmake`
- `bin/data/` must exist and be non-empty (the link always preloads it)
- a `reallocarray` shim is needed (`docker/scripts/em_shims.c`)
- `index.wasm.map` must be kept (the build links with `-sLOAD_SOURCE_MAP=1`)
- GitHub Pages can't set `COOP`/`COEP`, so the output ships `coi-serviceworker`
  for cross-origin isolation (first visit auto-reloads once)

## Addons

`ofxGui` and `ofxEmscripten` are verified to compile for the web. Other addons
vary — the worker validates each project's `addons.make` against an allowlist
and rejects unsupported ones with a clear message. Extend the allowlist with
`--build-arg ADDON_ALLOWLIST="ofxGui ofxEmscripten ofxXmlSettings"`.

## Status

The build worker is proven end-to-end (image authored; the orbital-motion sketch
compiles and runs live on GitHub Pages). Not yet built here as a hosted service —
the natural next step is a small upload → queue → `docker run` → publish frontend
around the worker. See `docker/README.md` for that sketch.
