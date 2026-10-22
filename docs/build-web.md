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
(~26 MB total for this sketch; `.wasm.map` is debug-only, drop it for hosting.)

## Serving / embedding

The build is pthread-enabled, so the page **requires cross-origin isolation headers**:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Without them the WASM won't instantiate. Set these on your static host (or a
Netlify `_headers` / Cloudflare rule). Embed with:

```html
<iframe src="https://host/path/to/index.html"
        width="1024" height="768" style="border:0"
        allow="fullscreen"></iframe>
```

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
