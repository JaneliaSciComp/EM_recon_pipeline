#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

GEN_PAIRS_JOB="${RENDER_PROJECT}_gen_pairs"
GEN_MATCH_RUN_JOB="${RENDER_PROJECT}_gen_match_run"

bsub -P "${BILL_TO}" -J "${GEN_PAIRS_JOB}" -n1 -W 59 "${SCRIPT_DIR}"/support/11_gen_new_pairs.sh
bsub -P "${BILL_TO}" -J "${GEN_MATCH_RUN_JOB}" -w "ended(${GEN_PAIRS_JOB})" -n1 -W 59 "${SCRIPT_DIR}"/support/12_gen_staged_match_run.sh