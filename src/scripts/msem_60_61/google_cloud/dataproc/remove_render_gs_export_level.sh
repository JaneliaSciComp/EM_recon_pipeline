#!/bin/bash

# ----------------------------------------------------------------------------
# Removes one scale level of a render n5 export and everything under it, after confirmation.
#
# Usage: remove_render_gs_export_level.sh <raw stack> <s level>
#        remove_render_gs_export_level.sh --full-url <url>
#
# For example, w61-s071-r00 and s1 removes
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}/s1
#
# The --full-url form takes that same path (e.g. pasted from a list of levels to clean up).
# Its raw stack and s level are pulled back out and used to rebuild the url, which must
# match what was passed in, so a url that does not follow the export conventions is
# rejected instead of removed.

RENDER_EXP="gs://janelia-spark-test/hess_wafers_60_61_export/render"

# note that the exported dataset name uses three underscores before pixel
STACK_SUFFIX="_gc_bc_par_cc_asoi_3d___pixel"

ARG_FULL_URL=""
ARG_RAW_STACK=""
ARG_S_LEVEL=""

if (( $# != 2 )); then
  printf "\nUSAGE: %s <raw stack> <s level>
       %s --full-url <url>

  raw stack  dashed stack name, e.g. w61-s071-r00
  s level    scale level to remove, e.g. s1
  url        full level url, e.g.
             %s/w61_serial_070_to_079/w61_s071_r00%s/s1

" "$(basename "$0")" "$(basename "$0")" "${RENDER_EXP}" "${STACK_SUFFIX}"
  exit 1
fi

if [ "$1" = "--full-url" ]; then

  # a trailing slash would make the rebuilt url differ from the one passed in
  ARG_FULL_URL="${2%/}"

  # split <...>/<stack><suffix>/<level> into its raw stack and s level
  ARG_S_LEVEL="${ARG_FULL_URL##*/}"
  DATASET_NAME="${ARG_FULL_URL%/*}"
  DATASET_NAME="${DATASET_NAME##*/}"
  UNDERSCORE_STACK="${DATASET_NAME%"${STACK_SUFFIX}"}"

  if [ "${UNDERSCORE_STACK}" = "${DATASET_NAME}" ]; then
    printf "\nExiting, --full-url dataset '%s' does not end with %s\n\n" \
           "${DATASET_NAME}" "${STACK_SUFFIX}"
    exit 1
  fi

  ARG_RAW_STACK="${UNDERSCORE_STACK//_/-}"

else

  ARG_RAW_STACK="$1"
  ARG_S_LEVEL="$2"

fi

# ----------------------------------------------------------------------------
# Validate and derive the dataset level url

if [[ ! "${ARG_RAW_STACK}" =~ ^(w[0-9]+)-s([0-9]+)-r[0-9]+$ ]]; then
  printf "\nExiting, raw stack '%s' is not <wafer>-s<serial>-r<region>\n\n" "${ARG_RAW_STACK}"
  exit 1
fi

WAFER="${BASH_REMATCH[1]}"
# force base 10 so that a zero padded serial (e.g. 071) is not treated as octal
SERIAL_NUMBER=$(( 10#${BASH_REMATCH[2]} ))
FIRST_PROJECT_SERIAL=$(( (SERIAL_NUMBER / 10) * 10 ))

# s0 is excluded because it is the full scale data that reruns start from
if [[ ! "${ARG_S_LEVEL}" =~ ^s[0-9]+$ ]] || [ "${ARG_S_LEVEL}" = "s0" ]; then
  printf "\nExiting, s level '%s' must be s1 or higher\n\n" "${ARG_S_LEVEL}"
  exit 1
fi

LEVEL_URL=$(printf '%s/%s_serial_%03d_to_%03d/%s%s/%s' \
                   "${RENDER_EXP}" \
                   "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )) \
                   "${ARG_RAW_STACK//-/_}" "${STACK_SUFFIX}" \
                   "${ARG_S_LEVEL}")

# The rebuilt url has to match the one that was passed in, otherwise the url refers to
# something other than a standard render export level and should not be removed here.
if [ -n "${ARG_FULL_URL}" ] && [ "${LEVEL_URL}" != "${ARG_FULL_URL}" ]; then
  printf "\nExiting, --full-url does not match the url built from its stack and level:
    --full-url: %s
       derived: %s\n\n" "${ARG_FULL_URL}" "${LEVEL_URL}"
  exit 1
fi

# ----------------------------------------------------------------------------
# Confirm and remove

printf "\nchecking %s ...\n" "${LEVEL_URL}"

OBJECT_COUNT=$(gcloud storage ls --recursive "${LEVEL_URL}/**" 2>/dev/null | wc -l | tr -d ' ')

if (( OBJECT_COUNT == 0 )); then
  printf "\nExiting, %s has no objects (it may have been removed already)\n\n" "${LEVEL_URL}"
  exit 1
fi

printf "
%s contains %s object(s).

Removing it cannot be undone.
" "${LEVEL_URL}" "${OBJECT_COUNT}"

echo
read -rp "Do you want to remove it? (y/n): " CONFIRM

if [[ ! ${CONFIRM} =~ ^[Yy]$ ]]; then
  printf "\nnothing was removed\n\n"
  exit 0
fi

printf "\nremoving %s ...\n" "${LEVEL_URL}"

gcloud storage rm --recursive --no-user-output-enabled "${LEVEL_URL}"

printf "\nremoved %s object(s) from %s\n\n" "${OBJECT_COUNT}" "${LEVEL_URL}"
