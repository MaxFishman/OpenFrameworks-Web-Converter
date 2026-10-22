#!/usr/bin/env bash
# Convenience wrapper: build ONE project dir into ./out using the worker image,
# with a sane security sandbox. For production, call the container from your
# queue worker instead (see README.md "Wiring it into an uploader").
#
# Usage:  ./run.sh /path/to/openframeworks/project   [output_dir]
set -euo pipefail

PROJECT="${1:?usage: run.sh <project_dir> [out_dir]}"
OUT="${2:-$PWD/out}"
IMAGE="${IMAGE:-of-web-worker}"
TIMEOUT="${TIMEOUT:-600}"            # hard wall-clock cap (seconds)
PLATFORM="${PLATFORM:-linux/amd64}"  # base image is amd64-only

mkdir -p "$OUT"
project_abs="$(cd "$PROJECT" && pwd)"
out_abs="$(cd "$OUT" && pwd)"

# `timeout` on macOS = gtimeout (coreutils); fall back to no timeout if absent.
TO=(); command -v timeout >/dev/null && TO=(timeout "$TIMEOUT")
command -v gtimeout >/dev/null && TO=(gtimeout "$TIMEOUT")

exec "${TO[@]}" docker run --rm \
  --platform "$PLATFORM" \
  --network none \
  --cpus "${CPUS:-2}" --memory "${MEMORY:-2g}" --pids-limit "${PIDS:-256}" \
  --security-opt no-new-privileges --cap-drop ALL \
  -v "$project_abs":/work/input:ro \
  -v "$out_abs":/work/output \
  "$IMAGE"
