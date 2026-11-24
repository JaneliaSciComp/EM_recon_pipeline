#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="04g_problem_pixel_export"
SLABS_PER_RUN=10

# ----------------------------------------------------------------------------
# Exports the _asoi_3d stacks that the 04f stage fixed (the ones listed in the tileRemoval
# project_to_stack_scans and project_to_stack_scan_mfovs of pipe.04b.w6n.remove-problem-tiles.json)
# again, so that SOFIMA can be run with the problem scans and MFOVs removed.
#
# The fixed 04b_3d_align dump of each listed project is restored on one VM, and every stack of those
# projects that is not listed is left out with db-restore-collections.sh --exclude-pattern.
#
# A run covers the project of the first serial number up to the one with --last-serial, which defaults
# to the last project the JSON lists (so e.g. "61 0 A" exports every listed w61 stack).
#
# The original exports of these stacks should be moved away before the run, so that the new ones get
# the usual <stack>___pixel dataset names.  11_run_n5_export.sh appends the run time to the name of any
# dataset that still exists (e.g. w61_s010_r00_gc_bc_par_cc_asoi_3d___pixel_20261124-093012), so this
# script warns about each stack whose original export is still there.
#
# NOTE: like load_data_for_04e_pixel_export_runs.sh --downsample-only, this runs gcloud storage ls,
#       so it needs gcloud credentials.

# Pull --last-serial out of the parameters before setup_load_data_variables.sh parses the rest
# (it can come before, between, or after the other values).
LAST_SERIAL_ARG=""
SETUP_ARGS=()
while (( $# > 0 )); do
  case "${1}" in
    --last-serial)
      if [ -z "${2:-}" ]; then
        printf "\nExiting, --last-serial requires a value (e.g. 69)\n\n"
        exit 1
      fi
      LAST_SERIAL_ARG="${2}"
      shift 2
      ;;
    *)
      SETUP_ARGS+=("${1}")
      shift
      ;;
  esac
done
set -- ${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}

USAGE_OPTIONS="[--last-serial <last serial number>]"
USAGE_DETAILS="  --last-serial  last serial number of the run (default: the last serial of the last project the
                 pipeline JSON lists), the run covers every project from the first serial
                 number's project to this one's

  Examples:
    $(basename "$0") 61  0 C                     # every listed w61 stack
    $(basename "$0") 61 30 D --last-serial 49    # the listed w61_serial_030_to_039 to w61_serial_040_to_049 stacks"

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

# Add current time to run file so that a different file is created for each run.
RUN_FILE="${OUTPUT_DIR}/run.$(date '+%Y%m%d').${STAGE}.vm${VM_LETTER}.$(date '+%H%M%S').txt"

if [ -n "${REGIONS_ARG}" ]; then
  printf "\nExiting, --regions is not supported for %s (the stacks come from the pipeline JSON)\n\n" "${STAGE}"
  exit 1
fi

MSEM_60_61_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)

PIPELINE_JSON="04_3d_align/pipe.04b.w6n.remove-problem-tiles.json"
PIPELINE_JSON_PATH="${MSEM_60_61_DIR}/pipeline_json/${PIPELINE_JSON}"

# lists every raw stack of the wafer (e.g. stack_name='w61_s070_r00'), so it has each slab's regions
SLAB_INFO_PATH="${MSEM_60_61_DIR}/slab_info.w${WAFER}.txt"

# the stacks the 04f stage changed, only the _asoi_3d ones are exported
ASO_SUFFIX="_gc_bc_par_cc_aso"
ASOI_3D_SUFFIX="_gc_bc_par_cc_asoi_3d"
STACK_SUFFIXES=("${ASO_SUFFIX}" "${ASOI_3D_SUFFIX}")

# keep this in sync with N5_PATH in ../11_run_n5_export.sh
N5_EXPORT_URL="gs://janelia-spark-test/hess_wafers_60_61_export/render"

# same as load_data_for_04e_pixel_export_runs.sh:
#   5 executors for w61 r00 regions take 7 to 9 hours
#   5 executors for w61 r01 regions take 2.5 to 3.5 hours
#  10 executors for w61_s099_r00 pixel with 82 z layers took 4 hours, 15 minutes
MAX_EXECUTORS=10

if [ ! -f "${SLAB_INFO_PATH}" ]; then
  printf "\nExiting, %s does not exist\n\n" "${SLAB_INFO_PATH}"
  exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
  printf "\nExiting, jq is needed to read %s\n\n" "${PIPELINE_JSON_PATH}"
  exit 1
fi

if [ ! -f "${PIPELINE_JSON_PATH}" ]; then
  printf "\nExiting, %s does not exist\n\n" "${PIPELINE_JSON_PATH}"
  exit 1
fi

# prints "<project> <stack>" for every stack in the JSON's project_to_stack_scans and
# project_to_stack_scan_mfovs, one per line (a stack in both maps is printed twice)
if ! JSON_PROJECT_STACKS=$(jq -r '.tileRemoval | (.project_to_stack_scans // {}), (.project_to_stack_scan_mfovs // {}) |
                                  to_entries[] | .key as $project |
                                  (.value // {}) | keys[] | "\($project) \(.)"' "${PIPELINE_JSON_PATH}"); then
  printf "\nExiting, could not read the tileRemoval project_to_stack_scans and project_to_stack_scan_mfovs stacks from %s\n\n" \
         "${PIPELINE_JSON_PATH}"
  exit 1
fi

# ----------------------------------------------------------------------------
# Work out the run's serial range

if [ -z "${LAST_SERIAL_ARG}" ]; then
  # the last serial of the last listed project of this wafer (e.g. 69 for w61_serial_060_to_069)
  RUN_LAST_SERIAL_NUMBER=$(printf '%s\n' "${JSON_PROJECT_STACKS}" |
                           awk -v wafer="${WAFER}" '
                             index($1, "w" wafer "_serial_") == 1 {
                               last = substr($1, length(wafer) + 17, 3) + 0
                               if (last > max) { max = last }
                             }
                             END { print max + 0 }')
  if (( RUN_LAST_SERIAL_NUMBER < LAST_SERIAL_NUMBER )); then
    printf "\nNothing to run, %s does not list any w%s projects from s%s on\n\n" \
           "${PIPELINE_JSON}" "${WAFER}" "${FIRST_SERIAL}"
    exit 0
  fi
elif [[ ! ${LAST_SERIAL_ARG} =~ ^[0-9]+$ ]]; then
  printf "\nExiting, --last-serial '%s' is not a number\n\n" "${LAST_SERIAL_ARG}"
  exit 1
else
  # force base 10 so that zero padded values (e.g. 079) are not treated as octal
  RUN_LAST_SERIAL_NUMBER=$(( 10#${LAST_SERIAL_ARG} ))
fi

# setup_load_data_variables.sh sets LAST_SERIAL_NUMBER to the last serial of the first project
if (( RUN_LAST_SERIAL_NUMBER < LAST_SERIAL_NUMBER )) || (( RUN_LAST_SERIAL_NUMBER > 419 )) ||
   (( RUN_LAST_SERIAL_NUMBER % 10 != 9 )); then
  printf "\nExiting, --last-serial %d must be the last serial of a project (ending in 9) from %d to 419\n\n" \
         "${RUN_LAST_SERIAL_NUMBER}" "${LAST_SERIAL_NUMBER}"
  exit 1
fi

RUN_LAST_SERIAL=$(printf "%03d" "${RUN_LAST_SERIAL_NUMBER}")

# prints the project name for the specified first serial number of the project (e.g. w61_serial_010_to_019)
projectName() {
  printf 'w%s_serial_%03d_to_%03d' "${WAFER}" "$1" "$(( $1 + 9 ))"
}

RUN_PROJECTS=()
for (( PROJECT_FIRST_NUMBER = FIRST_SERIAL_NUMBER; PROJECT_FIRST_NUMBER < RUN_LAST_SERIAL_NUMBER;
       PROJECT_FIRST_NUMBER += 10 )); do
  RUN_PROJECTS+=("$(projectName "${PROJECT_FIRST_NUMBER}")")
done

# ----------------------------------------------------------------------------
# Check the listed stacks (the same checks as load_data_for_04f_remove_problem_layers.sh)

# the "<project> <stack>" lines for the run's projects
RUN_PROJECT_STACKS=$(printf '%s\n' "${JSON_PROJECT_STACKS}" |
                     grep -F -f <(printf '%s \n' "${RUN_PROJECTS[@]}") | sort -u)

LISTED_STACKS=$(printf '%s\n' "${RUN_PROJECT_STACKS}" | awk 'NF == 2 { print $2 }' | sort -u)

# prints the slab info raw stacks (e.g. w61_s070_r00) with serials in the specified range
rawStacksInRange() {
  grep -oE "stack_name='w${WAFER}_s[0-9]{3}_r[0-9]{2}'" "${SLAB_INFO_PATH}" | cut -d"'" -f2 |
    awk -v first="$1" -v last="$2" \
        '{ serial = substr($0, index($0, "_s") + 2, 3) + 0; if (serial >= first && serial <= last) print }' |
    sort -u
}

CANDIDATE_STACKS=()
while IFS= read -r RAW_STACK; do
  for SUFFIX in "${STACK_SUFFIXES[@]}"; do
    CANDIDATE_STACKS+=("${RAW_STACK}${SUFFIX}")
  done
done < <(rawStacksInRange "${FIRST_SERIAL_NUMBER}" "${RUN_LAST_SERIAL_NUMBER}")

if (( ${#CANDIDATE_STACKS[@]} == 0 )); then
  printf "\nExiting, %s has no s%s to s%s raw stacks\n\n" "${SLAB_INFO_PATH}" "${FIRST_SERIAL}" "${RUN_LAST_SERIAL}"
  exit 1
fi

# A stack listed under the wrong project would not have been fixed by the 04f stage.
MISPLACED_STACKS=$(printf '%s\n' "${JSON_PROJECT_STACKS}" |
                   awk -v wafer="${WAFER}" -v first="${FIRST_SERIAL_NUMBER}" -v last="${RUN_LAST_SERIAL_NUMBER}" '
                     NF == 2 && index($2, "w" wafer "_s") == 1 {
                       # e.g. w61_s002_r00_... has the serial at character 6 and
                       #      w61_serial_000_to_009 has the project first serial at character 12
                       serial = substr($2, length(wafer) + 4, 3) + 0
                       project_first = int(serial / 10) * 10
                       expected = sprintf("w%s_serial_%03d_to_%03d", wafer, project_first, project_first + 9)
                       key_first = substr($1, length(wafer) + 10, 3) + 0
                       in_run = (serial >= first && serial <= last) || (key_first >= first && key_first <= last)
                       if (in_run && ($1 != expected)) {
                         print $2 " (listed under " $1 " instead of " expected ")"
                       }
                     }')
if [ -n "${MISPLACED_STACKS}" ]; then
  printf "\nExiting, %s lists stacks under the wrong project:\n%s\n\n" \
         "${PIPELINE_JSON}" "$(printf '%s\n' "${MISPLACED_STACKS}" | sed 's/^/  /')"
  exit 1
fi

UNEXPECTED_STACKS=$(printf '%s\n' "${LISTED_STACKS}" | grep -v '^$' |
                    grep -v -x -F -f <(printf '%s\n' "${CANDIDATE_STACKS[@]}"))
if [ -n "${UNEXPECTED_STACKS}" ]; then
  printf "\nExiting, %s lists stacks for the s%s to s%s projects that are not %s stacks of their slabs:\n%s\n\n" \
         "${PIPELINE_JSON}" "${FIRST_SERIAL}" "${RUN_LAST_SERIAL}" "${STACK_SUFFIXES[*]}" \
         "$(printf '%s\n' "${UNEXPECTED_STACKS}" | sed 's/^/  /')"
  exit 1
fi

EXPORT_STACKS=()
while IFS= read -r STACK; do
  if [ -n "${STACK}" ]; then
    EXPORT_STACKS+=("${STACK}")
  fi
done < <(printf '%s\n' "${LISTED_STACKS}" | grep -E "${ASOI_3D_SUFFIX}\$")

if (( ${#EXPORT_STACKS[@]} == 0 )); then
  printf "\nNothing to run, %s does not list any %s stacks for the s%s to s%s projects\n\n" \
         "${PIPELINE_JSON}" "${ASOI_3D_SUFFIX}" "${FIRST_SERIAL}" "${RUN_LAST_SERIAL}"
  exit 0
fi

# ----------------------------------------------------------------------------
# Work out what to load
#
# Only the projects with exported stacks are loaded.  The restore --pattern is read by basic grep,
# so \( \| \) group the project names, and the slab group must be exactly s<first>_to_s<last>_<suffix>
# so that the _pre_remove_<date> backups made by the 04f stage (and any region specific slab groups)
# are not restored.

# The project of a stack, e.g. w61_serial_010_to_019 for w61_s010_r00_gc_bc_par_cc_asoi_3d
stackProject() {
  projectName "$(( (10#${1:$(( ${#WAFER} + 3 )):3} / 10) * 10 ))"
}

LOADED_PROJECTS=()
EXPORT_RAW_STACKS=()
for STACK in "${EXPORT_STACKS[@]}"; do
  RAW_STACK="${STACK%"${ASOI_3D_SUFFIX}"}"
  EXPORT_RAW_STACKS+=("${RAW_STACK}")
  PROJECT=$(stackProject "${STACK}")
  if [[ " ${LOADED_PROJECTS[*]} " != *" ${PROJECT} "* ]]; then
    LOADED_PROJECTS+=("${PROJECT}")
  fi
done

# every raw stack of the loaded projects that is not exported is excluded
EXCLUDED_RAW_STACKS=()
for PROJECT in "${LOADED_PROJECTS[@]}"; do
  PROJECT_FIRST_NUMBER=$(( 10#${PROJECT:$(( ${#WAFER} + 9 )):3} ))
  while IFS= read -r RAW_STACK; do
    if [[ " ${EXPORT_RAW_STACKS[*]} " != *" ${RAW_STACK} "* ]]; then
      EXCLUDED_RAW_STACKS+=("${RAW_STACK}")
    fi
  done < <(rawStacksInRange "${PROJECT_FIRST_NUMBER}" "$(( PROJECT_FIRST_NUMBER + 9 ))")
done

PROJECT_ALTERNATION=$(printf '%s\|' "${LOADED_PROJECTS[@]}")
PROJECT_ALTERNATION="${PROJECT_ALTERNATION%\\|}"
RESTORE_PATTERN="google/04b_3d_align/\(${PROJECT_ALTERNATION}\)/s[0-9][0-9][0-9]_to_s[0-9][0-9][0-9]_${ALIGN_SLAB_GROUP_SUFFIX}/"

# Collection names and stack names both contain <raw stack>_, so the trailing underscore keeps
# w61_s070_r00 from also matching something like w61_s070_r001.  The pattern is read by grep -E
# for the dump files and by a JavaScript RegExp for the stack metadata, so it is kept to a simple
# alternation that means the same thing to both.
if (( ${#EXCLUDED_RAW_STACKS[@]} > 0 )); then
  EXCLUDE_PATTERN=$(printf '%s_|' "${EXCLUDED_RAW_STACKS[@]}")
  EXCLUDE_PATTERN="${EXCLUDE_PATTERN%|}"
  EXCLUDE_PARMS=" --exclude-pattern \"${EXCLUDE_PATTERN}\""
else
  EXCLUDE_PARMS=""
fi

# ----------------------------------------------------------------------------
# Build one line that submits an export job for each stack
#
# 11_run_n5_export.sh submits with --async and returns immediately, so the sleeps simply
# space out the submissions.  Using && means a failed submission stops the ones after it.

BATCH_EXPORT_CMD=""
for STACK in "${EXPORT_STACKS[@]}"; do
  EXPORT_CMD="./11_run_n5_export.sh --render-ws-ip ${VM_IP} --stack ${STACK} --max-executors ${MAX_EXECUTORS} --dataset-suffix pixel --disable-dynamic"
  BATCH_EXPORT_CMD="${BATCH_EXPORT_CMD:+${BATCH_EXPORT_CMD} && sleep 10 && }${EXPORT_CMD}"
done

# Check for original exports that were not moved away.  Each dataset is checked individually
# rather than with one listing of a project, which would also return any older timestamped exports.
printf "\nchecking for existing %s___pixel exports ...\n" "${ASOI_3D_SUFFIX}"

EXISTING_EXPORTS=()
for STACK in "${EXPORT_STACKS[@]}"; do
  DATASET_URL="${N5_EXPORT_URL}/$(stackProject "${STACK}")/${STACK}___pixel"
  if gcloud storage ls "${DATASET_URL}/" 2>/dev/null | grep -q .; then
    EXISTING_EXPORTS+=("${DATASET_URL}")
  fi
done

if (( ${#EXISTING_EXPORTS[@]} > 0 )); then
  EXISTING_WARNING="
# WARNING: these original exports still exist, so their new exports will have the run time appended
#          to their dataset names (move them away and run this again to keep the usual names):
$(printf '#   %s\n' "${EXISTING_EXPORTS[@]}")
"
else
  EXISTING_WARNING=""
fi

LIST_EXPORTS_CMDS=""
for PROJECT in "${LOADED_PROJECTS[@]}"; do
  PROJECT_STACKS=""
  for STACK in "${EXPORT_STACKS[@]}"; do
    if [ "$(stackProject "${STACK}")" = "${PROJECT}" ]; then
      PROJECT_STACKS="${PROJECT_STACKS:+${PROJECT_STACKS}|}${STACK}"
    fi
  done
  LIST_EXPORTS_CMDS="${LIST_EXPORTS_CMDS:+${LIST_EXPORTS_CMDS}
}gcloud storage ls ${N5_EXPORT_URL}/${PROJECT}/ | grep -E '/(${PROJECT_STACKS})___pixel'"
done

EXPORT_LIST=$(printf '#   %s\n' "${EXPORT_STACKS[@]}")
LOADED_LIST=$(printf '#   %s\n' "${LOADED_PROJECTS[@]}")

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, serials s${FIRST_SERIAL} to s${RUN_LAST_SERIAL}

Run file: ${RUN_FILE}

# ${PIPELINE_JSON} lists these ${#EXPORT_STACKS[@]} ${ASOI_3D_SUFFIX} stacks for the run's projects:
${EXPORT_LIST}
#
# They are in these ${#LOADED_PROJECTS[@]} project(s), whose other ${#EXCLUDED_RAW_STACKS[@]} region stacks are excluded when the data is loaded:
${LOADED_LIST}
${EXISTING_WARNING}
cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Remove the collections from the previous run:
${RIC_CMD} './remove-collections.sh --db render --method remove --items all'

# Load the fixed 04b_3d_align results of the listed stacks
# (should list ${#LOADED_PROJECTS[@]} dump directories, for the dump directories prompt, enter: all):
${RIC_CMD} './db-restore-collections.sh --pattern \"${RESTORE_PATTERN}\"${EXCLUDE_PARMS}'

# Check what is loaded (only the ${#EXPORT_STACKS[@]} stacks listed above should be there):
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run export jobs:

# Submits ${#EXPORT_STACKS[@]} export jobs, one for each listed ${ASOI_3D_SUFFIX} stack, with ${MAX_EXECUTORS} executors each.
${BATCH_EXPORT_CMD}

# -------------------------------------
# If needed, download the driver log for one of the export jobs:

# export batch ids are rex-<launch-time>-<stack name with dashes>-pixel,
# so a pattern is enough to find the most recent one (e.g. for ${EXPORT_STACKS[0]})
./dataproc/download_driver_log.sh --batch-id '$(printf '%s' "${EXPORT_RAW_STACKS[0]}" | tr '_' '-')-.*-pixel'

# -------------------------------------
# After the jobs complete, list the new datasets to send to the SOFIMA collaborator:
${LIST_EXPORTS_CMDS}

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
