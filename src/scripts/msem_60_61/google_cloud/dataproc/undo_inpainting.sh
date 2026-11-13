#!/bin/bash

# ----------------------------------------------------------------------------
# Undoes the inpainting of one render n5 export, after confirmation:
#   1. copies the original blocks saved in the <pixel group>_no_paint levels back over the
#      inpainted blocks in the matching <pixel group> levels,
#   2. removes the inpaint completion attribute from the pixel group (so a later inpaint run
#      does not skip the stack), and
#   3. removes the <pixel group>_no_paint group.
#
# Usage: undo_inpainting.sh <raw stack>
#        undo_inpainting.sh --full-url <url>
#
# For example, w61-s071-r00 restores
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}
# from
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}${NO_PAINT_SUFFIX}
#
# The --full-url form takes that same pixel group path (e.g. pasted from a list of exports).
# Its raw stack is pulled back out and used to rebuild the url, which must match what was
# passed in, so a url that does not follow the export conventions is rejected.
#
# Only the block objects of each level (its numeric sN/<x>/... prefixes) are copied.
# A no paint level's attributes.json only has the basic dataset attributes, so copying it
# would replace the pixel level's attributes.json and drop its other metadata.

RENDER_EXP="gs://janelia-spark-test/hess_wafers_60_61_export/render"

# note that the exported dataset name uses three underscores before pixel
STACK_SUFFIX="_gc_bc_par_cc_aso_3d_s3i___pixel"

# keep this in sync with InpaintParameters.noPaintDatasetSuffix and Wafer6061Inpainter.INPAINT_ATTRIBUTE
NO_PAINT_SUFFIX="_no_paint"
INPAINT_ATTRIBUTE="inpaint"

ARG_FULL_URL=""
ARG_RAW_STACK=""

if (( $# == 1 )) && [ "$1" != "--full-url" ]; then

  ARG_RAW_STACK="$1"

elif (( $# == 2 )) && [ "$1" = "--full-url" ]; then

  # a trailing slash would make the rebuilt url differ from the one passed in
  ARG_FULL_URL="${2%/}"

  # split <...>/<stack><suffix> into its raw stack
  DATASET_NAME="${ARG_FULL_URL##*/}"
  UNDERSCORE_STACK="${DATASET_NAME%"${STACK_SUFFIX}"}"

  if [ "${UNDERSCORE_STACK}" = "${DATASET_NAME}" ]; then
    printf "\nExiting, --full-url dataset '%s' does not end with %s\n\n" \
           "${DATASET_NAME}" "${STACK_SUFFIX}"
    exit 1
  fi

  ARG_RAW_STACK="${UNDERSCORE_STACK//_/-}"

else

  printf "\nUSAGE: %s <raw stack>
       %s --full-url <url>

  raw stack  dashed stack name, e.g. w61-s071-r00
  url        full pixel group url, e.g.
             %s/w61_serial_070_to_079/w61_s071_r00%s

" "$(basename "$0")" "$(basename "$0")" "${RENDER_EXP}" "${STACK_SUFFIX}"
  exit 1

fi

# ----------------------------------------------------------------------------
# Validate and derive the pixel and no paint group urls

if [[ ! "${ARG_RAW_STACK}" =~ ^(w[0-9]+)-s([0-9]+)-r[0-9]+$ ]]; then
  printf "\nExiting, raw stack '%s' is not <wafer>-s<serial>-r<region>\n\n" "${ARG_RAW_STACK}"
  exit 1
fi

WAFER="${BASH_REMATCH[1]}"
# force base 10 so that a zero padded serial (e.g. 071) is not treated as octal
SERIAL_NUMBER=$(( 10#${BASH_REMATCH[2]} ))
FIRST_PROJECT_SERIAL=$(( (SERIAL_NUMBER / 10) * 10 ))

PIXEL_URL=$(printf '%s/%s_serial_%03d_to_%03d/%s%s' \
                   "${RENDER_EXP}" \
                   "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )) \
                   "${ARG_RAW_STACK//-/_}" "${STACK_SUFFIX}")

# The rebuilt url has to match the one that was passed in, otherwise the url refers to
# something other than a standard render pixel export and should not be changed here.
if [ -n "${ARG_FULL_URL}" ] && [ "${PIXEL_URL}" != "${ARG_FULL_URL}" ]; then
  printf "\nExiting, --full-url does not match the url built from its stack:
    --full-url: %s
       derived: %s\n\n" "${ARG_FULL_URL}" "${PIXEL_URL}"
  exit 1
fi

NO_PAINT_URL="${PIXEL_URL}${NO_PAINT_SUFFIX}"

# ----------------------------------------------------------------------------
# Find the saved original blocks for each level

printf "\nchecking %s ...\n" "${NO_PAINT_URL}"

# levels are listed as <url>/sN/, so keep just the sN part (sorted numerically)
NO_PAINT_LEVELS=$(gcloud storage ls "${NO_PAINT_URL}/" 2>/dev/null |
                  sed -n 's#.*/\(s[0-9][0-9]*\)/$#\1#p' |
                  sort -t s -k 2 -n)

if [ -z "${NO_PAINT_LEVELS}" ]; then
  printf "\nExiting, %s has no levels (the stack may not be inpainted or may already be undone)\n\n" \
         "${NO_PAINT_URL}"
  exit 1
fi

LEVELS_TO_COPY=()
LEVEL_SUMMARY=""
TOTAL_BLOCK_COUNT=0
for LEVEL in ${NO_PAINT_LEVELS}; do
  # skip the level's attributes.json and any directory marker objects (names ending with /)
  BLOCK_COUNT=$(gcloud storage ls --recursive "${NO_PAINT_URL}/${LEVEL}/**" 2>/dev/null |
                grep -v -e '/attributes\.json$' -e '/$' | wc -l | tr -d ' ')
  LEVEL_SUMMARY="${LEVEL_SUMMARY}  ${LEVEL}: ${BLOCK_COUNT} original block(s)
"
  if (( BLOCK_COUNT > 0 )); then
    LEVELS_TO_COPY+=("${LEVEL}")
    TOTAL_BLOCK_COUNT=$(( TOTAL_BLOCK_COUNT + BLOCK_COUNT ))
  fi
done

# ----------------------------------------------------------------------------
# Read the pixel group attributes (needed to remove the inpaint attribute)

PIXEL_ATTRIBUTES_URL="${PIXEL_URL}/attributes.json"

if ! PIXEL_ATTRIBUTES=$(gcloud storage cat "${PIXEL_ATTRIBUTES_URL}" 2>/dev/null); then
  printf "\nExiting, could not read %s\n\n" "${PIXEL_ATTRIBUTES_URL}"
  exit 1
fi

INPAINT_SUMMARY=$(printf '%s' "${PIXEL_ATTRIBUTES}" |
                  jq -c --arg a "${INPAINT_ATTRIBUTE}" \
                     'if has($a) then .[$a] | del(.inpaintedLocations) else "none" end' 2>/dev/null)

if [ -z "${INPAINT_SUMMARY}" ]; then
  printf "\nExiting, could not parse %s\n\n" "${PIXEL_ATTRIBUTES_URL}"
  exit 1
fi

# ----------------------------------------------------------------------------
# Confirm

printf "
%s has:
%s
%s %s attribute (without its locations):
  %s

Undoing the inpainting will:
  1. copy the %d original block(s) back into the matching %s levels,
  2. remove the %s attribute from %s, and
  3. remove %s.

The inpainted blocks are overwritten, so this cannot be undone.
" "${NO_PAINT_URL}" "${LEVEL_SUMMARY}" \
  "${PIXEL_URL}" "${INPAINT_ATTRIBUTE}" "${INPAINT_SUMMARY}" \
  "${TOTAL_BLOCK_COUNT}" "${PIXEL_URL}" \
  "${INPAINT_ATTRIBUTE}" "${PIXEL_ATTRIBUTES_URL}" \
  "${NO_PAINT_URL}"

echo
read -rp "Do you want to undo the inpainting? (y/n): " CONFIRM

if [[ ! ${CONFIRM} =~ ^[Yy]$ ]]; then
  printf "\nnothing was changed\n\n"
  exit 0
fi

# ----------------------------------------------------------------------------
# 1. Copy the original blocks back
#
# The [0-9]* wildcard matches only the numeric <x> block prefixes of a level (not its
# attributes.json), and --recursive copies everything under each of them to the same
# relative path in the pixel level.

for LEVEL in "${LEVELS_TO_COPY[@]}"; do
  printf "\ncopying %s/%s original blocks to %s/%s ...\n" "${NO_PAINT_URL}" "${LEVEL}" "${PIXEL_URL}" "${LEVEL}"
  if ! gcloud storage cp --recursive --no-user-output-enabled \
         "${NO_PAINT_URL}/${LEVEL}/[0-9]*" "${PIXEL_URL}/${LEVEL}/"; then
    printf "\nExiting, copy failed for %s.
Nothing else was changed, so it is safe to rerun this script.\n\n" "${LEVEL}"
    exit 1
  fi
done

# ----------------------------------------------------------------------------
# 2. Remove the inpaint attribute

if [ "${INPAINT_SUMMARY}" = '"none"' ]; then
  printf "\n%s has no %s attribute to remove\n" "${PIXEL_ATTRIBUTES_URL}" "${INPAINT_ATTRIBUTE}"
else
  UPDATED_ATTRIBUTES_FILE=$(mktemp)
  trap 'rm -f "${UPDATED_ATTRIBUTES_FILE}"' EXIT

  printf '%s' "${PIXEL_ATTRIBUTES}" | jq -c --arg a "${INPAINT_ATTRIBUTE}" 'del(.[$a])' > "${UPDATED_ATTRIBUTES_FILE}"

  printf "\nremoving the %s attribute from %s ...\n" "${INPAINT_ATTRIBUTE}" "${PIXEL_ATTRIBUTES_URL}"
  if ! gcloud storage cp --no-user-output-enabled "${UPDATED_ATTRIBUTES_FILE}" "${PIXEL_ATTRIBUTES_URL}"; then
    printf "\nExiting, could not update %s.
The original blocks were restored, but %s was kept so this script can be rerun.\n\n" \
           "${PIXEL_ATTRIBUTES_URL}" "${NO_PAINT_URL}"
    exit 1
  fi
fi

# ----------------------------------------------------------------------------
# 3. Remove the no paint group

printf "\nremoving %s ...\n" "${NO_PAINT_URL}"

if ! gcloud storage rm --recursive --no-user-output-enabled "${NO_PAINT_URL}"; then
  printf "\nExiting, could not remove %s (the inpainting was otherwise undone)\n\n" "${NO_PAINT_URL}"
  exit 1
fi

printf "\nrestored %d original block(s) to %s\n\n" "${TOTAL_BLOCK_COUNT}" "${PIXEL_URL}"
