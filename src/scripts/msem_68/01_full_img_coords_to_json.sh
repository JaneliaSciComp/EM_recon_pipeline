#!/bin/bash

set -euo pipefail

# Defaults
SAMPLE_NUMBER="68"
ROOT="/nrs/hess/Hayworth/DATA"
OUT_JSON=""
RES_X="8.0"
RES_Y="8.0"
RES_Z="24.0"
VERBOSE=1

usage() {
  cat >&2 <<EOF
Usage: $0 [options]

Options:
  -s, --sample <n>     Sample number (default: 68)
  -r, --root <dir>     Root directory (default: /nrs/hess/Hayworth/DATA)
  -o, --out <file>     Output JSON file (default: sample_<sample>_image_coord.json)
      --res-x <val>    Resolution X (default: 8.0)
      --res-y <val>    Resolution Y (default: 8.0)
  -z, --res-z <val>    Resolution Z (default: 24.0)
  -q, --quiet          Disable progress/timing logs
  -v, --verbose        Enable progress/timing logs (default)
  -h, --help           Show help
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--sample)
      SAMPLE_NUMBER="${2:-}"; shift 2;;
    -r|--root)
      ROOT="${2:-}"; shift 2;;
    -o|--out)
      OUT_JSON="${2:-}"; shift 2;;
    --res-x)
      RES_X="${2:-}"; shift 2;;
    --res-y)
      RES_Y="${2:-}"; shift 2;;
    -z|--res-z)
      RES_Z="${2:-}"; shift 2;;
    -q|--quiet)
      VERBOSE=0; shift;;
    -v|--verbose)
      VERBOSE=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2;;
  esac
done

if [[ -z "$OUT_JSON" ]]; then
  OUT_JSON="sample_${SAMPLE_NUMBER}_image_coord.json"
fi

OWNER="hess_sample_${SAMPLE_NUMBER}"
PROJECT="w${SAMPLE_NUMBER}_serial_000_to_009"
STACK="w${SAMPLE_NUMBER}_s000_r00"

RENDER_HOST="em-services-1.int.janelia.org"

log() {
  (( VERBOSE == 1 )) && echo "$@" >&2
}

log "Searching (fast glob) for $ROOT/scan*/mFOVs/full_image_coordinates.txt ..."

shopt -s nullglob
COORD_FILES=( "$ROOT"/scan*/mFOVs/full_image_coordinates.txt )
shopt -u nullglob

# Optional: sort them (lexicographic)
mapfile -t COORD_FILES < <(printf '%s\n' "${COORD_FILES[@]}" | sort)

if (( ${#COORD_FILES[@]} == 0 )); then
  echo "No */mFOVs/full_image_coordinates.txt files found under: $ROOT" >&2
  exit 1
fi

TOTAL=${#COORD_FILES[@]}
log "Found $TOTAL coordinate files under: $ROOT"
log "Writing JSON to: $OUT_JSON"

# Write JSON
{
  echo '{'
  printf '  "root_directory": "%s",\n' "${ROOT//\"/\\\"}"
  printf '  "owner": "%s",\n' "${OWNER//\"/\\\"}"
  printf '  "project": "%s",\n' "${PROJECT//\"/\\\"}"
  printf '  "stack": "%s",\n' "${STACK//\"/\\\"}"
  printf '  "render_host": "%s",\n' "$RENDER_HOST"
  printf '  "resolution_x": %s,\n' "$RES_X"
  printf '  "resolution_y": %s,\n' "$RES_Y"
  printf '  "resolution_z": %s,\n' "$RES_Z"
  echo '  "sfov_info_list": ['

  # Emit sfov_info_list elements quickly in a single awk pass.
  # - Prints commas after each element except the last.
  # - Logs per-file processing to stderr (only if VERBOSE=1).
  awk -v ROOT="$ROOT" -v VERBOSE="$VERBOSE" '
    function vlog(msg) { if (VERBOSE == 1) print msg > "/dev/stderr" }

    BEGIN { prev = "" }

    FNR == 1 {
      fname = FILENAME
      sub("^" ROOT "/", "", fname)
      scan_rel = fname
      sub("/mFOVs/full_image_coordinates.txt$", "", scan_rel)
      mfovs_rel = scan_rel "/mFOVs"

      nfiles = ARGC - 1
      if (ARGIND == 1 || ARGIND % 20 == 0 || ARGIND == nfiles) {
        vlog("[" ARGIND "/" nfiles "] Processing: " FILENAME)
      }
    }

    NF >= 3 {
      rel = $1; x = $2; y = $3
      sub(/\r$/, "", rel); sub(/\r$/, "", x); sub(/\r$/, "", y)

      gsub(/\\/, "/", rel)
      split(rel, a, "/")
      if (length(a) < 2) next

      path = mfovs_rel "/" a[1] "/" a[2]

      gsub(/\\/, "\\\\", path)
      gsub(/"/, "\\\"", path)

      line = sprintf("    { \"path\": \"%s\", \"x\": %s, \"y\": %s }", path, x, y)

      if (prev != "") print prev ","
      prev = line
    }

    END {
      if (prev != "") print prev
    }
  ' "${COORD_FILES[@]}"

  echo '  ]'
  echo '}'
} > "$OUT_JSON"

echo "
Wrote: $OUT_JSON that starts like this:
"

head -n20 "$OUT_JSON"

echo