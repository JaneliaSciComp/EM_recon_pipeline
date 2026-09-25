#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="05_pixel_export"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

# NOTE: unlike the other load scripts, this one asks the VM which stacks exist instead of just
#       printing instructions, so the VM must be running with the 04b_3d_align data already loaded.

RENDER_OWNER="hess_wafers_60_61"

# only the 3d aligned stacks are exported
EXPORT_STACK_SUFFIX="_asoi_3d"

MAX_EXECUTORS=5        #  5 executors for w61_s083_r00 pixel with 80 z layers took 8 hours, 43 minutes
                       #  5 executors for w61_s097_r00 pixel with 75 z layers took 6 hours, 52 minutes
                       #  5 executors for w61_s083_r01 pixel with 80 z layers took 3 hours, 11 minutes
                       #  5 executors for w61_s097_r01 pixel with 75 z layers took 2 hours, 38 minutes
                       # 10 executors for w61_s099_r00 pixel with 82 z layers took 4 hours, 15 minutes
                       # 40 executors for w61_s081_r00 pixel with 82 z layers took 2 hours,  1 minute
                       # 10 executors for w61_s122_r00 mask  with 89 z layers took 1 hour,  30 minutes
                       # 40 executors for w61_s076_r00 mask  with 89 z layers took 0 hours, 42 minutes

# ----------------------------------------------------------------------------
# Ask the VM which stacks need to be exported
#
# The stackIds web service is used instead of ./list-stacks.sh because list-stacks.sh prompts
# for a project when more than one is loaded, which would hang this script.

STACK_IDS_URL="http://localhost:8080/render-ws/v1/owner/${RENDER_OWNER}/project/${PROJECT_GROUP}/stackIds"

printf "\nasking %s for %s ...\n" "${VM_LABEL}" "${STACK_IDS_URL}"

# Only curl runs on the VM.  The json is parsed here instead of piping to jq in the container
# because run_in_container.sh returns the remote command's exit status, so anything that fails
# out there (e.g. a missing jq) looks the same as an unreachable VM.
#
# Command substitution (instead of a pipe into the loop below) keeps that exit status.
STACK_IDS_JSON=$("${GOOGLE_CLOUD_DIR}/run_in_container.sh" --vm "${VM_LETTER}" \
                   --command "curl -s \"${STACK_IDS_URL}\"")
QUERY_EXIT_CODE=$?

if (( QUERY_EXIT_CODE != 0 )); then
  printf "\nExiting, could not reach %s (exit code %d)\n\n" "${VM_LABEL}" "${QUERY_EXIT_CODE}"
  exit 1
fi

# run_in_container.sh allocates a pseudo terminal, so strip the carriage returns it adds
ALL_STACKS=$(printf '%s' "${STACK_IDS_JSON}" | tr -d '\r' | jq -r '.[].stack' 2>/dev/null)

if [ -z "${ALL_STACKS}" ]; then
  printf "\nExiting, could not parse a stack list out of the %s response:\n\n%s\n\n" \
         "${VM_LABEL}" "${STACK_IDS_JSON}"
  exit 1
fi

EXPORT_STACKS=()
while IFS= read -r STACK_NAME; do
  if [ -n "${STACK_NAME}" ]; then
    EXPORT_STACKS+=("${STACK_NAME}")
  fi
done < <(printf '%s\n' "${ALL_STACKS}" | grep -E "${EXPORT_STACK_SUFFIX}\$" | sort)

if (( ${#EXPORT_STACKS[@]} == 0 )); then
  printf "\nExiting, no %s stacks found in %s on %s\n\n" \
         "${EXPORT_STACK_SUFFIX}" "${PROJECT_GROUP}" "${VM_LABEL}"
  exit 1
fi

printf "\nfound %d stack(s) to export:\n" "${#EXPORT_STACKS[@]}"
printf "  %s\n" "${EXPORT_STACKS[@]}"

# ----------------------------------------------------------------------------
# Build one line that submits an export job for each stack
#
# 11_run_n5_export.sh submits with --async and returns immediately, so the sleeps simply
# space out the submissions.  Using && means a failed submission stops the ones after it.

BATCH_EXPORT_CMD=""
for STACK in "${EXPORT_STACKS[@]}"; do
  EXPORT_CMD="./11_run_n5_export.sh ${VM_IP} ${PROJECT_GROUP} ${STACK} ${MAX_EXECUTORS} pixel"
  if [ -z "${BATCH_EXPORT_CMD}" ]; then
    BATCH_EXPORT_CMD="${EXPORT_CMD}"
  else
    BATCH_EXPORT_CMD="${BATCH_EXPORT_CMD} && sleep 10 && ${EXPORT_CMD}"
  fi
done

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

# -------------------------------------
# Setup VM:

# To setup a new VM (asoi data load typically takes 1 to 2 minutes), run:
#   ${RIC_CMD} './db-restore-collections.sh --pattern \"04b_3d_align.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# -------------------------------------
# Run export jobs:

# Submits ${#EXPORT_STACKS[@]} export jobs, one for each ${EXPORT_STACK_SUFFIX} stack, with ${MAX_EXECUTORS} executors each.
${BATCH_EXPORT_CMD}

# -------------------------------------
# If needed, download the driver log for one of the export jobs:

# export batch ids are rex-<launch-time>-<stack name with dashes>-pixel,
# so a pattern is enough to find the most recent one
./download_driver_log.sh 'w${WAFER}-s${FIRST_SERIAL}-r00-.*-pixel'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
