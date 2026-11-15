#!/bin/bash

# ----------------------------------------------------------------------------
# Searches a pixel export for a block that was written after a specified time but has no saved
# original in the matching no paint group, and prints the first one found.
#
# The inpainter (Wafer6061Inpainter) saves each original block to <pixel group>_no_paint before
# it overwrites the block in <pixel group>, and undo_inpainting.sh copies those originals back.
# A pixel block written after the cutoff without a no paint copy therefore cannot be restored by
# undo_inpainting.sh, so the pixel volume may need to be regenerated.
#
# NOTE: in the s1 and higher pyramid levels, the inpainter also creates blocks where none
#       existed before (there is no original to save for those), so a hit in those levels may
#       be one of these.  Those levels can also be rebuilt from s0 by downsampling.
#
# Only block objects are checked: attributes.json files and directory marker objects are skipped.
#
# Exit codes:  0 = no unsaved block found,  1 = error,  2 = an unsaved block was found

# keep this in sync with InpaintParameters.noPaintDatasetSuffix
NO_PAINT_SUFFIX="_no_paint"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_NO_PAINT_URL=""
ARG_MODIFIED_AFTER=""

usage() {
  echo "
USAGE $(basename "$0") --no-paint-url <url> --modified-after <UTC time>

  --no-paint-url    no paint group of the pixel export to check, e.g.
                      gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___pixel_no_paint
                    (the pixel group checked is the same url without ${NO_PAINT_SUFFIX})
  --modified-after  UTC cutoff time as YYYY-MM-DDTHH:MM:SSZ, e.g. 2026-11-15T18:45:00Z for 1:45 pm EST
                    (EST is UTC-5, EDT is UTC-4)

Prints the first block in the pixel group that was written after the cutoff and has no copy
at the same path in the no paint group.

Example:
  $(basename "$0") \\
    --no-paint-url gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___pixel_no_paint \\
    --modified-after 2026-11-15T18:45:00Z
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --no-paint-url)
      ARG_NO_PAINT_URL="${2:?'--no-paint-url requires a value'}"
      shift 2
      ;;
    --modified-after)
      ARG_MODIFIED_AFTER="${2:?'--modified-after requires a value'}"
      shift 2
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

# a trailing slash (e.g. from tab completion) is harmless, so drop it
NO_PAINT_URL="${ARG_NO_PAINT_URL%/}"

if [[ ! "${NO_PAINT_URL}" =~ ^gs://.+___pixel${NO_PAINT_SUFFIX}$ ]]; then
  echo "ERROR: --no-paint-url must be a gs:// url ending with ___pixel${NO_PAINT_SUFFIX} (not '${ARG_NO_PAINT_URL}')"
  exit 1
fi

# GNU and BSD (macOS) date parse times differently, so the cutoff is required in the same UTC
# format that gcloud storage ls --long prints, which lets the times be compared as strings
if [[ ! "${ARG_MODIFIED_AFTER}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "ERROR: --modified-after must be a UTC time like 2026-11-15T18:45:00Z (not '${ARG_MODIFIED_AFTER}')"
  exit 1
fi

PIXEL_URL="${NO_PAINT_URL%"${NO_PAINT_SUFFIX}"}"

if ! gcloud storage ls "${PIXEL_URL}/" 2>/dev/null | grep -q .; then
  echo "ERROR: ${PIXEL_URL} does not exist"
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

# ----------------------------------------------------------------------------
# List the saved originals as paths relative to the no paint group (e.g. s0/12/7/0)

NO_PAINT_LIST="${WORK_DIR}/no_paint.txt"

printf "\nlisting saved originals in %s ...\n" "${NO_PAINT_URL}"

gcloud storage ls --recursive "${NO_PAINT_URL}/**" 2>/dev/null |
  awk -v prefix="${NO_PAINT_URL}/" 'index($0, prefix) == 1 && $0 !~ /\/$/ { print substr($0, length(prefix) + 1) }' \
  > "${NO_PAINT_LIST}"

NO_PAINT_COUNT=$(grep -E -c -v '(^|/)attributes\.json$' "${NO_PAINT_LIST}" | tr -d ' ')

if (( NO_PAINT_COUNT == 0 )); then
  printf "  WARNING: no saved original blocks found, so every block written after the cutoff will be reported\n"
else
  printf "  found %d saved original block(s)\n" "${NO_PAINT_COUNT}"
fi

# ----------------------------------------------------------------------------
# Stream the pixel group listing and stop at the first unsaved block written after the cutoff
#
# gcloud storage ls --long lines look like
#   <size>  <YYYY-MM-DDTHH:MM:SSZ>  <url>
# so the time is field 2 and the url is field 3 (the TOTAL line and directory markers are skipped).
# awk exits as soon as it finds a block, which also stops the listing.

RESULT_FILE="${WORK_DIR}/result.txt"

printf "\nsearching %s\nfor blocks written after %s without a saved original (this can take a while) ...\n" \
       "${PIXEL_URL}" "${ARG_MODIFIED_AFTER}"

gcloud storage ls --long --recursive "${PIXEL_URL}/**" 2>/dev/null |
  awk -v prefix="${PIXEL_URL}/" -v cutoff="${ARG_MODIFIED_AFTER}" -v result_file="${RESULT_FILE}" '
    # load the saved original paths from the first file
    NR == FNR { saved[$0] = 1; next }

    $3 !~ /^gs:\/\// || $2 !~ /^[0-9][0-9][0-9][0-9]-/ || index($3, prefix) != 1 { next }

    {
      path = substr($3, length(prefix) + 1)
      if (path ~ /\/$/ || path ~ /(^|\/)attributes\.json$/) { next }

      checked++
      if (checked % 20000 == 0) {
        printf "  checked %d blocks, %d written after the cutoff so far ...\n", checked, modified > "/dev/stderr"
      }

      if ($2 > cutoff) {
        modified++
        if (! (path in saved)) {
          printf "FOUND %s %s\n", $2, $3 > result_file
          found = 1
          exit
        }
      }
    }

    END {
      if (! found) {
        printf "DONE %d %d\n", checked, modified > result_file
      }
    }
  ' "${NO_PAINT_LIST}" -

LISTING_STATUS=${PIPESTATUS[0]}

# ----------------------------------------------------------------------------
# Report

if [ ! -s "${RESULT_FILE}" ]; then
  printf "\nERROR: the search did not finish (gcloud storage ls exit code %s)\n\n" "${LISTING_STATUS}"
  exit 1
fi

read -r RESULT_TYPE RESULT_A RESULT_B < "${RESULT_FILE}"

if [ "${RESULT_TYPE}" = "FOUND" ]; then
  printf "
FOUND a block written at %s (after %s) with no saved original:
  %s

It is not in %s,
so undo_inpainting.sh cannot restore it.

" "${RESULT_A}" "${ARG_MODIFIED_AFTER}" "${RESULT_B}" "${NO_PAINT_URL}"
  exit 2
fi

printf "
no unsaved blocks found: checked %d block(s), %d written after %s, and every one of those has a saved original in
  %s

" "${RESULT_A}" "${RESULT_B}" "${ARG_MODIFIED_AFTER}" "${NO_PAINT_URL}"
