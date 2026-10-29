#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="02_align"
SLABS_PER_RUN=auto

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

PIPELINE_JSON="${STAGE}/pipe.02.w6n.align-stitch-only.json"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern aso"

BATCH_NAME="aso-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ----------------------------------------------------------------------------
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Typical case: prior 01_match run _par stacks need to be removed and _par_cc stacks kept.
#               The _par_match collections are renamed to _par_cc_match so they can be left as is.
${RIC_CMD} './remove-collections.sh --db render --method keep --items \"2 4 6 8 10 12 14 16 18 20\"'

# To setup new VM, run:
${RIC_CMD} './db-restore-collections.sh --pattern \"01_match.*s${FIRST_SERIAL}.*${SLAB_GROUP_SUFFIX}_creep/\"'

# -------------------------------------
# Run pipeline batch job:

#  20 4-core executor runs take  ~5 hours   and 26 concurrent runs will use 2184 cores ( 84 cores per run)
#  60 4-core executor runs take  ~2 hours   and 12 concurrent runs will use 2928 cores (244 cores per run)
# 120 4-core executor runs take ~90 minutes and  6 concurrent runs will use 2904 cores (484 cores per run)
# 300 4-core executor run  took  65 minutes for w61-s075-to-s079 (and 79 minutes for w61-s070-to-s074)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  60  4  premium  60  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the run completes, save result data:

# The render collection dump takes 30 seconds, dump directory is: ${RUN_DUMP_DIR}/render

# The dump will prompt for confirmation before continuing.
${DUMP_DB_CMD} render ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
