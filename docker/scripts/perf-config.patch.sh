#!/usr/bin/env bash
# Apply a performance profile to oF's Emscripten link config, in place.
# Run once at image-build time (before warming the core). Turns the default
# compatibility build into a fast, small one:
#   - static link (MAIN_MODULE=0) instead of dynamic  → index.js 12MB→~190KB
#   - no ALLOW_MEMORY_GROWTH (pthread+growth = slow memory on every access)
#   - drop --profiling-funcs / GL_ASSERTIONS / VERBOSE / LOAD_SOURCE_MAP / -gsource-map
#   - drop EMBIND_AOT (incompatible with MAIN_MODULE=0; embind binds at runtime)
#   - no index.wasm.map emitted (so nothing to ship or fetch at startup)
# Net: ~5x smaller bundle and native-like frame rate. The orbital-motion sketch
# is frame-rate-dependent, so this directly fixes "slow / wrong motion" vs native.
set -euo pipefail
CFG="${1:?usage: perf-config.patch.sh <path to config.emscripten.default.mk>}"
cp "$CFG" "$CFG.orig-backup"

python3 - "$CFG" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()

def sub(pat, repl, s, n=1):
    s2, c = re.subn(pat, repl, s, count=n)
    assert c == n, f"pattern not found (x{n}): {pat}"
    return s2

# drop --profiling-funcs
s = sub(r'--preload-file bin/data@data --emrun --bind --profiling-funcs',
        r'--preload-file bin/data@data --emrun --bind', s)
# disable GL_ASSERTIONS / VERBOSE
s = sub(r'\nPLATFORM_LDFLAGS \+= -s GL_ASSERTIONS=1', r'\n# PERF: PLATFORM_LDFLAGS += -s GL_ASSERTIONS=1', s)
s = sub(r'\nPLATFORM_LDFLAGS \+= -s VERBOSE=1',       r'\n# PERF: PLATFORM_LDFLAGS += -s VERBOSE=1', s)
# static link
s = sub(r'-s MAIN_MODULE=1 -DEMCC_FORCE_STDLIBS=1', r'-s MAIN_MODULE=0', s)
# drop EXPORT_ALL (only needed for dynamic linking)
s = sub(r'\nPLATFORM_LDFLAGS \+= -s EXPORT_ALL=1', r'\n# PERF: PLATFORM_LDFLAGS += -s EXPORT_ALL=1', s)
# drop ALLOW_MEMORY_GROWTH
s = sub(r'\nPLATFORM_LDFLAGS \+= -s ALLOW_MEMORY_GROWTH=1', r'\n# PERF: PLATFORM_LDFLAGS += -s ALLOW_MEMORY_GROWTH=1', s)
# drop LOAD_SOURCE_MAP (keep ABORT_ON_WASM_EXCEPTIONS)
s = sub(r'-sLOAD_SOURCE_MAP=1 -sABORT_ON_WASM_EXCEPTIONS=0', r'-sABORT_ON_WASM_EXCEPTIONS=0', s)
# drop EMBIND_AOT
s = sub(r'-s DYNAMIC_EXECUTION=0 -s EMBIND_AOT=1', r'-s DYNAMIC_EXECUTION=0', s)
# drop -gsource-map from the release optimization line (no .wasm.map emitted)
s = sub(r'(PLATFORM_OPTIMIZATION_LDFLAGS_RELEASE = -O3 -s TOTAL_MEMORY=\$\(PLATFORM_EMSCRIPTEN_TOTAL_MEMORY\) -s WASM=1 -fPIC) -gsource-map',
        r'\1', s)

open(p, "w").write(s)
print("perf config applied to", p)
PY
