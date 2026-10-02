#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="01_match"
SLABS_PER_RUN=auto

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

MATCH_PIPELINE_JSON="${STAGE}/pipe.01a.w6n.diff-mfov-match-patch.json"
CREEP_PIPELINE_JSON="${STAGE}/pipe.01b.w6n.creep-correct.json"
CREEP_SLAB_GROUP="${SLAB_GROUP}_creep"

# The negative lookahead keeps the creep corrected _cc stacks out of the match run dump.  The pattern
# is double quoted for the shell in the container because ( and ! are special there, and double rather
# than single quotes are needed since the dump command is already inside single quotes.
RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern \"bc_par(?!_cc)\""

CREEP_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${CREEP_SLAB_GROUP}"
CREEP_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${CREEP_SLAB_GROUP} --pattern bc_par_cc"

BATCH_NAME="match-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
CREEP_BATCH_NAME="creep-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ----------------------------------------------------------------------------
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Typical case: mfov-as-tile data from 00_par run needs to be removed.
${RIC_CMD} './remove-collections.sh --db match --method remove --items \"1 3 5 7 9 11 13 15 17 19\"'
${RIC_CMD} './remove-collections.sh --db render --method keep --items \"6 12 18 24 30 36 42 48 54 60\"'

# To setup new VM, run:
${RIC_CMD} './db-restore-collections.sh --pattern \"00_par.*s${FIRST_SERIAL}.*${SLAB_GROUP_SUFFIX}/\"'

# Check what is loaded:
${RIC_CMD} './list-stacks.sh'
${RIC_CMD} './list-match-collections.sh'

# -------------------------------------
# Run match pipeline batch job:

# 300 4-core executor run  took  40 minutes for w61-s125-to-129
# 120 4-core executor runs take ~90 minutes and  6 concurrent runs will use 2904 cores (484 cores per run)
#  25 4-core executor runs take  ~6 hours   and 26 concurrent runs will use 2704 cores (104 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${MATCH_PIPELINE_JSON}  120  4  premium  120  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the match run completes, save result data:

# The render collection dump takes 30 seconds, dump directory is: ${RUN_DUMP_DIR}/render
# The match collection dump takes 10 minutes, dump directory is: ${RUN_DUMP_DIR}/match

# Each of the dumps will prompt for confirmation before continuing.
# They are together here in one line so that you can copy and paste the line to run all dumps.
${DUMP_DB_CMD} render ${RUN_PARMS}' && ${DUMP_DB_CMD} match ${RUN_PARMS}'

# -------------------------------------
# Run creep correction pipeline batch job:

#  10 4-core executor runs take  15 minutes   and 26 concurrent runs will use 1144 cores (44 cores per run)
#  25 4-core executor run takes same amount of time as 10 4-core executor run because it serially goes
#                         through each stack and then parallelizes work by z layer

./02_run_pipeline.sh  ${VM_IP}  ${CREEP_PIPELINE_JSON}  10  4  premium  10  ${CREEP_BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${CREEP_BATCH_NAME}

# -------------------------------------
# After the creep correction run completes, save result data:

# The creep render collection dump takes 30 seconds, dump directory is: ${CREEP_DUMP_DIR}/render
# The creep match collection dump takes 10 minutes, dump directory is: ${CREEP_DUMP_DIR}/match

# Each of the dumps will prompt for confirmation before continuing.
# They are together here in one line so that you can copy and paste the line to run all dumps.
${DUMP_DB_CMD} render ${CREEP_PARMS}' && ${DUMP_DB_CMD} match ${CREEP_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
