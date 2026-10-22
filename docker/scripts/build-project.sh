#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-project — compile one openFrameworks project to a web bundle.
#
# Contract:
#   IN   $INPUT_DIR  (default /work/input)   a project dir, or a dir containing
#                                            one (the unzipped upload). Must hold
#                                            src/ somewhere one level down.
#   OUT  $OUTPUT_DIR (default /work/output)  receives index.html/.js/.wasm/.data
#                                            + _headers + EMBED.html
#
# Exit codes:  0 ok · 2 rejected (disallowed addon / no src) · 1 build failed
# ---------------------------------------------------------------------------
set -euo pipefail

OF_ROOT="${OF_ROOT:-/opt/openFrameworks}"
INPUT_DIR="${INPUT_DIR:-/work/input}"
OUTPUT_DIR="${OUTPUT_DIR:-/work/output}"
PROJECT_NAME="${PROJECT_NAME:-studentapp}"           # deterministic on-disk name
ADDON_ALLOWLIST="${ADDON_ALLOWLIST:-ofxGui ofxEmscripten}"
GHPAGES="${GHPAGES:-1}"                               # 1 = make output GitHub-Pages ready
JOBS="$(nproc)"

# emsdk is on PATH via the base image; source defensively in case of overrides.
# shellcheck disable=SC1091
source /emsdk/emsdk_env.sh >/dev/null 2>&1 || true

say()  { printf '\033[1;36m[worker]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[worker] ERROR:\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }

# --- 1. Locate the project root (the dir that contains src/) ----------------
resolve_root() {
  if [ -d "$INPUT_DIR/src" ]; then echo "$INPUT_DIR"; return; fi
  # common case: upload unzipped to a single wrapper folder
  local kids=( "$INPUT_DIR"/*/ )
  if [ "${#kids[@]}" -eq 1 ] && [ -d "${kids[0]}src" ]; then
    echo "${kids[0]%/}"; return
  fi
  # otherwise search shallowly for the first src/ dir
  local hit
  hit="$(find "$INPUT_DIR" -maxdepth 3 -type d -name src -print -quit 2>/dev/null || true)"
  [ -n "$hit" ] && { dirname "$hit"; return; }
  return 1
}
PROJ_ROOT="$(resolve_root)" || fail "no openFrameworks project found under $INPUT_DIR (expected a src/ folder)" 2
say "project root: $PROJ_ROOT"

# --- 2. Validate addons against the allowlist -------------------------------
# membership test (no bash-4 associative arrays; works on any bash >= 3.2)
is_allowed() {
  local needle="$1" a
  for a in ${ADDON_ALLOWLIST//,/ }; do [ "$a" = "$needle" ] && return 0; done
  return 1
}

ADDONS_MAKE="$PROJ_ROOT/addons.make"
declared=()
if [ -f "$ADDONS_MAKE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                 # strip comments
    line="${line//$'\r'/}"             # strip CR
    line="$(echo "$line" | xargs || true)"   # trim whitespace
    [ -z "$line" ] && continue
    declared+=("$line")
  done < "$ADDONS_MAKE"
fi

bad=()
for a in "${declared[@]:-}"; do
  [ -z "$a" ] && continue
  is_allowed "$a" || bad+=("$a")
done
if [ "${#bad[@]}" -gt 0 ]; then
  {
    echo "This project uses addon(s) not supported by the web build:"
    for b in "${bad[@]}"; do echo "  - $b"; done
    echo
    echo "Supported addons: ${ADDON_ALLOWLIST}"
    echo "Remove the unsupported addon(s) from addons.make, or ask your instructor"
    echo "to add it to the allowlist if it is known to compile for the web."
  } >&2
  exit 2
fi
say "addons ok: ${declared[*]:-(none)}"

# --- 3. Stage into apps/myApps/<name> (the ../../.. paths require this) ------
DEST="$OF_ROOT/apps/myApps/$PROJECT_NAME"
rm -rf "$DEST"; mkdir -p "$DEST"
cp -a "$PROJ_ROOT"/. "$DEST"/

# If the upload was src-only, borrow the standard build files from the warmup.
for f in Makefile config.make; do
  [ -f "$DEST/$f" ] || cp "$OF_ROOT/apps/myApps/_warmup/$f" "$DEST/$f"
done
[ -f "$DEST/addons.make" ] || : > "$DEST/addons.make"

# --- 4. Apply the build guards (gotchas #3 and #4) --------------------------
mkdir -p "$DEST/bin/data"; [ -e "$DEST/bin/data/.keep" ] || : > "$DEST/bin/data/.keep"
cp -f /opt/em_shims.c "$DEST/src/em_shims.c"

# --- 5. Build for WASM (emmake + lowercase emscripten = gotchas #1 and #2) ---
say "compiling for emscripten ..."
cd "$DEST"
if ! emmake make -j"$JOBS" PLATFORM_OS=emscripten; then
  fail "compilation failed — see the log above" 1
fi

# --- 6. Collect the bundle --------------------------------------------------
SRC_OUT="$DEST/bin/em/$PROJECT_NAME"
[ -f "$SRC_OUT/index.html" ] || fail "build reported success but $SRC_OUT/index.html is missing" 1
mkdir -p "$OUTPUT_DIR"; rm -rf "${OUTPUT_DIR:?}"/*
# Copy the WHOLE bundle, including index.wasm.map — the build links with
# -sLOAD_SOURCE_MAP=1, so the runtime fetches + JSON-parses the map at startup.
# Dropping it 404s and aborts the app at "Preparing...". Keep it.
cp -a "$SRC_OUT"/. "$OUTPUT_DIR"/

# Cross-origin isolation headers for hosts that CAN set them (nginx/S3/Cloudflare).
cat > "$OUTPUT_DIR/_headers" <<'HDR'
/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
HDR

if [ "$GHPAGES" = "1" ]; then
  # GitHub Pages can't send COOP/COEP headers, so ship coi-serviceworker, which
  # supplies cross-origin isolation client-side. Inject it as the first <head>
  # script so it runs before the emscripten runtime. Also add .nojekyll.
  cp -f /opt/coi-serviceworker.js "$OUTPUT_DIR/coi-serviceworker.js"
  : > "$OUTPUT_DIR/.nojekyll"
  python3 - "$OUTPUT_DIR/index.html" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "coi-serviceworker.js" not in s:
    s = re.sub(r'(<head[^>]*>)', r'\1\n    <script src="coi-serviceworker.js"></script>', s, count=1)
    open(p, "w", encoding="utf-8").write(s)
PY
fi

cat > "$OUTPUT_DIR/EMBED.html" <<'EMB'
<!-- GitHub Pages: just embed the URL; coi-serviceworker handles isolation
     (first visit auto-reloads once). On a host that sets COOP/COEP headers
     (see _headers) you can delete coi-serviceworker.js and the injected tag. -->
<iframe src="index.html" width="1024" height="768" style="border:0" allow="fullscreen"></iframe>
EMB

say "done -> $OUTPUT_DIR"
( cd "$OUTPUT_DIR" && ls -la )
