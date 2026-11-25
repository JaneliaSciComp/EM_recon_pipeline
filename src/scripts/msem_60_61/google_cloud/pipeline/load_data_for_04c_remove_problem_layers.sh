#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="04c_remove_problem_layers"
SLABS_PER_RUN=10

# ----------------------------------------------------------------------------
# Removes the problem scans and MFOVs listed in the pipeline JSON's tileRemoval project_to_stack_scans
# and project_to_stack_scan_mfovs from the _aso and _asoi_3d stacks of one or more projects, and then
# replaces the 02_align and 04b_3d_align dumps that hold those stacks with fixed ones.
#
# A run covers the project of the first serial number and, with --last-serial, each following project
# up to the one with the last serial (e.g. 0 --last-serial 29 for w61_serial_000_to_009 to
# w61_serial_020_to_029).  All of the run's projects are loaded on one VM and processed by one batch.
#
# The run restores the full 04b_3d_align (_asoi_3d) and 02_align (_aso) dumps of each project that
# has listed stacks.  REMOVE_TILES only changes the listed stacks, so after the run each dump slab group
# with a changed stack is:
#
#   1. renamed by appending BACKUP_SUFFIX (e.g. s010_to_s019_20261027 -> s010_to_s019_20261027_pre_remove_20261123),
#      which keeps the original dump exactly as it was, and
#   2. dumped again under its original name with a pattern for just its serials' stacks,
#      so it has the fixed stacks along with the untouched ones.
#
# Those steps are written to a post run script next to the run file (with a .post-run.sh suffix instead
# of .txt), which stops at the first problem and can be run again starting with the group that had it.
#
# Later stages (e.g. the 04b and 04d exports and the 05 sofima import) restore the original slab group names
# with patterns that end in <slab group suffix>/, so they load the fixed dumps and never see the backups.
# Slab groups without a changed stack are left alone.

# Pull --last-serial out of the parameters before setup_load_data_variables.sh parses the rest
# (it can come before, between, or after the other values).
LAST_SERIAL_ARG=""
SETUP_ARGS=()
while (( $# > 0 )); do
  case "${1}" in
    --last-serial)
      if [ -z "${2:-}" ]; then
        printf "\nExiting, --last-serial requires a value (e.g. 29)\n\n"
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
USAGE_DETAILS="  --last-serial  last serial number of the run (default: first serial number + 9), the run
                 covers every project from the first serial number's project to this one's

  Examples:
    $(basename "$0") 61  0 C --last-serial 29    # w61_serial_000_to_009 to w61_serial_020_to_029
    $(basename "$0") 61 30 D --last-serial 49    # w61_serial_030_to_039 to w61_serial_040_to_049
    $(basename "$0") 61 70 E                     # just w61_serial_070_to_079"

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

# Add current time to run file so that a different file is created for each run.
# There are so many steps in this process that it is confusing to append multiple runs to the same file.
RUN_FILE="${OUTPUT_DIR}/run.$(date '+%Y%m%d').${STAGE}.vm${VM_LETTER}.$(date '+%H%M%S').txt"

if [ -n "${REGIONS_ARG}" ]; then
  printf "\nExiting, --regions is not supported for %s (the stacks come from the pipeline JSON)\n\n" "${STAGE}"
  exit 1
fi

# setup_load_data_variables.sh sets LAST_SERIAL_NUMBER to the last serial of the first project
if [ -z "${LAST_SERIAL_ARG}" ]; then
  RUN_LAST_SERIAL_NUMBER=${LAST_SERIAL_NUMBER}
elif [[ ! ${LAST_SERIAL_ARG} =~ ^[0-9]+$ ]]; then
  printf "\nExiting, --last-serial '%s' is not a number\n\n" "${LAST_SERIAL_ARG}"
  exit 1
else
  # force base 10 so that zero padded values (e.g. 079) are not treated as octal
  RUN_LAST_SERIAL_NUMBER=$(( 10#${LAST_SERIAL_ARG} ))
fi

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

RUN_PROJECT_FIRST_NUMBERS=()
RUN_PROJECTS=()
for (( PROJECT_FIRST_NUMBER = FIRST_SERIAL_NUMBER; PROJECT_FIRST_NUMBER < RUN_LAST_SERIAL_NUMBER;
       PROJECT_FIRST_NUMBER += 10 )); do
  RUN_PROJECT_FIRST_NUMBERS+=("${PROJECT_FIRST_NUMBER}")
  RUN_PROJECTS+=("$(projectName "${PROJECT_FIRST_NUMBER}")")
done

MSEM_60_61_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)

PIPELINE_JSON="04_3d_align/pipe.04b.w6n.remove-problem-tiles.json"
PIPELINE_JSON_PATH="${MSEM_60_61_DIR}/pipeline_json/${PIPELINE_JSON}"

# lists every raw stack of the wafer (e.g. stack_name='w61_s070_r00'), so it has each slab's regions
SLAB_INFO_PATH="${MSEM_60_61_DIR}/slab_info.w${WAFER}.txt"

# the stacks REMOVE_TILES can change in this stage, the JSON should not list any others
ASO_SUFFIX="_gc_bc_par_cc_aso"
ASOI_3D_SUFFIX="_gc_bc_par_cc_asoi_3d"
STACK_SUFFIXES=("${ASO_SUFFIX}" "${ASOI_3D_SUFFIX}")

# appended to the name of each original dump slab group that is replaced
BACKUP_SUFFIX="_pre_remove_$(date '+%Y%m%d')"

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

# the "<project> <stack>" lines for the run's projects
RUN_PROJECT_STACKS=$(printf '%s\n' "${JSON_PROJECT_STACKS}" |
                     grep -F -f <(printf '%s \n' "${RUN_PROJECTS[@]}") | sort -u)

LISTED_STACKS=$(printf '%s\n' "${RUN_PROJECT_STACKS}" | awk 'NF == 2 { print $2 }' | sort -u)

# Every stack this run could change: the slab info raw stacks of this run's serials
# (a read loop instead of mapfile because macOS still ships bash 3.2)
CANDIDATE_STACKS=()
while IFS= read -r RAW_STACK; do
  for SUFFIX in "${STACK_SUFFIXES[@]}"; do
    CANDIDATE_STACKS+=("${RAW_STACK}${SUFFIX}")
  done
done < <(grep -oE "stack_name='w${WAFER}_s[0-9]{3}_r[0-9]{2}'" "${SLAB_INFO_PATH}" | cut -d"'" -f2 |
         awk -v first="${FIRST_SERIAL_NUMBER}" -v last="${RUN_LAST_SERIAL_NUMBER}" \
             '{ serial = substr($0, index($0, "_s") + 2, 3) + 0; if (serial >= first && serial <= last) print }' |
         sort -u)

if (( ${#CANDIDATE_STACKS[@]} == 0 )); then
  printf "\nExiting, %s has no s%s to s%s raw stacks\n\n" "${SLAB_INFO_PATH}" "${FIRST_SERIAL}" "${RUN_LAST_SERIAL}"
  exit 1
fi

# A stack listed under the wrong project would not be processed.  This checks every listed stack of
# the run's wafer that is in one of the run's projects or has one of the run's serials (before the
# check below, which would otherwise report a stack listed under one of the run's projects as unexpected).
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

# A listed stack that is not a candidate has an unexpected serial, region, or suffix and
# is probably a typo, since REMOVE_TILES silently skips stacks that do not exist.
UNEXPECTED_STACKS=$(printf '%s\n' "${LISTED_STACKS}" | grep -v '^$' |
                    grep -v -x -F -f <(printf '%s\n' "${CANDIDATE_STACKS[@]}"))
if [ -n "${UNEXPECTED_STACKS}" ]; then
  printf "\nExiting, %s lists stacks for the s%s to s%s projects that are not %s stacks of their slabs:\n%s\n\n" \
         "${PIPELINE_JSON}" "${FIRST_SERIAL}" "${RUN_LAST_SERIAL}" "${STACK_SUFFIXES[*]}" \
         "$(printf '%s\n' "${UNEXPECTED_STACKS}" | sed 's/^/  /')"
  exit 1
fi

if [ -z "${LISTED_STACKS}" ]; then
  printf "\nNothing to run, %s does not list any stacks for the s%s to s%s projects\n\n" \
         "${PIPELINE_JSON}" "${FIRST_SERIAL}" "${RUN_LAST_SERIAL}"
  exit 0
fi

LISTED_LIST=$(printf '%s\n' "${LISTED_STACKS}" | sed 's/^/#   /')

# ----------------------------------------------------------------------------
# Work out what to load for each project and which original dump slab groups to dump again.
#
# 04b_3d_align was dumped once for each project with --pattern asoi_3d when only that project was loaded.
# 02_align was dumped once for each 00 - 02 run with --pattern aso, so a project has two 5 slab groups
# when its 00 - 02 runs had 5 slabs and one 10 slab group otherwise (see deriveSlabsPerRun).  The _asoi_3d
# stacks are loaded along with the _aso ones and a run can load more than one project, so each group is
# dumped again with a pattern for just its serials' _aso or _asoi_3d collections (the __ after the stack
# name keeps _aso from matching _asoi_3d).  The dump script does not limit collections to --project.

# prints the slabs per 00 - 02 run for the project with the specified first serial number
alignSlabsPerRun() {
  local SAVED_FIRST_SERIAL_NUMBER="${FIRST_SERIAL_NUMBER}" RESULT
  FIRST_SERIAL_NUMBER="$1"
  RESULT=$(deriveSlabsPerRun)
  FIRST_SERIAL_NUMBER="${SAVED_FIRST_SERIAL_NUMBER}"
  echo "${RESULT}"
}

# prints the listed stacks with the specified suffix whose serials are in the specified range
listedStacksInRange() {
  local SUFFIX="$1" FIRST="$2" LAST="$3"
  printf '%s\n' "${LISTED_STACKS}" | grep -E "^w${WAFER}_s[0-9]{3}_r[0-9]{2}${SUFFIX}\$" |
    awk -v first="${FIRST}" -v last="${LAST}" \
        '{ serial = substr($0, index($0, "_s") + 2, 3) + 0; if (serial >= first && serial <= last) print }'
}

# prints the --pattern for one slab group's stacks with the specified suffix
# (e.g. _s01[0-4]_r[0-9][0-9]_gc_bc_par_cc_aso__ for 10, 14, and _gc_bc_par_cc_aso)
dumpPattern() {
  local FIRST LAST SUFFIX="$3"
  FIRST=$(printf '%03d' "$1")
  LAST=$(printf '%03d' "$2")
  echo "_s${FIRST:0:2}[${FIRST:2:1}-${LAST:2:1}]_r[0-9][0-9]${SUFFIX}__"
}

DUMP_STAGES=()
DUMP_PROJECTS=()
DUMP_SLAB_GROUPS=()
DUMP_PATTERNS=()
DUMP_CHANGED_STACKS=()

addDumpGroup() {
  local DUMP_STAGE="$1" PROJECT="$2" FIRST="$3" LAST="$4" SUFFIX="$5" PATTERN="$6" CHANGED
  CHANGED=$(listedStacksInRange "${SUFFIX}" "${FIRST}" "${LAST}")
  if [ -n "${CHANGED}" ]; then
    DUMP_STAGES+=("${DUMP_STAGE}")
    DUMP_PROJECTS+=("${PROJECT}")
    DUMP_SLAB_GROUPS+=("$(printf 's%03d_to_s%03d_%s' "${FIRST}" "${LAST}" "${ALIGN_SLAB_GROUP_SUFFIX}")")
    DUMP_PATTERNS+=("${PATTERN}")
    DUMP_CHANGED_STACKS+=("$(printf '%s\n' "${CHANGED}" | tr '\n' ' ' | sed 's/ $//')")
  fi
}

LOADED_PROJECTS=()
SKIPPED_PROJECTS=()
LOAD_INSTRUCTIONS=""
for I in "${!RUN_PROJECTS[@]}"; do

  PROJECT="${RUN_PROJECTS[I]}"
  PROJECT_FIRST_NUMBER="${RUN_PROJECT_FIRST_NUMBERS[I]}"
  PROJECT_LAST_NUMBER=$(( PROJECT_FIRST_NUMBER + 9 ))
  PROJECT_FIRST=$(printf '%03d' "${PROJECT_FIRST_NUMBER}")

  if [ -z "$(listedStacksInRange "(${ASO_SUFFIX}|${ASOI_3D_SUFFIX})" "${PROJECT_FIRST_NUMBER}" "${PROJECT_LAST_NUMBER}")" ]; then
    SKIPPED_PROJECTS+=("${PROJECT}")
    continue
  fi

  LOADED_PROJECTS+=("${PROJECT}")

  addDumpGroup "04b_3d_align" "${PROJECT}" "${PROJECT_FIRST_NUMBER}" "${PROJECT_LAST_NUMBER}" "${ASOI_3D_SUFFIX}" \
               "$(dumpPattern "${PROJECT_FIRST_NUMBER}" "${PROJECT_LAST_NUMBER}" "${ASOI_3D_SUFFIX}")"

  if [ "$(alignSlabsPerRun "${PROJECT_FIRST_NUMBER}")" = "10" ]; then
    PROJECT_ALIGN_DUMP_SELECTION="1"
    addDumpGroup "02_align" "${PROJECT}" "${PROJECT_FIRST_NUMBER}" "${PROJECT_LAST_NUMBER}" "${ASO_SUFFIX}" \
                 "$(dumpPattern "${PROJECT_FIRST_NUMBER}" "${PROJECT_LAST_NUMBER}" "${ASO_SUFFIX}")"
  else
    PROJECT_ALIGN_DUMP_SELECTION="1 2"
    MIDDLE_NUMBER=$(( PROJECT_FIRST_NUMBER + 4 ))
    addDumpGroup "02_align" "${PROJECT}" "${PROJECT_FIRST_NUMBER}" "${MIDDLE_NUMBER}" "${ASO_SUFFIX}" \
                 "$(dumpPattern "${PROJECT_FIRST_NUMBER}" "${MIDDLE_NUMBER}" "${ASO_SUFFIX}")"
    addDumpGroup "02_align" "${PROJECT}" "$(( MIDDLE_NUMBER + 1 ))" "${PROJECT_LAST_NUMBER}" "${ASO_SUFFIX}" \
                 "$(dumpPattern "$(( MIDDLE_NUMBER + 1 ))" "${PROJECT_LAST_NUMBER}" "${ASO_SUFFIX}")"
  fi

  # matches the project's two 5 slab serials with one pattern (e.g. s01[05] for serials 010 and 015)
  PROJECT_SERIAL_PATTERN="s${PROJECT_FIRST:0:2}[05]"

  LOAD_INSTRUCTIONS="${LOAD_INSTRUCTIONS}
# ${PROJECT}: load all of its 04b_3d_align results (_asoi_3d stacks) and 02_align results (_aso stacks)
# (each typically takes 1 to 2 minutes, for the dump directories prompts, enter: 1  and then: ${PROJECT_ALIGN_DUMP_SELECTION}):
${RIC_CMD} './db-restore-collections.sh --pattern \"04b_3d_align.*${PROJECT_SERIAL_PATTERN}.*${ALIGN_SLAB_GROUP_SUFFIX}/\"'
${RIC_CMD} './db-restore-collections.sh --pattern \"02_align.*${PROJECT_SERIAL_PATTERN}.*${ALIGN_SLAB_GROUP_SUFFIX}/\"'
"
done

LOADED_LIST=$(printf '#   %s\n' "${LOADED_PROJECTS[@]}")
if (( ${#SKIPPED_PROJECTS[@]} == 0 )); then
  SKIPPED_LIST="#   (none)"
else
  SKIPPED_LIST=$(printf '#   %s\n' "${SKIPPED_PROJECTS[@]}")
fi

BATCH_NAME="remove-layers-w${WAFER}-s${FIRST_SERIAL}-to-s${RUN_LAST_SERIAL}"

DUMP_GROUP_LIST=""
for I in "${!DUMP_STAGES[@]}"; do
  DUMP_GROUP_LIST="${DUMP_GROUP_LIST:+${DUMP_GROUP_LIST}
}#   $(( I + 1 )). ${DUMP_STAGES[I]}/${DUMP_PROJECTS[I]}/${DUMP_SLAB_GROUPS[I]}"
done

# ----------------------------------------------------------------------------
# Write the post run script that replaces the original dumps of the changed stacks.
#
# It sits next to the run file with the same name except for a .post-run.sh suffix instead of .txt
# (e.g. run.<date>.<stage>.vm<letter>.<time>.post-run.sh), and its output is logged to a .post-run.log file.
# For each slab group, the move only happens when the original slab group has
# nothing but a render dump in it (so no other data is moved away) and has not already been backed
# up with BACKUP_SUFFIX.

POST_RUN_SCRIPT="${RUN_FILE%.txt}.post-run.sh"
POST_RUN_LOG="${RUN_FILE%.txt}.post-run.log"

{
  printf '#!/bin/bash\n\n'
  printf '# Written by %s on %s\n' "$(basename "$0")" "$(date)"
  printf '# for batch %s (run file %s).\n' "${BATCH_NAME}" "$(basename "${RUN_FILE}")"
  cat <<'EOF'
#
# Replaces the original dumps of the stacks changed by the remove tiles run.  Each slab group listed
# below is renamed with BACKUP_SUFFIX, dumped again under its original name, and then the file lists
# of the two dumps are compared.  The script stops at the first problem, and can be run again starting
# with the group that had the problem:
#
#   <this script> [first group number, default 1]
#
# A group whose original slab group was already renamed by an earlier try (the backup exists and the
# original does not) skips the rename.  A group with both a backup and an original slab group stops,
# since its original may be an incomplete or already fixed dump: check it, remove it if needed, and
# run the script again starting with that group.
#
# To go back to an original dump later, remove the fixed slab group and rename the backup to the original name.

EOF
  printf 'GOOGLE_CLOUD_DIR=%q\n' "${GOOGLE_CLOUD_DIR}"
  printf 'VM_LETTER=%q\n' "${VM_LETTER}"
  printf 'VM_BASE_DUMP_DIR=%q\n' "${VM_BASE_DUMP_DIR}"
  printf 'BACKUP_SUFFIX=%q\n' "${BACKUP_SUFFIX}"
  cat <<'EOF'

GROUP_STAGES=()
GROUP_PROJECTS=()
GROUP_SLAB_GROUPS=()
GROUP_PATTERNS=()
GROUP_CHANGED_STACKS=()

addGroup() {
  GROUP_STAGES+=("$1")
  GROUP_PROJECTS+=("$2")
  GROUP_SLAB_GROUPS+=("$3")
  GROUP_PATTERNS+=("$4")
  GROUP_CHANGED_STACKS+=("$5")
}

# addGroup <stage> <project> <slab group> <dump pattern> <changed stacks>
EOF
  for I in "${!DUMP_STAGES[@]}"; do
    printf 'addGroup %q %q %q %q %q\n' "${DUMP_STAGES[I]}" "${DUMP_PROJECTS[I]}" "${DUMP_SLAB_GROUPS[I]}" \
           "${DUMP_PATTERNS[I]}" "${DUMP_CHANGED_STACKS[I]}"
  done
  cat <<'EOF'

GROUP_COUNT=${#GROUP_STAGES[@]}
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

FIRST_GROUP="${1:-1}"
if [[ ! "${FIRST_GROUP}" =~ ^[0-9]+$ ]] || (( 10#${FIRST_GROUP} < 1 || 10#${FIRST_GROUP} > GROUP_COUNT )); then
  echo "
USAGE: $0 [first group number from 1 to ${GROUP_COUNT}, default 1]
"
  exit 1
fi
FIRST_GROUP=$(( 10#${FIRST_GROUP} ))

runInContainer() {
  ./run_in_container.sh --vm "${VM_LETTER}" --command "$1"
}

stopAt() {
  printf '\nStopped at group %d: %s\n\n' "$1" "$2"
  if (( $3 <= GROUP_COUNT )); then
    printf 'After fixing the problem, continue with:\n  %s %d\n\n' "${SCRIPT_PATH}" "$3"
  fi
  exit 1
}

echo "
Slab groups to replace on VM ${VM_LETTER}:
"
for (( I = 0; I < GROUP_COUNT; I++ )); do
  if (( I + 1 < FIRST_GROUP )); then
    MARK="skip"
  else
    MARK="    "
  fi
  printf '  %s %2d. %s/%s/%s (changed: %s)\n' "${MARK}" "$(( I + 1 ))" "${GROUP_STAGES[I]}" \
         "${GROUP_PROJECTS[I]}" "${GROUP_SLAB_GROUPS[I]}" "${GROUP_CHANGED_STACKS[I]}"
done

echo
read -p "Replace groups ${FIRST_GROUP} to ${GROUP_COUNT}? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

cd "${GOOGLE_CLOUD_DIR}" || exit 1

for (( I = FIRST_GROUP - 1; I < GROUP_COUNT; I++ )); do

  NUMBER=$(( I + 1 ))
  STAGE="${GROUP_STAGES[I]}"
  PROJECT="${GROUP_PROJECTS[I]}"
  ORIGINAL="${GROUP_SLAB_GROUPS[I]}"
  BACKUP="${ORIGINAL}${BACKUP_SUFFIX}"
  PATTERN="${GROUP_PATTERNS[I]}"
  PROJECT_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT}"

  printf '\n# ==========\n# %d of %d: %s %s %s (changed: %s)\n' "${NUMBER}" "${GROUP_COUNT}" "${STAGE}" \
         "${PROJECT}" "${ORIGINAL}" "${GROUP_CHANGED_STACKS[I]}"

  echo "
# Renaming the original dump to ${BACKUP} ..."
  runInContainer "cd ${PROJECT_DUMP_DIR} && if test -e ${BACKUP}; then test ! -e ${ORIGINAL} && echo \"${BACKUP} already exists, skipping rename\"; else test \"\$(ls ${ORIGINAL})\" = render && mv ${ORIGINAL} ${BACKUP}; fi && ls -d ${ORIGINAL}*" ||
    stopAt "${NUMBER}" "could not rename ${PROJECT_DUMP_DIR}/${ORIGINAL} (it may not exist, may have more than a render dump in it, or both it and ${BACKUP} may exist)" "${NUMBER}"

  echo "
# Dumping the fixed data to ${ORIGINAL} (the dump will prompt for confirmation) ..."
  runInContainer "./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT} --slab-group ${ORIGINAL} --pattern \"${PATTERN}\"" ||
    stopAt "${NUMBER}" "the dump to ${PROJECT_DUMP_DIR}/${ORIGINAL} did not complete (remove any partial dump before continuing)" "${NUMBER}"

  echo "
# Checking that the fixed dump has the same files as the original ..."
  runInContainer "cd ${PROJECT_DUMP_DIR} && diff <(ls ${BACKUP}/render) <(ls ${ORIGINAL}/render) && echo \"${ORIGINAL} has the same files as ${BACKUP}\"" ||
    stopAt "${NUMBER}" "${PROJECT_DUMP_DIR}/${ORIGINAL} does not have the same files as ${BACKUP}" "$(( NUMBER + 1 ))"

done

echo "
Replaced ${GROUP_COUNT} slab group(s), starting with group ${FIRST_GROUP}.
"
EOF
} > "${POST_RUN_SCRIPT}"

chmod 755 "${POST_RUN_SCRIPT}"

# ----------------------------------------------------------------------------


echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, serials s${FIRST_SERIAL} to s${RUN_LAST_SERIAL}

Run file: ${RUN_FILE}

# ${PIPELINE_JSON} lists these stacks for the run's projects:
${LISTED_LIST}
#
# These ${#LOADED_PROJECTS[@]} project(s) have listed stacks and are loaded:
${LOADED_LIST}
#
# These project(s) do not have listed stacks and are not loaded:
${SKIPPED_LIST}
#
# The listed stacks are in ${#DUMP_STAGES[@]} dump slab group(s) that will be replaced after the run:
${DUMP_GROUP_LIST}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Remove the collections from the previous run:
${RIC_CMD} './remove-collections.sh --db render --method remove --items all'

${LOAD_INSTRUCTIONS}
# Check what is loaded (each region of the loaded projects should have an _aso and an _asoi_3d stack):
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run pipeline batch job:

# REMOVE_TILES runs on the driver, so the batch uses the minimum of 2 executors.

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  2  4  standard  2  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# Check the driver log for each listed stack before replacing any dumps, for example:
#   'removing ... from <stack>' and 'collapseStack: moved ... layers in <stack>'
# A stack that does not exist is skipped without an error.

# -------------------------------------
# After the run completes, replace the original dumps of the changed stacks:
#
# Each original slab group is renamed with the ${BACKUP_SUFFIX} suffix and then dumped again under its
# original name.  The script stops at the first problem and says how to continue after fixing it.
# The dumps will prompt for confirmation before continuing.

${POST_RUN_SCRIPT} | tee -a \"${POST_RUN_LOG}\"
" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}

Wrote the post run script:
  ${POST_RUN_SCRIPT}
"
