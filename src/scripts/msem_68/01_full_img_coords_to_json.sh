#!/bin/bash

set -euo pipefail

SAMPLE_NUMBER="${1:-68}"
ROOT="${2:-/nrs/hess/Hayworth/DATA}"
OUT_JSON="${3:-sample_${SAMPLE_NUMBER}_image_coord.json}"
RES_Z="${4:-8.0}"

OWNER="hess_sample_${SAMPLE_NUMBER}"
PROJECT="w${SAMPLE_NUMBER}_serial_000_to_009"
STACK="w${SAMPLE_NUMBER}_s000_r00"

RENDER_HOST="em-services-1.int.janelia.org"
RES_X="8.0"
RES_Y="8.0"

# Find all coordinate files
mapfile -t COORD_FILES < <(find "$ROOT" -type f -path "*/mFOVs/full_image_coordinates.txt" | sort)

if (( ${#COORD_FILES[@]} == 0 )); then
  echo "No */mFOVs/full_image_coordinates.txt files found under: $ROOT" >&2
  exit 1
fi

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

  first=1

  for coord_file in "${COORD_FILES[@]}"; do
    # coord_file: .../scan_000009/mFOVs/full_image_coordinates.txt
    scan_dir="$(dirname "$(dirname "$coord_file")")"   # .../scan_000009
    scan_rel="${scan_dir#"$ROOT"/}"                    # scan_000009
    mfovs_rel="$scan_rel/mFOVs"                        # scan_000009/mFOVs

    awk -v mfovs_rel="$mfovs_rel" '
      BEGIN { OFS="\t" }
      NF >= 3 {
        rel = $1
        x   = $2
        y   = $3

        sub(/\r$/, "", rel); sub(/\r$/, "", x); sub(/\r$/, "", y)

        # Convert backslashes to forward slashes
        gsub(/\\/, "/", rel)

        # rel: mFOV_0032/sfov_082.png
        split(rel, a, "/")
        if (length(a) < 2) next

        mfov = a[1]
        sfov = a[2]

        path = mfovs_rel "/" mfov "/" sfov
        print path, x, y
      }
    ' "$coord_file" | while IFS=$'\t' read -r path x y; do
      # JSON-escape path
      esc_path=${path//\\/\\\\}
      esc_path=${esc_path//\"/\\\"}

      if (( first == 1 )); then
        first=0
      else
        echo '    ,'
      fi

      printf '    { "path": "%s", "x": %s, "y": %s }\n' "$esc_path" "$x" "$y"
    done
  done

  echo '  ]'
  echo '}'
} > "$OUT_JSON"

echo "Wrote: $OUT_JSON"
echo "Sample: $SAMPLE_NUMBER  Owner: $OWNER  Project: $PROJECT  Stack: $STACK"
echo "Coordinate files processed: ${#COORD_FILES[@]}"
