#!/bin/bash

# ----------------------------------------------------------------------------
# Removes one scale level of a render n5 export, or the entire export (all scale levels),
# and everything under it, after confirmation.
#
# For example, --stack w61-s071-r00 --level s1 removes
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}/s1
# and --stack w61-s071-r00 --all-levels removes
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}
#
# The --full-url form takes one of those same paths (e.g. pasted from a list to clean up).
# Its raw stack (and s level) are pulled back out and used to rebuild the url, which must
# match what was passed in, so a url that does not follow the export conventions is
# rejected instead of removed.
#
# --full-url also accepts other export variants (e.g. ..._aso_3d_s3i___pixel_no_paint)
# and mask exports (e.g. ..._aso_3d_s3i___mask_20261114-203929), whose dataset suffix is
# kept when the url is rebuilt.

RENDER_EXP="gs://janelia-spark-test/hess_wafers_60_61_export/render"

# note that the exported dataset name uses three underscores before pixel
STACK_SUFFIX="_gc_bc_par_cc_asoi_3d___pixel"

# --full-url also accepts other export variants, e.g.
#   w61_s079_r01_gc_bc_par_cc_aso_3d_s3i___pixel_no_paint
#   w61_s077_r01_gc_bc_par_cc_aso___pixel_20261110-132805
#   w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___mask_20261114-203929
# so its dataset name only needs to be <wafer>_s<serial>_r<region>_<variant>___<pixel|mask><optional suffix>
# (the optional suffix may also contain dashes, e.g. a date-time stamp)
DATASET_MARKER_PATTERN="___(pixel|mask)"
DATASET_MARKER_DESCRIPTION="___<pixel|mask>"
DATASET_NAME_PATTERN="^(w[0-9]+_s[0-9]+_r[0-9]+)(_[A-Za-z0-9_]*${DATASET_MARKER_PATTERN}[A-Za-z0-9_-]*)$"

# the stack suffix used to build the url, replaced by the one in --full-url when it is used
DATASET_SUFFIX="${STACK_SUFFIX}"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_FULL_URL=""
ARG_RAW_STACK=""
ARG_S_LEVEL=""
ARG_ALL_LEVELS="false"
ARG_SKIP_CONFIRM="false"

usage() {
  echo "
USAGE: $(basename "$0") --stack <raw stack> --level <s level>
       $(basename "$0") --stack <raw stack> --all-levels
       $(basename "$0") --full-url <level url>
       $(basename "$0") --full-url <export url> --all-levels
       (add --skip-confirm to any of these to remove without asking)

  --stack         dashed stack name, e.g. w61-s071-r00
  --level         scale level to remove, s1 or higher, e.g. s1
  --all-levels    remove the entire export (every scale level, including s0)
  --full-url      full level or export url, e.g.
                    ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}/s1
                    ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}
                    ${RENDER_EXP}/w61_serial_070_to_079/w61_s079_r01_gc_bc_par_cc_aso_3d_s3i___pixel_no_paint
                    ${RENDER_EXP}/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___mask_20261114-203929
                  other export variants (<stack>_<variant>___<pixel|mask><optional suffix>) are only
                  accepted here, --stack always uses the ${STACK_SUFFIX} suffix
                  an export url must be combined with --all-levels
  --skip-confirm  remove without asking first (e.g. for scripted cleanup), can be added to any form

Exactly one of --stack or --full-url is required, and --level is only used with --stack.
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --stack)
      ARG_RAW_STACK="${2:?'--stack requires a value'}"
      shift 2
      ;;
    --level)
      ARG_S_LEVEL="${2:?'--level requires a value'}"
      shift 2
      ;;
    --all-levels)
      ARG_ALL_LEVELS="true"
      shift
      ;;
    --skip-confirm)
      ARG_SKIP_CONFIRM="true"
      shift
      ;;
    --full-url)
      # a trailing slash would make the rebuilt url differ from the one passed in
      ARG_FULL_URL="${2:?'--full-url requires a value'}"
      ARG_FULL_URL="${ARG_FULL_URL%/}"
      shift 2
      ;;
    *)
      printf "\nERROR: unrecognized parameter '%s'\n" "${1}"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Check parameter combinations

if [ -n "${ARG_FULL_URL}" ]; then

  if [ -n "${ARG_RAW_STACK}" ] || [ -n "${ARG_S_LEVEL}" ]; then
    printf "\nExiting, --full-url cannot be combined with --stack or --level\n\n"
    exit 1
  fi

  # split <...>/<stack><suffix>[/<level>] into its raw stack, dataset suffix, and s level
  if [ "${ARG_ALL_LEVELS}" = "true" ]; then
    DATASET_NAME="${ARG_FULL_URL##*/}"
  else
    ARG_S_LEVEL="${ARG_FULL_URL##*/}"
    DATASET_NAME="${ARG_FULL_URL%/*}"
    DATASET_NAME="${DATASET_NAME##*/}"
  fi

  if [[ ! "${DATASET_NAME}" =~ ${DATASET_NAME_PATTERN} ]]; then
    if [ "${ARG_ALL_LEVELS}" = "true" ]; then
      printf "\nExiting, --full-url with --all-levels must end with an export dataset like %s, not '%s'\n\n" \
             "w61_s071_r00${STACK_SUFFIX}" "${DATASET_NAME}"
    elif [[ "${ARG_FULL_URL##*/}" =~ ${DATASET_NAME_PATTERN} ]]; then
      printf "\nExiting, --full-url is an entire export, add --all-levels to remove all of it\n\n"
    else
      printf "\nExiting, --full-url dataset '%s' is not <wafer>_s<serial>_r<region>_<variant>%s<optional suffix>\n\n" \
             "${DATASET_NAME}" "${DATASET_MARKER_DESCRIPTION}"
    fi
    exit 1
  fi

  ARG_RAW_STACK="${BASH_REMATCH[1]//_/-}"
  DATASET_SUFFIX="${BASH_REMATCH[2]}"

else

  if [ -z "${ARG_RAW_STACK}" ]; then
    printf "\nERROR: --stack or --full-url is required\n"
    usage
  fi

  if [ "${ARG_ALL_LEVELS}" = "true" ] && [ -n "${ARG_S_LEVEL}" ]; then
    printf "\nExiting, use either --level or --all-levels, not both\n\n"
    exit 1
  fi

  if [ "${ARG_ALL_LEVELS}" = "false" ] && [ -z "${ARG_S_LEVEL}" ]; then
    printf "\nERROR: --stack requires --level or --all-levels\n"
    usage
  fi

fi

# ----------------------------------------------------------------------------
# Validate and derive the url to remove

if [[ ! "${ARG_RAW_STACK}" =~ ^(w[0-9]+)-s([0-9]+)-r[0-9]+$ ]]; then
  printf "\nExiting, raw stack '%s' is not <wafer>-s<serial>-r<region>\n\n" "${ARG_RAW_STACK}"
  exit 1
fi

WAFER="${BASH_REMATCH[1]}"
# force base 10 so that a zero padded serial (e.g. 071) is not treated as octal
SERIAL_NUMBER=$(( 10#${BASH_REMATCH[2]} ))
FIRST_PROJECT_SERIAL=$(( (SERIAL_NUMBER / 10) * 10 ))

EXPORT_URL=$(printf '%s/%s_serial_%03d_to_%03d/%s%s' \
                    "${RENDER_EXP}" \
                    "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )) \
                    "${ARG_RAW_STACK//-/_}" "${DATASET_SUFFIX}")

if [ "${ARG_ALL_LEVELS}" = "true" ]; then

  REMOVE_URL="${EXPORT_URL}"

else

  # s0 is excluded because it is the full scale data that reruns start from
  # (use --all-levels to remove it along with everything else)
  if [[ ! "${ARG_S_LEVEL}" =~ ^s[0-9]+$ ]] || [ "${ARG_S_LEVEL}" = "s0" ]; then
    printf "\nExiting, s level '%s' must be s1 or higher\n\n" "${ARG_S_LEVEL}"
    exit 1
  fi

  REMOVE_URL="${EXPORT_URL}/${ARG_S_LEVEL}"

fi

# The rebuilt url has to match the one that was passed in, otherwise the url refers to
# something other than a standard render export (level) and should not be removed here.
if [ -n "${ARG_FULL_URL}" ] && [ "${REMOVE_URL}" != "${ARG_FULL_URL}" ]; then
  printf "\nExiting, --full-url does not match the url built from its stack and level:
    --full-url: %s
       derived: %s\n\n" "${ARG_FULL_URL}" "${REMOVE_URL}"
  exit 1
fi

# ----------------------------------------------------------------------------
# Confirm and remove

printf "\nchecking %s ...\n" "${REMOVE_URL}"

OBJECT_COUNT=$(gcloud storage ls --recursive "${REMOVE_URL}/**" 2>/dev/null | wc -l | tr -d ' ')

if (( OBJECT_COUNT == 0 )); then
  printf "\nExiting, %s has no objects (it may have been removed already)\n\n" "${REMOVE_URL}"
  exit 1
fi

if [ "${ARG_ALL_LEVELS}" = "true" ]; then
  LEVEL_NAMES=$(gcloud storage ls "${REMOVE_URL}/" 2>/dev/null |
                  sed -nE 's#.*/(s[0-9]+)/$#\1#p' | sort -V | paste -sd ' ' -)
  printf "
%s is an entire export with scale levels: %s
It contains %s object(s), including the full scale s0 data.

Removing it cannot be undone.
" "${REMOVE_URL}" "${LEVEL_NAMES:-(none found)}" "${OBJECT_COUNT}"
else
  printf "
%s contains %s object(s).

Removing it cannot be undone.
" "${REMOVE_URL}" "${OBJECT_COUNT}"
fi

if [ "${ARG_SKIP_CONFIRM}" = "true" ]; then
  printf "\n--skip-confirm was specified, so not asking before removing it\n"
else
  echo
  read -rp "Do you want to remove it? (y/n): " CONFIRM

  if [[ ! ${CONFIRM} =~ ^[Yy]$ ]]; then
    printf "\nnothing was removed\n\n"
    exit 0
  fi
fi

printf "\nremoving %s ...\n" "${REMOVE_URL}"

gcloud storage rm --recursive --no-user-output-enabled "${REMOVE_URL}"

printf "\nremoved %s object(s) from %s\n\n" "${OBJECT_COUNT}" "${REMOVE_URL}"
