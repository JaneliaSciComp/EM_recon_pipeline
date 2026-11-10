#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="06e_ic3d_export"
SLABS_PER_RUN=10

# Pull --downsample-only out of the parameters before sourcing the setup script,
# which requires exactly the three <wafer> <first serial> <VM letter> values.
ARG_DOWNSAMPLE_ONLY="false"
SETUP_ARGS=()
for ARG in "$@"; do
  if [ "${ARG}" = "--downsample-only" ]; then
    ARG_DOWNSAMPLE_ONLY="true"
  else
    SETUP_ARGS+=("${ARG}")
  fi
done
set -- "${SETUP_ARGS[@]}"

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

# NOTE: unlike the other load scripts, this one asks the VM which stacks exist instead of just
#       printing instructions, so the VM must be running with the 06_ic3d data already loaded.
#
# NOTE: 11_run_n5_export.sh writes to <stack>___<suffix>_<timestamp> when <stack>___<suffix> already exists,
#       but the inpaint step (load_data_for_07_inpaint_run.sh) only reads <stack>___pixel and <stack>___mask.
#       Move any earlier export to the old area first (see ../move_n5_batch.sh) so that a re-export
#       is not silently skipped by inpainting.

RENDER_OWNER="hess_wafers_60_61"

# only the ic3d (s3i) stacks are exported
EXPORT_STACK_SUFFIX="_aso_3d_s3i"

# keep this in sync with N5_PATH in ../11_run_n5_export.sh
N5_EXPORT_URL="gs://janelia-spark-test/hess_wafers_60_61_export/render/${PROJECT_GROUP}"

# --------------
# TODO: replace these with _aso_3d_s3i run times once they are known.
#       The times below are from the _asoi_3d exports, which did not render through a SOFIMA field.
#
# Pixel Jobs:
#    5 executors for w61 r00 regions take 7 to 9 hours
#    5 executors for w61 r01 regions take 2.5 to 3.5 hours
#
# Pixel Downsample Jobs:
#   25 executors for w61 r00 regions take 20 minutes
#
# Mask Jobs:
#   10 executors for w61_s122_r00 mask  with 89 z layers took 1 hour,  30 minutes
#   40 executors for w61_s076_r00 mask  with 89 z layers took 0 hours, 42 minutes
MAX_EXECUTORS=5

# ----------------------------------------------------------------------------
# Ask the VM which stacks need a job
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

CANDIDATE_STACKS=()
while IFS= read -r STACK_NAME; do
  if [ -n "${STACK_NAME}" ]; then
    CANDIDATE_STACKS+=("${STACK_NAME}")
  fi
done < <(printf '%s\n' "${ALL_STACKS}" | grep -E "${EXPORT_STACK_SUFFIX}\$" | sort)

if (( ${#CANDIDATE_STACKS[@]} == 0 )); then
  printf "\nExiting, no %s stacks found in %s on %s\n\n" \
         "${EXPORT_STACK_SUFFIX}" "${PROJECT_GROUP}" "${VM_LABEL}"
  exit 1
fi

# ----------------------------------------------------------------------------
# Pick the jobs: one pixel and one mask dataset for each stack
#
# For downsample only runs, drop each dataset whose pyramid was already built.
# 11_run_n5_export.sh refuses to downsample when s1 exists, and the submissions below are
# chained with &&, so one already downsampled dataset would stop all of the ones after it.
# The pixel and mask datasets are checked separately since either one can be done without the other.
#
# Each dataset is checked individually rather than with one wildcard listing of the project
# group, which would return every export in it.
#
# Each job is "<stack> <dataset suffix>".

DATASET_SUFFIXES=(pixel mask)
EXPORT_JOBS=()

if [ "${ARG_DOWNSAMPLE_ONLY}" = "true" ]; then

  printf "\nchecking for datasets that already have an s1 ...\n"

  for STACK in "${CANDIDATE_STACKS[@]}"; do
    for DS_SUFFIX in "${DATASET_SUFFIXES[@]}"; do
      if gcloud storage ls "${N5_EXPORT_URL}/${STACK}___${DS_SUFFIX}/s1/" 2>/dev/null | grep -q .; then
        printf "  skipping %s___%s because its s1 already exists\n" "${STACK}" "${DS_SUFFIX}"
      else
        EXPORT_JOBS+=("${STACK} ${DS_SUFFIX}")
      fi
    done
  done

  if (( ${#EXPORT_JOBS[@]} == 0 )); then
    printf "\nExiting, every %s pixel and mask dataset in %s already has an s1\n\n" \
           "${EXPORT_STACK_SUFFIX}" "${PROJECT_GROUP}"
    exit 1
  fi

  RUN_DESCRIPTION="downsample"

else

  for STACK in "${CANDIDATE_STACKS[@]}"; do
    for DS_SUFFIX in "${DATASET_SUFFIXES[@]}"; do
      EXPORT_JOBS+=("${STACK} ${DS_SUFFIX}")
    done
  done

  RUN_DESCRIPTION="export"

fi

printf "\nfound %d dataset(s) to %s:\n" "${#EXPORT_JOBS[@]}" "${RUN_DESCRIPTION}"
for JOB in "${EXPORT_JOBS[@]}"; do
  read -r STACK DS_SUFFIX <<< "${JOB}"
  printf "  %s___%s\n" "${STACK}" "${DS_SUFFIX}"
done

# ----------------------------------------------------------------------------
# Build one line that submits all of the jobs
#
# 11_run_n5_export.sh submits with --async and returns immediately, so the sleeps simply
# space out the submissions.  Using && means a failed submission stops the ones after it.

BATCH_EXPORT_CMD=""
for JOB in "${EXPORT_JOBS[@]}"; do
  read -r STACK DS_SUFFIX <<< "${JOB}"
  EXPORT_CMD="./11_run_n5_export.sh --render-ws-ip ${VM_IP} --stack ${STACK} --max-executors ${MAX_EXECUTORS} --dataset-suffix ${DS_SUFFIX} --disable-dynamic"
  if [ "${ARG_DOWNSAMPLE_ONLY}" = "true" ]; then
    EXPORT_CMD="${EXPORT_CMD} --downsample-only"
  fi
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

# To setup a new VM (aso_3d_s3i data load typically takes 1 to 2 minutes), run:
#   ${RIC_CMD} './db-restore-collections.sh --pattern \"06_ic3d.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# -------------------------------------
# Run ${RUN_DESCRIPTION} jobs:

# Submits ${#EXPORT_JOBS[@]} ${RUN_DESCRIPTION} jobs (pixel and mask datasets of the ${EXPORT_STACK_SUFFIX} stacks),
# with ${MAX_EXECUTORS} executors each.
${BATCH_EXPORT_CMD}

# -------------------------------------
# If needed, download the driver log for one of the jobs:

# batch ids are <rex | rds>-<launch-time>-<stack name with dashes>-<pixel | mask>,
# so a pattern is enough to find the most recent one (s3i keeps it from matching older asoi_3d exports)
./dataproc/download_driver_log.sh --batch-id 'w${WAFER}-s${FIRST_SERIAL}-r00-.*-s3i-pixel'
./dataproc/download_driver_log.sh --batch-id 'w${WAFER}-s${FIRST_SERIAL}-r00-.*-s3i-mask'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
