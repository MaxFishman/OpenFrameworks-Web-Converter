# openFrameworks → Web build worker

A reusable Docker image that compiles an uploaded openFrameworks project to a
browser bundle (`index.html` + `.js` + `.wasm` + `.data`) via Emscripten.

The expensive layers — emsdk toolchain, the oF core, and the allowlisted addons —
are **baked into the image once**, so each student build only compiles their
`src/` (seconds). This is the per-upload step of a "students upload a zip, get an
embeddable webpage" service.

Pinned, verified combination: **openFrameworks 0.12.1 + emsdk 4.0.4** (the exact
versions proven end-to-end; see `../NOC_OrbitalMotion-GravitationalAttraction-main/BUILD_WEB.md`).

```
Dockerfile              the image (base: emscripten/emsdk:4.0.4, amd64-only)
scripts/build-project.sh per-upload entrypoint: validate → guard → compile → collect
scripts/em_shims.c       reallocarray shim, injected into every project
run.sh                   convenience: build one project dir into ./out, sandboxed
```

## Build the image (once)

```bash
cd docker   # this directory, inside the OpenFrameworks-Web-Converter repo
docker build --platform linux/amd64 -t of-web-worker .
```

First build takes a while (it compiles the oF core for WASM inside the image).
On Apple Silicon this runs under emulation — fine for building the image; run the
actual worker on an amd64 host in production.

Change the allowlist at build time:

```bash
docker build --platform linux/amd64 \
  --build-arg ADDON_ALLOWLIST="ofxGui ofxEmscripten ofxXmlSettings" \
  -t of-web-worker .
```

## Run it on one project

```bash
./run.sh /path/to/their/openframeworks/project ./out
# -> ./out/index.html  index.js  index.wasm  index.data  app.js  style.css
#    + _headers (COOP/COEP)  + EMBED.html
```

Or directly:

```bash
docker run --platform linux/amd64 --rm --network none \
  --cpus 2 --memory 2g --pids-limit 256 \
  --security-opt no-new-privileges --cap-drop ALL \
  -v "$PWD/project":/work/input:ro \
  -v "$PWD/out":/work/output \
  of-web-worker
```

**Input** `/work/input` may be the project dir itself or a wrapper folder that
contains it (the typical unzip). **Output** lands in `/work/output`.

**Exit codes:** `0` success · `2` rejected (disallowed addon, or no `src/` found —
a clean user-facing message) · `1` compilation failed (build log on stderr).

## What the worker does per run (the four gotchas, automated)

1. uses lowercase `PLATFORM_OS=emscripten`
2. compiles through `emmake` (so the compiler is `em++`, not native clang)
3. guarantees a non-empty `bin/data/` (the link always preloads it)
4. injects `src/em_shims.c` so `reallocarray` resolves

Plus: validates `addons.make` against the allowlist, borrows `Makefile`/`config.make`
from a template if the upload was `src/`-only, and emits COOP/COEP headers.

## Serving the output

The build is pthread-enabled, so the page only instantiates under
**cross-origin isolation** (`COOP`/`COEP`). There are two cases:

- **GitHub Pages (default, `GHPAGES=1`)** — Pages can't send custom headers, so
  the worker ships `coi-serviceworker.js` (injected as the first `<head>` script)
  plus `.nojekyll`. Just push the output to a Pages repo and serve it. The first
  visit registers the service worker and auto-reloads once; every visit after is
  normal. Verified live end-to-end.
- **A host you control (`GHPAGES=0`)** — set the real headers from the emitted
  `_headers` file (Cloudflare rule, S3+CloudFront, nginx `add_header`, …) and you
  can delete `coi-serviceworker.js` + the injected tag.

Embed with the snippet in `EMBED.html` either way.

> **Do not strip `index.wasm.map`.** oF links with `-sLOAD_SOURCE_MAP=1`, so the
> runtime fetches and JSON-parses the map at startup — a missing map 404s and
> aborts the app at "Preparing…". The worker keeps it; don't prune it downstream.

## Security — this compiles untrusted C++

The compile step runs arbitrary student code through a compiler. The image helps
(non-root `builder` user), but **isolation is the runner's job**. The flags in
`run.sh` are the baseline:

- `--network none` — no exfiltration or downloads during compile (most important)
- `--memory`, `--cpus`, `--pids-limit` — contain fork bombs / OOM
- `--security-opt no-new-privileges`, `--cap-drop ALL`
- `--rm` ephemeral container + host-side `timeout`
- input mounted read-only

For stronger isolation run under **gVisor** (`--runtime=runsc`) or a microVM
(Firecracker/Kata). The produced `.wasm` is safe — it runs in the student's own
browser sandbox.

## Wiring it into an uploader (the rest of the pipeline)

```
browser  ──upload project.zip──▶  API (validate size/shape, enqueue job)
                                        │
                                        ▼
                                   queue (SQS / Redis / RQ)
                                        │
                              build worker pops a job:
                                 unzip ─▶ docker run of-web-worker (sandboxed)
                                        │   exit 2 → show friendly reject msg
                                        │   exit 1 → show build log
                                        ▼   exit 0 → publish /work/output
                              static host (S3 / Cloudflare) + COOP/COEP headers
                                        │
                                        ▼
                              return URL + <iframe> embed to the student
```

The worker is the hard part and it's done here. Everything else is a standard
upload-and-queue service. Give each job a unique output prefix so student builds
don't collide, and cap concurrent `docker run`s to your host's core count.

## Upgrading versions

Bump `ARG OF_VERSION` and the `FROM emscripten/emsdk:<ver>` tag together, then
rebuild. oF's Emscripten support varies across releases — re-run a known project
(e.g. the orbital-motion sketch) through the new image before rolling it out.
