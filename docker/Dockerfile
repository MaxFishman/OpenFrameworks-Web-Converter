# ---------------------------------------------------------------------------
# openFrameworks -> WebAssembly build worker
#
# A reusable image that compiles an uploaded openFrameworks project to a
# browser bundle (index.html/.js/.wasm/.data). The slow parts — the emsdk
# toolchain, the openFrameworks core, and the allowlisted addons — are all
# baked in at image-build time, so each per-project run only compiles the
# student's src/ (seconds, not minutes).
#
# Base is emscripten/emsdk (emsdk preinstalled + on PATH). It is amd64-only,
# so on Apple Silicon build/run with:  --platform linux/amd64
#
#   docker build --platform linux/amd64 -t of-web-worker .
#   docker run  --platform linux/amd64 --rm --network none \
#       -v "$PWD/project":/work/input:ro -v "$PWD/out":/work/output of-web-worker
#
# Versions are pinned to the combination verified end-to-end (oF 0.12.1 +
# emsdk 4.0.4). See README.md for the security sandbox flags.
# ---------------------------------------------------------------------------
FROM emscripten/emsdk:4.0.4

# Toolchain deps for fetching + building (emscripten target only; no native GL).
RUN apt-get update && apt-get install -y --no-install-recommends \
        make git curl ca-certificates bzip2 \
    && rm -rf /var/lib/apt/lists/*

ARG OF_VERSION=0.12.1
# Space/comma list of addons students are allowed to use. ofxEmscripten is
# auto-added by oF for the web target, so it is always permitted.
ARG ADDON_ALLOWLIST="ofxGui ofxEmscripten"

ENV OF_ROOT=/opt/openFrameworks \
    EM_CACHE=/home/builder/.em_cache \
    ADDON_ALLOWLIST=${ADDON_ALLOWLIST}

# Non-root build user (defense in depth; the container should still be run
# sandboxed — see README). Everything it needs is owned by it.
RUN useradd -m -u 1000 builder \
    && mkdir -p ${OF_ROOT} /work/input /work/output ${EM_CACHE} \
    && chown -R builder:builder ${OF_ROOT} /work /home/builder
USER builder
WORKDIR /opt

# --- openFrameworks source tree (release) -----------------------------------
# Base image is amd64; keep an arch switch for portability if the base changes.
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) OF_PKG="of_v${OF_VERSION}_linux64_gcc6_release" ;; \
      arm64) OF_PKG="of_v${OF_VERSION}_linuxaarch64_release" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -L --fail -o /tmp/of.tar.gz \
      "https://github.com/openframeworks/openFrameworks/releases/download/${OF_VERSION}/${OF_PKG}.tar.gz"; \
    tar -xzf /tmp/of.tar.gz -C ${OF_ROOT} --strip-components=1; \
    rm /tmp/of.tar.gz

# --- openFrameworks prebuilt emscripten core libraries ----------------------
RUN cd ${OF_ROOT}/scripts/emscripten && ./download_libs.sh

# --- Guards baked in: the reallocarray shim (gotcha #4) + GitHub Pages SW -----
COPY --chown=builder:builder scripts/em_shims.c /opt/em_shims.c
COPY --chown=builder:builder scripts/coi-serviceworker.js /opt/coi-serviceworker.js

# --- Performance profile: static link, fixed memory, strip debug/sourcemap -----
# Turns oF's default compatibility build into a fast, ~5x smaller one. Must run
# before warming the core so the warmup link uses the same flags.
COPY --chown=builder:builder scripts/perf-config.patch.sh /opt/perf-config.patch.sh
RUN bash /opt/perf-config.patch.sh \
      "${OF_ROOT}/libs/openFrameworksCompiled/project/emscripten/config.emscripten.default.mk"

# --- Prebuild the oF core + allowlisted addons for WASM ---------------------
# Uses oF's own emptyExample (brings a valid Makefile/config.make), sets its
# addons.make to the allowlist, and links once. This warms:
#   - libs/openFrameworksCompiled/.../libopenFrameworks.o  (shared core)
#   - addons/obj/emscripten/...                            (shared addon objs)
#   - $EM_CACHE                                            (emscripten syslibs)
# so per-project runs reuse all of it. Also proves the toolchain inside the image.
RUN set -eux; \
    cp -r ${OF_ROOT}/examples/templates/emptyExample ${OF_ROOT}/apps/myApps/_warmup; \
    cd ${OF_ROOT}/apps/myApps/_warmup; \
    printf '%s\n' ${ADDON_ALLOWLIST} > addons.make; \
    mkdir -p bin/data && : > bin/data/.keep; \
    cp /opt/em_shims.c src/em_shims.c; \
    emmake make -j"$(nproc)" PLATFORM_OS=emscripten PROJECT_EMSCRIPTEN_TOTAL_MEMORY=268435456; \
    ls -la bin/em/_warmup/index.wasm

# --- Per-run entrypoint (copied last so edits don't bust the heavy layers) ---
USER root
COPY scripts/build-project.sh /usr/local/bin/build-project
RUN chmod +x /usr/local/bin/build-project
USER builder

WORKDIR /work
# Default I/O contract: mount project at /work/input:ro, collect /work/output.
ENTRYPOINT ["build-project"]
