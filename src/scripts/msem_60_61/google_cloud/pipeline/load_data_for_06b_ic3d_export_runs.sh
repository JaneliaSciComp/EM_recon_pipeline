#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="06b_ic3d_export"
SLABS_PER_RUN=10

# Pull --downsample-only and --jobs out of the parameters before sourcing the setup script,
# which requires exactly the three <wafer> <first serial> <VM letter> values.
#
# --jobs picks which exports to submit, so that the long running ones can be run in their own
# batches while the short ones are cycled through the remaining cores:
#
#   long   r00 pixel exports (about 7 hours for w61)
#   short  r00 mask, r01 pixel, and r01 mask exports (1 to 2 hours for w61)
#   all    every pixel and mask export (the default)
#
# Both sets read from the same loaded VM, so a slab group only needs to be set up once
# (see setup_data_for_06b_ic3d_export_runs.sh) even when its long and short jobs run at the same time.
ARG_DOWNSAMPLE_ONLY="false"
ARG_JOBS="all"
SETUP_ARGS=()
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --downsample-only)
      ARG_DOWNSAMPLE_ONLY="true"
      shift
      ;;
    --jobs)
      ARG_JOBS="${2:?'--jobs requires a value (long, short, or all)'}"
      shift 2
      ;;
    *)
      SETUP_ARGS+=("${1}")
      shift
      ;;
  esac
done
set -- "${SETUP_ARGS[@]}"

case "${ARG_JOBS}" in
  long|short|all)
    ;;
  *)
    printf "\nExiting, --jobs must be long, short, or all (not '%s')\n\n" "${ARG_JOBS}"
    exit 1
    ;;
esac

# printed by setup_load_data_variables.sh when the <wafer> <first serial> <VM letter> values are wrong
SCRIPT_NAME=$(basename "$0")
USAGE_OPTIONS="[--jobs <long | short | all>] [--downsample-only]"
USAGE_DETAILS="  --jobs             which exports to submit (default: all)
                       long   r00 pixel exports (about 7 hours for w61)
                       short  r00 mask, r01 pixel, and r01 mask exports (1 to 2 hours for w61)
                       all    every pixel and mask export
  --downsample-only  only build the scale pyramids, skipping datasets that already have an s1

Examples:
  # run the long r00 pixel exports and the short exports for s110 to s119 on VM D
  # (set up the VM once first with setup_data_for_06b_ic3d_export_runs.sh 61 110 D)
  ${SCRIPT_NAME} 61 110 D --jobs long
  ${SCRIPT_NAME} 61 110 D --jobs short

  # run every export for s110 to s119 on VM D
  ${SCRIPT_NAME} 61 110 D

  # downsample only the short exports
  ${SCRIPT_NAME} 61 110 D --jobs short --downsample-only"

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
# _aso_3d_s3i export times with 5 executors (w61 s070 to s108 runs on 2026-11-14):
#   r00 pixel  about 7 hours
#   r00 mask   about 2 hours
#   r01 pixel  about 2 hours  (r01 volumes are much smaller than r00 volumes)
#   r01 mask   about 1 hour
#
# These region differences are consistent for w61, but w60 regions and sizes may differ,
# so check the long / short split below before using --jobs for w60.
#
# Earlier _asoi_3d export times (no SOFIMA field):
#   Pixel Downsample Jobs:
#     25 executors for w61 r00 regions take 20 minutes
#   Mask Jobs:
#     10 executors for w61_s122_r00 mask  with 89 z layers took 1 hour,  30 minutes
#     40 executors for w61_s076_r00 mask  with 89 z layers took 0 hours, 42 minutes
MAX_EXECUTORS=5

# Cores each job uses, for comparing a run against the Dataproc CPU quota.
# Keep SPARK_EXEC_CORES in sync with the ARG_SPARK_EXEC_CORES default in ../11_run_n5_export.sh.
# 11_run_n5_export.sh does not set spark.driver.cores, so the driver gets the Dataproc Serverless default of 4.
SPARK_EXEC_CORES=4
SPARK_DRIVER_CORES=4
CORES_PER_JOB=$(( MAX_EXECUTORS * SPARK_EXEC_CORES + SPARK_DRIVER_CORES ))

# Prints "long" or "short" for a "<stack> <dataset suffix>" job.
# Only r00 pixel exports are long (see the times above).
jobLength() {
  local STACK="${1}"
  local DS_SUFFIX="${2}"
  if [[ "${STACK}" =~ _r00_ ]] && [ "${DS_SUFFIX}" = "pixel" ]; then
    echo "long"
  else
    echo "short"
  fi
}

# Succeeds when a job belongs to the --jobs set.
isSelectedJob() {
  [ "${ARG_JOBS}" = "all" ] || [ "$(jobLength "${1}" "${2}")" = "${ARG_JOBS}" ]
}

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
# Only the datasets in the --jobs set are considered.
#
# Each job is "<stack> <dataset suffix>".

case "${ARG_JOBS}" in
  long)  JOB_SET_DESCRIPTION="long (r00 pixel)" ;;
  short) JOB_SET_DESCRIPTION="short (r00 mask, r01 pixel, and r01 mask)" ;;
  *)     JOB_SET_DESCRIPTION="all (pixel and mask)" ;;
esac

DATASET_SUFFIXES=(pixel mask)
EXPORT_JOBS=()

if [ "${ARG_DOWNSAMPLE_ONLY}" = "true" ]; then

  printf "\nchecking for datasets that already have an s1 ...\n"

  for STACK in "${CANDIDATE_STACKS[@]}"; do
    for DS_SUFFIX in "${DATASET_SUFFIXES[@]}"; do
      isSelectedJob "${STACK}" "${DS_SUFFIX}" || continue
      if gcloud storage ls "${N5_EXPORT_URL}/${STACK}___${DS_SUFFIX}/s1/" 2>/dev/null | grep -q .; then
        printf "  skipping %s___%s because its s1 already exists\n" "${STACK}" "${DS_SUFFIX}"
      else
        EXPORT_JOBS+=("${STACK} ${DS_SUFFIX}")
      fi
    done
  done

  RUN_DESCRIPTION="downsample"

else

  for STACK in "${CANDIDATE_STACKS[@]}"; do
    for DS_SUFFIX in "${DATASET_SUFFIXES[@]}"; do
      isSelectedJob "${STACK}" "${DS_SUFFIX}" || continue
      EXPORT_JOBS+=("${STACK} ${DS_SUFFIX}")
    done
  done

  RUN_DESCRIPTION="export"

fi

# e.g. a long run for a slab group without r00 stacks, or a downsample run where every s1 exists
if (( ${#EXPORT_JOBS[@]} == 0 )); then
  printf "\nExiting, no %s datasets to %s for the %s stacks in %s\n\n" \
         "${JOB_SET_DESCRIPTION}" "${RUN_DESCRIPTION}" "${EXPORT_STACK_SUFFIX}" "${PROJECT_GROUP}"
  exit 1
fi

TOTAL_CORES=$(( ${#EXPORT_JOBS[@]} * CORES_PER_JOB ))

printf "\nfound %d %s dataset(s) to %s:\n" "${#EXPORT_JOBS[@]}" "${JOB_SET_DESCRIPTION}" "${RUN_DESCRIPTION}"
for JOB in "${EXPORT_JOBS[@]}"; do
  read -r STACK DS_SUFFIX <<< "${JOB}"
  printf "  %s___%s  (%s)\n" "${STACK}" "${DS_SUFFIX}" "$(jobLength "${STACK}" "${DS_SUFFIX}")"
done

printf "\nthese jobs will use %d cores (%d jobs x %d cores)\n" \
       "${TOTAL_CORES}" "${#EXPORT_JOBS[@]}" "${CORES_PER_JOB}"

# ----------------------------------------------------------------------------
# Driver log patterns for the --jobs set
#
# batch ids are <rex | rds>-<launch-time>-<stack name with dashes>-<pixel | mask>,
# so a pattern is enough to find the most recent one (s3i keeps it from matching older asoi_3d exports)

DRIVER_LOG_CMDS=""
for REGION_AND_SUFFIX in "r00 pixel" "r00 mask" "r01 pixel" "r01 mask"; do
  read -r REGION DS_SUFFIX <<< "${REGION_AND_SUFFIX}"
  # jobLength only looks at the _r00_ part of the stack name, so a stand-in stack is enough here
  isSelectedJob "w${WAFER}_s${FIRST_SERIAL}_${REGION}_" "${DS_SUFFIX}" || continue
  DRIVER_LOG_CMDS="${DRIVER_LOG_CMDS}./dataproc/download_driver_log.sh --batch-id 'w${WAFER}-s${FIRST_SERIAL}-${REGION}-.*-s3i-${DS_SUFFIX}'
"
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

# Submits ${#EXPORT_JOBS[@]} ${JOB_SET_DESCRIPTION} ${RUN_DESCRIPTION} jobs for the ${EXPORT_STACK_SUFFIX} stacks,
# with ${MAX_EXECUTORS} executors each, using ${TOTAL_CORES} cores (${CORES_PER_JOB} per job).
${BATCH_EXPORT_CMD}

# -------------------------------------
# If needed, download the driver log for one of the jobs:

${DRIVER_LOG_CMDS}
" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
