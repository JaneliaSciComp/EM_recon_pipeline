#!/bin/bash

# ----------------------------------------------------------------------------
# Moves exported volumes in Google storage out of the way so that new ones can be written to the
# original names.  The --type parameter selects which volumes are moved:
#
#   render: exported pixel volumes are renamed by appending a suffix, e.g.
#     gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_asoi_3d___pixel
#     -> gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_asoi_3d___pixel_20260925
#
#   cost: cost volumes are moved into the old directory of the cost group, e.g.
#     gs://janelia-spark-test/hess_wafers_60_61_export/cost_v4/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i
#     -> gs://janelia-spark-test/hess_wafers_60_61_export/cost_v4/old/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i
#
#   hf: heightfields volumes are moved into the old directory of the heightfields group, e.g.
#     gs://janelia-spark-test/hess_wafers_60_61_export/heightfields_v4/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i
#     -> gs://janelia-spark-test/hess_wafers_60_61_export/heightfields_v4/old/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i
#
#   hf_surface: heightfield surface volumes (with their min and max groups) are moved into the old
#   directory of the heightfields surface group, e.g.
#     gs://janelia-spark-test/hess_wafers_60_61_export/heightfields_v4_surface/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i
#     -> gs://janelia-spark-test/hess_wafers_60_61_export/heightfields_v4_surface/old/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i
#
# Google storage has no real directories, so a move copies every object in the volume to the new
# name and then deletes the original.  The copies happen inside Google storage, but large volumes
# still take a while.
#
# Each volume is moved in three steps so that the source is only deleted once it has been copied:
#   1. gcloud storage rsync copies the volume to the target
#   2. every source object is checked to exist in the target with the same size
#   3. only then is the source deleted
#
# gcloud storage mv is not used because an interrupted mv leaves the volume split between the two
# names, and rerunning it onto the existing target would nest the volume inside the target.
#
# A stack is skipped when neither its volume nor its target exists (e.g. r01 for serials 180 and up),
# and is reported as already moved when only its target exists.  When a stack's target already exists
# along with its volume (e.g. a volume moved before was regenerated), the volume is moved to a new
# target named with today's date appended instead (e.g. .../old/w61_serial_070_to_079/<stack>_20261124),
# or with the date and time if that exists too, so an earlier moved version is never mixed with or
# overwritten by a later one.  Because of this, a failed move is not resumed by a rerun, see the
# error messages for how to clean up.
#
# Use --suffix to choose the target name instead, e.g. to give the heightfields and heightfields surface
# volumes of a stack the same suffix.  With --suffix 20261124_082411 the target is always
# .../old/w61_serial_070_to_079/<stack>_20261124_082411 (or <volume>_20261124_082411 for render, in place
# of the _20261122 suffix), and the stack fails rather than being moved if that target already
# exists along with the volume.

EXPORT_BASE_URL="gs://janelia-spark-test/hess_wafers_60_61_export"
WAFER="61"

# keep these in sync with N5_PATH, N5_DATASET, and RENDER_PROJECT in 11_run_n5_export.sh
RENDER_BASE_URL="${EXPORT_BASE_URL}/render"
RENDER_STACK_SUFFIX="_gc_bc_par_cc_asoi_3d"
RENDER_DATASET_SUFFIX="___pixel"
# appended to each moved render volume's name
RENDER_TARGET_SUFFIX="_20261122"

# keep these in sync with hot-knife RawStack (getCostDataset, getHeightfieldsDataset,
# getHeightfieldsSurfaceDataset, and DEFAULT_IC3D_SUFFIX)
COST_BASE_URL="${EXPORT_BASE_URL}/cost_v4"
HF_BASE_URL="${EXPORT_BASE_URL}/heightfields_v4"
HF_SURFACE_BASE_URL="${EXPORT_BASE_URL}/heightfields_v4_surface"
IC3D_STACK_SUFFIX="_gc_bc_par_cc_aso_3d_s3i"
# moved cost, heightfields, and heightfields surface volumes keep their project and stack names
# under this directory of their group
OLD_DIR="old"

# appended to a target that already exists (with the time too if the dated target exists),
# e.g. a volume that was moved before and then regenerated
DATE_SUFFIX="_$(date +%Y%m%d)"
DATE_TIME_SUFFIX="_$(date +%Y%m%d_%H%M%S)"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_TYPE=""
ARG_REGION=""
ARG_MIN_SERIAL=""
ARG_MAX_SERIAL=""
ARG_DRY_RUN="false"
ARG_SUFFIX=""

usage() {
  echo "
USAGE $0 --type <type> --region <region> --min-serial <number> --max-serial <number> [--suffix <suffix>] [--dry-run]

  --type        type of volumes to move, render, cost, hf (heightfields),
                or hf_surface (heightfields surface) (required)
  --region      region of the stacks to move, r00 or r01 (required)
  --min-serial  first serial number to move (required)
  --max-serial  last serial number to move (required)
  --suffix      always append _<suffix> to the target name, e.g. 20261124_082411
                (by default a suffix is only added when the target already exists,
                using today's date, or the date and time if that exists too)
  --dry-run     print the gcloud copy and remove commands instead of running them

For --type render, each w${WAFER}_s<serial>_<region>${RENDER_STACK_SUFFIX}${RENDER_DATASET_SUFFIX} volume is moved to
w${WAFER}_s<serial>_<region>${RENDER_STACK_SUFFIX}${RENDER_DATASET_SUFFIX}${RENDER_TARGET_SUFFIX} in the same project directory under
${RENDER_BASE_URL}

For --type cost, hf, or hf_surface, each <project>/w${WAFER}_s<serial>_<region>${IC3D_STACK_SUFFIX} volume under
${COST_BASE_URL} (cost),
${HF_BASE_URL} (hf), or
${HF_SURFACE_BASE_URL} (hf_surface)
is moved to the same <project>/<stack> path under the group's ${OLD_DIR} directory

Examples:
  $0 --type render --region r00 --min-serial 70 --max-serial 79 --dry-run
  $0 --type render --region r01 --min-serial 70 --max-serial 179
  $0 --type cost --region r00 --min-serial 70 --max-serial 79 --dry-run
  $0 --type hf --region r00 --min-serial 70 --max-serial 79 --dry-run
  $0 --type hf_surface --region r00 --min-serial 70 --max-serial 79 --dry-run
  $0 --type hf --region r00 --min-serial 70 --max-serial 70 --suffix 20261124_082411
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --type)
      ARG_TYPE="${2:?'--type requires a value'}"
      shift 2
      ;;
    --region)
      ARG_REGION="${2:?'--region requires a value'}"
      shift 2
      ;;
    --min-serial)
      ARG_MIN_SERIAL="${2:?'--min-serial requires a value'}"
      shift 2
      ;;
    --max-serial)
      ARG_MAX_SERIAL="${2:?'--max-serial requires a value'}"
      shift 2
      ;;
    --suffix)
      ARG_SUFFIX="${2:?'--suffix requires a value'}"
      shift 2
      ;;
    --dry-run)
      ARG_DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

case "${ARG_TYPE}" in
  render) STACK_SUFFIX="${RENDER_STACK_SUFFIX}" ;;
  cost)   STACK_SUFFIX="${IC3D_STACK_SUFFIX}"; GROUP_BASE_URL="${COST_BASE_URL}" ;;
  hf)     STACK_SUFFIX="${IC3D_STACK_SUFFIX}"; GROUP_BASE_URL="${HF_BASE_URL}" ;;
  hf_surface) STACK_SUFFIX="${IC3D_STACK_SUFFIX}"; GROUP_BASE_URL="${HF_SURFACE_BASE_URL}" ;;
  *)
    echo "ERROR: --type must be render, cost, hf, or hf_surface (not '${ARG_TYPE}')"
    exit 1
    ;;
esac

if [[ ! "${ARG_REGION}" =~ ^r0[01]$ ]]; then
  echo "ERROR: --region must be r00 or r01 (not '${ARG_REGION}')"
  exit 1
fi

for SERIAL_ARG in "${ARG_MIN_SERIAL}" "${ARG_MAX_SERIAL}"; do
  if [[ ! "${SERIAL_ARG}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --min-serial and --max-serial must be numbers (not '${SERIAL_ARG}')"
    exit 1
  fi
done

# force base 10 so that zero padded values (e.g. 070) are not treated as octal
MIN_SERIAL=$(( 10#${ARG_MIN_SERIAL} ))
MAX_SERIAL=$(( 10#${ARG_MAX_SERIAL} ))

if (( MIN_SERIAL > MAX_SERIAL )); then
  echo "ERROR: --min-serial ${MIN_SERIAL} is greater than --max-serial ${MAX_SERIAL}"
  exit 1
fi

if (( MAX_SERIAL > 999 )); then
  echo "ERROR: --max-serial must be less than 1000 (not ${MAX_SERIAL})"
  exit 1
fi

# accept the suffix with or without its leading underscore
ARG_SUFFIX="${ARG_SUFFIX#_}"
if [ -n "${ARG_SUFFIX}" ] && [[ ! "${ARG_SUFFIX}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
  echo "ERROR: --suffix must only have letters, numbers, _, ., and - (not '${ARG_SUFFIX}')"
  exit 1
fi

# ----------------------------------------------------------------------------
# Build the list of stacks to move

STACKS=()
for (( SERIAL = MIN_SERIAL; SERIAL <= MAX_SERIAL; SERIAL++ )); do
  STACKS+=("$(printf "w%s_s%03d_%s%s" "${WAFER}" "${SERIAL}" "${ARG_REGION}" "${STACK_SUFFIX}")")
done

# e.g. w61_s070_r00_... is in w61_serial_070_to_079
projectForStack() {
  local STACK_SERIAL
  STACK_SERIAL=$(echo "${1}" | sed -E 's/^w[0-9]+_s([0-9]{3})_.*/\1/')
  local FIRST_PROJECT_SERIAL=$(( (10#${STACK_SERIAL} / 10) * 10 ))
  printf "w%s_serial_%03d_to_%03d" "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 ))
}

# gcloud storage ls fails when nothing matches, so any listed object means the volume exists
volumeExists() {
  gcloud storage ls "${1}/" 2>/dev/null | grep -q .
}

# Writes a sorted "<name relative to the volume> <size>" line for each object in the volume to the
# specified file.  Zero byte "directory" placeholder objects (names ending with /) are left out because
# they are not data and rsync may not copy them.
listObjects() {
  local VOLUME_URL="${1}"
  local OUTPUT_FILE="${2}"
  gcloud storage ls --long "${VOLUME_URL}/**" 2>/dev/null |
    awk -v prefix="${VOLUME_URL}/" '
      index($NF, prefix) == 1 && $NF !~ /\/$/ { print substr($NF, length(prefix) + 1), $1 }' |
    sort > "${OUTPUT_FILE}"
}

# e.g. "45 seconds" for 45 and "190 seconds" for 190
formatElapsed() {
  local ELAPSED_SECONDS="${1}"
  local UNIT="seconds"
  (( ELAPSED_SECONDS == 1 )) && UNIT="second"
  printf "%d %s" "${ELAPSED_SECONDS}" "${UNIT}"
}

LIST_DIR=$(mktemp -d)
trap 'rm -rf "${LIST_DIR}"' EXIT

printf "\nmoving %d %s %s stack volume(s) for serials %03d to %03d%s ...\n" \
       "${#STACKS[@]}" "${ARG_REGION}" "${ARG_TYPE}" "${MIN_SERIAL}" "${MAX_SERIAL}" \
       "$( [ "${ARG_DRY_RUN}" = "true" ] && echo " (dry run)" )"

# ----------------------------------------------------------------------------
# Move each stack's volume

MOVED=()
ALREADY_MOVED=()
SKIPPED=()
FAILED=()

for STACK in "${STACKS[@]}"; do

  PROJECT="$(projectForStack "${STACK}")"
  if [ "${ARG_TYPE}" = "render" ]; then
    SOURCE_URL="${RENDER_BASE_URL}/${PROJECT}/${STACK}${RENDER_DATASET_SUFFIX}"
    TARGET_URL="${SOURCE_URL}${RENDER_TARGET_SUFFIX}"
  else
    SOURCE_URL="${GROUP_BASE_URL}/${PROJECT}/${STACK}"
    TARGET_URL="${GROUP_BASE_URL}/${OLD_DIR}/${PROJECT}/${STACK}"
  fi

  # an explicit suffix replaces the render target suffix and is added to the other targets
  if [ -n "${ARG_SUFFIX}" ]; then
    if [ "${ARG_TYPE}" = "render" ]; then
      TARGET_URL="${SOURCE_URL}_${ARG_SUFFIX}"
    else
      TARGET_URL="${TARGET_URL}_${ARG_SUFFIX}"
    fi
  fi

  printf "\n%s\n" "${STACK}"

  if ! volumeExists "${SOURCE_URL}"; then
    if volumeExists "${TARGET_URL}"; then
      printf "  already moved to %s\n" "${TARGET_URL}"
      ALREADY_MOVED+=("${STACK}")
    else
      printf "  skipping, %s does not exist\n" "${SOURCE_URL}"
      SKIPPED+=("${STACK}")
    fi
    continue
  fi

  # never copy into an earlier moved version: fail with an explicit suffix,
  # otherwise move a regenerated volume to a new dated target
  if [ -n "${ARG_SUFFIX}" ] && volumeExists "${TARGET_URL}"; then
    printf "  ERROR: %s already exists, source was not moved (choose another --suffix)\n" "${TARGET_URL}"
    FAILED+=("${STACK}")
    continue
  elif volumeExists "${TARGET_URL}"; then
    printf "  %s already exists\n" "${TARGET_URL}"
    if volumeExists "${TARGET_URL}${DATE_SUFFIX}"; then
      ADDED_SUFFIX="${DATE_TIME_SUFFIX}"
    else
      ADDED_SUFFIX="${DATE_SUFFIX}"
    fi
    TARGET_URL="${TARGET_URL}${ADDED_SUFFIX}"
    if volumeExists "${TARGET_URL}"; then
      printf "  ERROR: %s also exists, source was not moved\n" "${TARGET_URL}"
      FAILED+=("${STACK}")
      continue
    fi
    # render targets already have a suffix, so the same --suffix would not give the same name
    if [ "${ARG_TYPE}" != "render" ]; then
      printf "  adding suffix %s (use --suffix %s to give the other types the same name)\n" \
             "${ADDED_SUFFIX}" "${ADDED_SUFFIX#_}"
    fi
  fi

  if [ "${ARG_DRY_RUN}" = "true" ]; then
    printf "  would run: gcloud storage rsync --recursive %s %s\n" "${SOURCE_URL}" "${TARGET_URL}"
    printf "  would check that every source object is in the target with the same size\n"
    printf "  would run: gcloud storage rm %s/**\n" "${SOURCE_URL}"
    MOVED+=("${STACK}")
    continue
  fi

  STACK_START_SECONDS=${SECONDS}

  # 1. copy (the target does not exist yet, so rsync creates it rather than nesting the volume in it)
  printf "  copying %s\n       to %s ...\n" "${SOURCE_URL}" "${TARGET_URL}"

  # a rerun after a failed copy or check would move the source to another dated target,
  # so the partial target needs to be removed before rerunning
  REMOVE_TARGET_HINT="remove the partial copy with 'gcloud storage rm --recursive ${TARGET_URL}' and rerun"

  # --no-user-output-enabled hides the 'Copying ...' line printed for every object
  if ! gcloud storage rsync --recursive --no-user-output-enabled "${SOURCE_URL}" "${TARGET_URL}"; then
    printf "  ERROR: copy failed, source was not removed, %s\n" "${REMOVE_TARGET_HINT}"
    FAILED+=("${STACK}")
    continue
  fi

  # 2. verify that every source object is in the target with the same size
  SOURCE_LIST="${LIST_DIR}/source.txt"
  TARGET_LIST="${LIST_DIR}/target.txt"
  listObjects "${SOURCE_URL}" "${SOURCE_LIST}"
  listObjects "${TARGET_URL}" "${TARGET_LIST}"

  SOURCE_COUNT=$(wc -l < "${SOURCE_LIST}" | tr -d ' ')
  MISSING_COUNT=$(comm -23 "${SOURCE_LIST}" "${TARGET_LIST}" | wc -l | tr -d ' ')

  if (( SOURCE_COUNT == 0 )); then
    printf "  ERROR: could not list the objects in %s, source was not removed, %s\n" "${SOURCE_URL}" "${REMOVE_TARGET_HINT}"
    FAILED+=("${STACK}")
    continue
  fi

  if (( MISSING_COUNT > 0 )); then
    printf "  ERROR: %d of %d source objects are missing from the target or have a different size, source was not removed, %s\n" \
           "${MISSING_COUNT}" "${SOURCE_COUNT}" "${REMOVE_TARGET_HINT}"
    comm -23 "${SOURCE_LIST}" "${TARGET_LIST}" | head -5 | sed 's/^/    /'
    FAILED+=("${STACK}")
    continue
  fi

  printf "  verified all %d source objects in the target\n" "${SOURCE_COUNT}"

  # 3. remove the source
  printf "  removing %s ...\n" "${SOURCE_URL}"

  # --no-user-output-enabled hides the 'Removing ...' line printed for every object
  if ! gcloud storage rm --no-user-output-enabled "${SOURCE_URL}/**"; then
    printf "  ERROR: remove failed, the copy is complete, finish removing the source with 'gcloud storage rm %s/**' (a rerun would move what is left to another target)\n" "${SOURCE_URL}"
    FAILED+=("${STACK}")
    continue
  fi

  if volumeExists "${SOURCE_URL}"; then
    printf "  ERROR: objects are left in %s, the copy is complete, finish removing the source with 'gcloud storage rm %s/**' (a rerun would move what is left to another target)\n" "${SOURCE_URL}" "${SOURCE_URL}"
    FAILED+=("${STACK}")
    continue
  fi

  printf "  done in %s\n" "$(formatElapsed $(( SECONDS - STACK_START_SECONDS )))"
  MOVED+=("${STACK}")

done

# ----------------------------------------------------------------------------
# Summarize

if [ "${ARG_DRY_RUN}" = "true" ]; then
  MOVED_LABEL="would move"
else
  MOVED_LABEL="moved"
fi

printf "\n%s %d, already moved %d, skipped %d (no volume), failed %d\n" \
       "${MOVED_LABEL}" "${#MOVED[@]}" "${#ALREADY_MOVED[@]}" "${#SKIPPED[@]}" "${#FAILED[@]}"

if (( ${#FAILED[@]} > 0 )); then
  printf "\nfailed stacks:\n"
  printf "  %s\n" "${FAILED[@]}"
  printf "\n"
  exit 1
fi

printf "\n"
