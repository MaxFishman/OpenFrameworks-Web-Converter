# Building this openFrameworks sketch for the web (Emscripten / WASM)

This is the **verified, working** recipe used to compile this project to a browser
bundle. It is the reference for an automated "student uploads a zip → gets an
embeddable webpage" pipeline. Every step below was run and confirmed on
macOS (Apple Silicon), openFrameworks 0.12.1, emsdk 4.0.4.

## One-time toolchain setup (bake this into your Docker image)

```bash
# 1. openFrameworks 0.12.1 (osx release) unpacked at $OF_ROOT
#    Project must live at $OF_ROOT/apps/myApps/<project>/  (the ../../.. paths depend on this)

# 2. Emscripten SDK, pinned to the version oF expects
cd $OF_ROOT
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk && ./emsdk install 4.0.4 && ./emsdk activate 4.0.4

# 3. openFrameworks' prebuilt emscripten core libraries
cd $OF_ROOT/scripts/emscripten && ./download_libs.sh
```

## Per-project build (this is what runs for each student upload)

```bash
source $OF_ROOT/emsdk/emsdk_env.sh
cd $OF_ROOT/apps/myApps/<project>

# REQUIRED FIXES (see "Gotchas" — a template/preprocess step should guarantee both):
mkdir -p bin/data && : > bin/data/.keep      # file_packager needs a non-empty data dir
#   + ensure src/em_shims.c (reallocarray shim) is present — see Gotchas

emmake make -j$(nproc) PLATFORM_OS=emscripten
#   ^ emmake (sets CXX=em++) is MANDATORY; plain `make` uses native clang and fails.
#   ^ platform string is lowercase `emscripten`, NOT `Emscripten`.
```

Output lands in `bin/em/<project>/`:
`index.html  index.js  index.wasm  index.data  app.js  style.css`
(With the default oF flags this is ~26 MB and a `.wasm.map` is emitted that the
runtime fetches at startup — see the performance profile below, which the build
worker applies to cut it to ~5.4 MB and emit no map.)

## Serving / embedding

The build is pthread-enabled, so the page needs **cross-origin isolation**
(`COOP`/`COEP`). Two cases:

- **A host you control** — set the headers directly:
  ```
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  ```
  (nginx `add_header`, S3+CloudFront, a Netlify `_headers`, a Cloudflare rule…).
- **GitHub Pages** (can't set headers) — ship
  [`coi-serviceworker.js`](https://github.com/gzuidhof/coi-serviceworker) and
  inject it as the first `<head>` script; it supplies isolation client-side. The
  first visit registers it and auto-reloads once. Add a `.nojekyll` file too.
  The build worker does all of this automatically (`GHPAGES=1`).

Embed with:

```html
<iframe src="https://host/path/to/index.html"
        width="1024" height="768" style="border:0"
        allow="fullscreen"></iframe>
```

## Performance profile (strongly recommended)

oF's default Emscripten config optimizes for compatibility, not speed. For a
trivial sketch the result is still noticeably sluggish — and because many sketches
advance physics per frame with **no delta-time**, a low frame rate makes the
motion itself run slow/wrong vs native. The build worker patches the config
(`docker/scripts/perf-config.patch.sh`) to:

- **static link** (`MAIN_MODULE=0`, not dynamic) → cross-module inlining; `index.js` 12 MB → ~190 KB
- **no `ALLOW_MEMORY_GROWTH`** (fixed `TOTAL_MEMORY`) → avoids the slow-memory penalty that pthreads + growable memory impose on *every* access
- **drop** `--profiling-funcs`, `GL_ASSERTIONS`, `VERBOSE`, `LOAD_SOURCE_MAP`/`-gsource-map`, `EMBIND_AOT`

Net: ~5.4 MB total (from ~27 MB), native-like frame rate, and no `index.wasm.map`.

## Gotchas discovered (each one is a pipeline guard you need)

1. **`make PLATFORM_OS=Emscripten` (capital E) → "does not support your operating system".**
   The makefile matches lowercase `emscripten` only.

2. **Plain `make` compiles with native clang** and dies on `-matomics`/`-mbulk-memory`.
   Must invoke through `emmake` so the compiler becomes `em++`/`emcc`.

3. **`error: bin/data@data does not exist`.** The emscripten link always runs
   `--preload-file bin/data@data`. A `bin/data/` directory must exist, AND it must
   contain at least one file (an empty dir makes `file_packager` return "Nothing to do!"
   and fail). Preprocess step: `mkdir -p bin/data && touch bin/data/.keep`.

4. **`error: undefined symbol: reallocarray`.** oF's prebuilt emscripten libs reference
   `reallocarray`, which emsdk 4.0.4's musl libc doesn't export; oF links with
   `-sERROR_ON_UNDEFINED_SYMBOLS=1`. Fix: drop `src/em_shims.c` into the project
   (defines `reallocarray` as overflow-checked `realloc`). This file is committed here.

## Addon support = the real limiter for a classroom uploader
`ofxGui` and `ofxEmscripten` compile cleanly (verified). Maintain an **allowlist** of
addons known to build for web; reject uploads whose `addons.make` references anything
else with a clear message, rather than surfacing raw compiler errors to students.
