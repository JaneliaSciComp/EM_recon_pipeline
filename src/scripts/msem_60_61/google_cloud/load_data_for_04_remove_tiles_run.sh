#!/bin/bash

# Batch identifier appended to each slab group name (edit this for each round of runs).
SLAB_GROUP_SUFFIX="20260901"

#STAGE="01_match"
#STAGE_BATCH="01-match"

#STAGE="02_align"
#STAGE_BATCH="02-align"

STAGE="03_ic2d_nc4_hist_rs0p5"
STAGE_BATCH="03-ic2d"

OUTPUT_DIR="/Users/trautmane/Desktop/msem-2026-09/00-runs"
WAFER=61
FIRST_SERIAL_NUMBER="???"
VM_LETTER="A"
VM_IP="10.150.0.2"
VM_LABEL="${VM_LETTER} - ${VM_IP}"
BATCH_NAME="remove-bad-scans-from-${STAGE_BATCH}-data"

# matches both serials with one pattern (e.g. s08[05] for serials 080 and 085)
SERIAL_PATTERN="s0.[05]"

RUN_FILE="${OUTPUT_DIR}/run.$(date '+%Y%m%d').remove-bad-scans.${STAGE}.vm${VM_LETTER}.txt"

echo "
# ============================================================================
# Run $(date)

# -------------------------------------
On ${VM_LABEL}, run:

./db-restore-collections.sh --pattern '${STAGE}.*_20260901_with_bad_scans'

# -------------------------------------
On launch box, run:

./02_run_pipeline.sh  ${VM_IP}  04_3d_align/pipe.04.w61.remove-scans.json  2  4  premium  2  ${BATCH_NAME}  disableDynamic

# launch information:
...


# -------------------------------------
After the run completes (less than 10 minutes), on ${VM_LABEL}, run:
" | tee -a "${RUN_FILE}"

for FIRST_SERIAL_NUMBER in 70 80 90 100 110 120 130 140 150 160 170 180 190; do

  SECOND_SERIAL_NUMBER=$(( FIRST_SERIAL_NUMBER + 5 ))
  SECOND_SERIAL_NUMBER_B=$(( SECOND_SERIAL_NUMBER - 1 ))
  LAST_SERIAL_NUMBER=$(( SECOND_SERIAL_NUMBER + 4 ))

  FIRST_PROJECT_NUMBER=${FIRST_SERIAL_NUMBER}
  LAST_PROJECT_NUMBER=$(( FIRST_PROJECT_NUMBER + 9 ))

  FIRST_SERIAL=$(printf "%03d" "${FIRST_SERIAL_NUMBER}")         # 070
  SECOND_SERIAL=$(printf "%03d" "${SECOND_SERIAL_NUMBER}")       # 075
  SECOND_SERIAL_B=$(printf "%03d" "${SECOND_SERIAL_NUMBER_B}")   # 074
  LAST_SERIAL=$(printf "%03d" "${LAST_SERIAL_NUMBER}")           # 079
  FIRST_PROJECT=$(printf "%03d" "${FIRST_PROJECT_NUMBER}")
  LAST_PROJECT=$(printf "%03d" "${LAST_PROJECT_NUMBER}")

  PREFIX_NUMBER=$(( FIRST_SERIAL_NUMBER / 10 ))                  # 7
  PREFIX=$(printf "%02d" "${PREFIX_NUMBER}")                     # 07
  PREFIX_A="s${PREFIX}[0-4]_"
  PREFIX_B="s${PREFIX}[5-9]_"
  PREFIX_C="s${PREFIX}[0-9]_"

  SGA_PATTERN="w61_.*_par$"

  SLAB_GROUP_A="s${FIRST_SERIAL}_to_s${SECOND_SERIAL_B}_${SLAB_GROUP_SUFFIX}"
  SLAB_GROUP_B="s${SECOND_SERIAL}_to_s${LAST_SERIAL}_${SLAB_GROUP_SUFFIX}"
  SLAB_GROUP_C="s${FIRST_SERIAL}_to_s${LAST_SERIAL}_${SLAB_GROUP_SUFFIX}"

  PROJECT_GROUP="w${WAFER}_serial_${FIRST_PROJECT}_to_${LAST_PROJECT}"

  # note: _par suffix will work for both 01_match and 02_align runs as long as they are setup without each others' stacks
#  echo "
#./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP_A} --pattern 'w61_${PREFIX_A}.*_par'
#./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP_B} --pattern 'w61_${PREFIX_B}.*_par'
#  " | tee -a "${RUN_FILE}"

  echo "
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP_C} --pattern 'w61_${PREFIX_C}.*_asoi'
  " | tee -a "${RUN_FILE}"

done

echo "
Appended run information to:
  ${RUN_FILE}
"
