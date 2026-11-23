#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="05_sofima"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

# ----------------------------------------------------------------------------
# Only the stacks in the current SOFIMA round are imported.
#
# sofima/sofima_complete_<SOFIMA_ROUND>.csv lists the raw stacks (e.g. w61_s070_r00 or w61-s070-r00)
# whose SOFIMA processing was completed for the round, separated by commas, spaces, or new lines.
# Each of this run's region stacks that is not in the round is left out of the VM with
# db-restore-collections.sh --exclude-pattern, so the import, its dump, and the 06 - 07 stages
# that load from that dump never see it.

# lists every raw stack of the wafer (e.g. stack_name='w61_s070_r00'), so it has each slab's regions
SLAB_INFO_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)/slab_info.w${WAFER}.txt"

if [ ! -f "${SLAB_INFO_PATH}" ]; then
  printf "\nExiting, %s does not exist\n\n" "${SLAB_INFO_PATH}"
  exit 1
fi

ROUND_FILE="${SOFIMA_DIR}/sofima_complete_${SOFIMA_ROUND}.csv"

if [ ! -f "${ROUND_FILE}" ]; then
  printf "\nExiting, %s does not exist (SOFIMA_ROUND is set in setup_load_data_variables.sh)\n\n" \
         "${ROUND_FILE}"
  exit 1
fi

# prints the raw stacks in a round file, one per line, with underscores instead of dashes
readRoundStacks() {
  tr ', \t\r' '\n\n\n\n' < "$1" | grep -v '^$' | tr '-' '_' | sort -u
}

ROUND_STACKS=$(readRoundStacks "${ROUND_FILE}")

INVALID_STACKS=$(printf '%s\n' "${ROUND_STACKS}" | grep -v -E '^w[0-9]+_s[0-9]{3}_r[0-9]{2}$')
if [ -n "${INVALID_STACKS}" ]; then
  printf "\nExiting, %s has values that are not <wafer>_s<serial>_r<region> raw stacks:\n%s\n\n" \
         "${ROUND_FILE}" "$(printf '%s\n' "${INVALID_STACKS}" | sed 's/^/  /')"
  exit 1
fi

# Every region stack this run could import: the slab info raw stacks of this run's serials
# (a read loop instead of mapfile because macOS still ships bash 3.2)
CANDIDATE_STACKS=()
while IFS= read -r RAW_STACK; do
  CANDIDATE_STACKS+=("${RAW_STACK}")
done < <(grep -oE "stack_name='w${WAFER}_s[0-9]{3}_r[0-9]{2}'" "${SLAB_INFO_PATH}" | cut -d"'" -f2 |
         awk -v first="${FIRST_SERIAL_NUMBER}" -v last="${LAST_SERIAL_NUMBER}" \
             '{ serial = substr($0, index($0, "_s") + 2, 3) + 0; if (serial >= first && serial <= last) print }' |
         sort -u)

if (( ${#CANDIDATE_STACKS[@]} == 0 )); then
  printf "\nExiting, %s has no s%s to s%s raw stacks\n\n" "${SLAB_INFO_PATH}" "${FIRST_SERIAL}" "${LAST_SERIAL}"
  exit 1
fi

INCLUDED_STACKS=()
EXCLUDED_STACKS=()
for STACK in "${CANDIDATE_STACKS[@]}"; do
  if printf '%s\n' "${ROUND_STACKS}" | grep -q -x "${STACK}"; then
    INCLUDED_STACKS+=("${STACK}")
  else
    EXCLUDED_STACKS+=("${STACK}")
  fi
done

# A listed stack in this run's serials that is not a candidate has a region the slab info does not have.
# Runs are whole projects (SLABS_PER_RUN=10), so the serials are s<first two digits>0 to 9.
UNEXPECTED_STACKS=$(printf '%s\n' "${ROUND_STACKS}" |
                    grep -E "^w${WAFER}_s${FIRST_SERIAL:0:2}[0-9]_" |
                    grep -v -x -F -f <(printf '%s\n' "${CANDIDATE_STACKS[@]}"))
if [ -n "${UNEXPECTED_STACKS}" ]; then
  printf "\nExiting, %s lists stacks in this run's slabs with regions that are not in %s:\n%s\n\n" \
         "${ROUND_FILE}" "$(basename "${SLAB_INFO_PATH}")" \
         "$(printf '%s\n' "${UNEXPECTED_STACKS}" | sed 's/^/  /')"
  exit 1
fi

if (( ${#INCLUDED_STACKS[@]} == 0 )); then
  printf "\nNothing to run, none of the %s to %s stacks are in SOFIMA round %s\n\n" \
         "s${FIRST_SERIAL}" "s${LAST_SERIAL}" "${SOFIMA_ROUND}"
  exit 0
fi

# Warn about stacks that were already in another round, since running them again would redo
# the 12 hour ic3d run and make the 06e export write a second, timestamped dataset.
REPEATED_STACKS=""
for OTHER_ROUND_FILE in "${SOFIMA_DIR}"/sofima_complete_*.csv; do
  if [ "${OTHER_ROUND_FILE}" != "${ROUND_FILE}" ]; then
    for STACK in $(readRoundStacks "${OTHER_ROUND_FILE}" |
                   grep -x -F -f <(printf '%s\n' "${INCLUDED_STACKS[@]}")); do
      REPEATED_STACKS="${REPEATED_STACKS}#   ${STACK} is also in $(basename "${OTHER_ROUND_FILE}")
"
    done
  fi
done

if [ -n "${REPEATED_STACKS}" ]; then
  REPEATED_WARNING="
# WARNING: these stacks were already in another SOFIMA round and will be processed again:
${REPEATED_STACKS}"
else
  REPEATED_WARNING=""
fi

# Collection names and stack names both contain <raw stack>_, so the trailing underscore keeps
# w61_s070_r00 from also matching something like w61_s070_r001.  The pattern is read by grep -E
# for the dump files and by a JavaScript RegExp for the stack metadata, so it is kept to a simple
# alternation that means the same thing to both.
if (( ${#EXCLUDED_STACKS[@]} > 0 )); then
  EXCLUDE_PATTERN=$(printf '%s_|' "${EXCLUDED_STACKS[@]}")
  EXCLUDE_PATTERN="${EXCLUDE_PATTERN%|}"
  EXCLUDE_PARMS=" --exclude-pattern \"${EXCLUDE_PATTERN}\""
else
  EXCLUDE_PARMS=""
fi

INCLUDED_LIST=$(printf '#   %s\n' "${INCLUDED_STACKS[@]}")
EXCLUDED_LIST=$(printf '#   %s\n' "${EXCLUDED_STACKS[@]}")
if (( ${#EXCLUDED_STACKS[@]} == 0 )); then
  EXCLUDED_LIST="#   (none)"
fi

# ----------------------------------------------------------------------------

PIPELINE_JSON="05_import_sofima/pipe.05.w6n.import-sofima.json"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern _3d_s_"

BATCH_NAME="import-sofima-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

# SOFIMA round ${SOFIMA_ROUND} (${ROUND_FILE}) has ${#INCLUDED_STACKS[@]} of this run's stacks:
${INCLUDED_LIST}
#
# These stacks are not in the round and are excluded when the data is loaded:
${EXCLUDED_LIST}
${REPEATED_WARNING}
cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Load the 04b_3d_align results for the round's stacks
# (typically takes 1 to 2 minutes, for the dump directories prompt, enter: 1):
${RIC_CMD} './db-restore-collections.sh --pattern \"04b_3d_align.*${SERIAL_PATTERN}.*${ALIGN_SLAB_GROUP_SUFFIX}/\"${EXCLUDE_PARMS}'

# Load the 02_align results for the round's stacks because REPLACE_FILTERS reads each tile's filters from the _aso stack
# (typically takes 1 to 2 minutes, for the dump directories prompt, enter: ${ALIGN_DUMP_SELECTION}):
${RIC_CMD} './db-restore-collections.sh --pattern \"02_align.*${SERIAL_PATTERN}.*${ALIGN_SLAB_GROUP_SUFFIX}/\"${EXCLUDE_PARMS}'

# Check what is loaded (only the ${#INCLUDED_STACKS[@]} stacks listed above should have _aso and _asoi_3d stacks):
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run pipeline batch job:

#  20 4-core executor runs take 10 minutes to complete and 26 concurrent runs will use 2184 cores (84 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  20  4  premium  20  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the run completes, save result data:

# The sofima render collection dump takes 2 to 3 minutes, dump directory is: ${RUN_DUMP_DIR}/render

# The dump will prompt for confirmation before continuing.
${DUMP_DB_CMD} render ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
