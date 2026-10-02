#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="00_par"
SLABS_PER_RUN=auto

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

PIPELINE_JSON="00_rough_align/pipe.00a.w${WAFER}.bc-match-mat.json"
MAT_RERUN_PIPELINE_JSON="00_rough_align/pipe.00b.w6n.rerun-mat.json"
MAT_RERUN_3_PASS_PIPELINE_JSON="00_rough_align/pipe.00c.w6n.rerun-mat-w-3-cross-passes.json"
MAT_SLAB_GROUP="${SLAB_GROUP}_mat"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern _gc_bc_par"

# The negative lookahead keeps the _gc_bc_par stacks out of the mfov-as-tile dump.  The pattern is
# double quoted for the shell in the container because ( and ! are special there, and double rather
# than single quotes are needed since the dump command is already inside single quotes.
MAT_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${MAT_SLAB_GROUP}"
MAT_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${MAT_SLAB_GROUP} --pattern \"_gc_bc(?!_par)\""

BATCH_NAME="rough-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
MAT_RERUN_BATCH_NAME="rough-mat-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

# The janelia dumps are organized by project, so a five slab run would restore a whole project's
# worth of stacks (ten slabs).  db-restore-collections.sh greps --exclude-pattern against each
# collection name (e.g. hess_wafers_60_61__w61_serial_170_to_179__w61_s175_r00_gc__tile),
# so the other half of the project's slabs can be skipped instead of being loaded and then removed.
#
# A ten slab run wants the whole project, so it needs no exclusion.
EXCLUDE_PATTERN_ARG=""
if (( SLABS_PER_RUN == 5 )); then

  # project serials share their first two digits (e.g. 170 to 179), so the excluded half is
  # the other five last digits
  if (( FIRST_SERIAL_NUMBER == FIRST_PROJECT_NUMBER )); then
    EXCLUDED_LAST_DIGITS="[5-9]"   # keeping the first half, so skip the second
  else
    EXCLUDED_LAST_DIGITS="[0-4]"   # keeping the second half, so skip the first
  fi

  # double quoted because the restore command is printed inside single quotes
  EXCLUDE_PATTERN_ARG=" --exclude-pattern \"_s${FIRST_PROJECT:0:2}${EXCLUDED_LAST_DIGITS}_\""

fi

echo "
# ----------------------------------------------------------------------------
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Typical case: prior 02_align run results need to be removed.
${RIC_CMD} './remove-collections.sh --db match --method remove --items all'
${RIC_CMD} './remove-collections.sh --db render --method remove --items all'

# To setup new VM (janelia data load typically takes 1 to 2 minutes), run:
${RIC_CMD} './db-restore-collections.sh --pattern \"janelia/00_gc/.*s${FIRST_PROJECT}\"${EXCLUDE_PATTERN_ARG}'

# -------------------------------------
# Run pipeline batch job:

# 120 4-core executor runs take ~7 hours to complete and 6 concurrent runs will use 2904 cores (484 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  120  4  premium  120  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# if mfov-as-tile processing needs to be rerun, launch:
# ./02_run_pipeline.sh  ${VM_IP}  ${MAT_RERUN_PIPELINE_JSON}  120  4  premium  120  ${MAT_RERUN_BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# if the rerun still misses cross matches for small region 01 slabs, remove the matches for the r01 slabs and launch the slower three cross pass version:
# ./02_run_pipeline.sh  ${VM_IP}  ${MAT_RERUN_3_PASS_PIPELINE_JSON}  120  4  premium  120  ${MAT_RERUN_BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# -------------------------------------
# After the run completes, save result data:

# The mfov-as-tile render collection dump takes 1 minute, dump directory is: ${MAT_DUMP_DIR}/render
# The mfov-as-tile match collection dump takes 1 minute, dump directory is: ${MAT_DUMP_DIR}/match
# The par render collection dump takes 30 seconds, dump directory is: ${RUN_DUMP_DIR}/render
# The par match collection dump takes 10 minutes, dump directory is: ${RUN_DUMP_DIR}/match

# Each of the dumps will prompt for confirmation before continuing.
# They are together here in one line so that you can copy and paste the line to run all dumps.
${DUMP_DB_CMD} render ${MAT_PARMS}' && ${DUMP_DB_CMD} match ${MAT_PARMS}' && ${DUMP_DB_CMD} render ${RUN_PARMS}' && ${DUMP_DB_CMD} match ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
