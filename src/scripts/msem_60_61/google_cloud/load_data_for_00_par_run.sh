#!/bin/bash

# NOTE: readlink -m is a GNU extension that the BSD readlink on macOS does not support,
#       so derive the absolute script directory with cd and pwd instead
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Batch identifier appended to each slab group name (edit this for each round of runs).
SLAB_GROUP_SUFFIX="20260918"
STAGE="00_par"

OUTPUT_DIR="/Users/trautmane/Desktop/msem-2026-09/00-runs"
WAFER="$1"
FIRST_SERIAL_NUMBER="$2"
VM_LETTER="$3"

if (( $# != 3 )); then
  printf "\nUSAGE: %s <wafer> <first serial number> <VM letter>\n\n" "$(basename "$0")"
  exit 1
fi

case "${WAFER}" in
  60|61)
    ;;
  *)
    printf "\nExiting, wafer '%s' is not 60 or 61\n\n" "${WAFER}"
    exit 1
    ;;
esac

PIPELINE_JSON="00_rough_align/pipe.00.w${WAFER}.bc-match-mat.json"
MAT_RERUN_PIPELINE_JSON="00_rough_align/pipe.00.w6n.rerun-mat.json"

VM_IPS=(10.150.0.2  10.150.0.3  10.150.0.4  10.150.0.5  10.150.0.6
        10.150.0.7  10.150.0.8  10.150.0.9  10.150.0.10 10.150.0.11
        10.150.0.12 10.150.0.13 10.150.0.14 10.150.0.15 10.150.0.16
        10.150.0.17 10.150.0.18 10.150.0.19 10.150.0.20 10.150.0.21
        10.150.0.22 10.150.0.23 10.150.0.24 10.150.0.25 10.150.0.26
        10.150.0.27)

# VMs are lettered in IP order (A is the first IP, B is the second, ...)
VM_LETTERS=({A..Z})
VM_LABELS=()
for I in "${!VM_IPS[@]}"; do
  VM_LABEL_FOR_INDEX="${VM_LETTERS[I]} - ${VM_IPS[I]}"
  VM_LABELS+=("${VM_LABEL_FOR_INDEX}")
  if [[ "${VM_LETTERS[I]}" == "${VM_LETTER}" ]]; then
    VM_IP="${VM_IPS[I]}"
    VM_LABEL="${VM_LABEL_FOR_INDEX}"
  fi
done

if [[ ! ${VM_LETTER} =~ ^[A-Z]$ ]]; then
  printf "\nExiting, VM letter '%s' is not a single upper case letter from A to Z\n\n" "${VM_LETTER}"
  exit 1
fi

# only letters with a corresponding IP are matched above, so an unset VM_IP means the letter is out of range
if [[ -z "${VM_IP}" ]]; then
  printf "\nExiting, VM letter '%s' is not one of the %d defined VMs (A to %s)\n\n" \
         "${VM_LETTER}" "${#VM_IPS[@]}" "${VM_LETTERS[${#VM_IPS[@]}-1]}"
  exit 1
fi

if [[ ! ${FIRST_SERIAL_NUMBER} =~ ^[0-9]+$ ]]; then
  printf "\nExiting, '%s' is not a number\n\n" "${FIRST_SERIAL_NUMBER}"
  exit 1
fi

# force base 10 so that zero padded values (e.g. 070) are not treated as octal
FIRST_SERIAL_NUMBER=$(( 10#${FIRST_SERIAL_NUMBER} ))

if (( FIRST_SERIAL_NUMBER > 410 )) || (( FIRST_SERIAL_NUMBER % 5 != 0 )); then
  printf "\nExiting, %d is not a multiple of 5 between 0 and 410\n\n" "${FIRST_SERIAL_NUMBER}"
  exit 1
fi

LAST_SERIAL_NUMBER=$(( FIRST_SERIAL_NUMBER + 4 ))

# even serial numbers are the first half of a project's slabs, odd ones are the second half
if (( FIRST_SERIAL_NUMBER % 2 == 0 )); then
  KEEP_OR_REMOVE="[k]ept"
  FIRST_PROJECT_NUMBER=${FIRST_SERIAL_NUMBER}
else
  KEEP_OR_REMOVE="[r]emoved"
  FIRST_PROJECT_NUMBER=$(( FIRST_SERIAL_NUMBER - 5 ))
fi

LAST_PROJECT_NUMBER=$(( FIRST_PROJECT_NUMBER + 9 ))

FIRST_SERIAL=$(printf "%03d" "${FIRST_SERIAL_NUMBER}")
LAST_SERIAL=$(printf "%03d" "${LAST_SERIAL_NUMBER}")
FIRST_PROJECT=$(printf "%03d" "${FIRST_PROJECT_NUMBER}")
LAST_PROJECT=$(printf "%03d" "${LAST_PROJECT_NUMBER}")

SLAB_GROUP="s${FIRST_SERIAL}_to_s${LAST_SERIAL}_${SLAB_GROUP_SUFFIX}"
BATCH_NAME="rough-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
MAT_RERUN_BATCH_NAME="rough-mat-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
PROJECT_GROUP="w${WAFER}_serial_${FIRST_PROJECT}_to_${LAST_PROJECT}"

RUN_FILE="${OUTPUT_DIR}/run.$(date '+%Y%m%d').${STAGE}.vm${VM_LETTER}.txt"

echo "
# ----------------------------------------------------------------------------
# Run $(date)


Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

./db-restore-collections.sh --pattern 'janelia/00_gc/.*s${FIRST_PROJECT}'

./other/remove-stacks.sh

# you want stacks to be ${KEEP_OR_REMOVE}
# then enter ' 1 2 3 4 5 6 7 8 9 10 '


# -------------------------------------
On launch box, run:

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  120  4  premium  120  ${BATCH_NAME}  disableDynamic

# launch information:
...

# if run fails, use the following to download the driver log:
${SCRIPT_DIR}/download-driver-log.sh rp-<launch-time>-${BATCH_NAME}

# if mfov-as-tile processing needs to be rerun, launch:
# ./02_run_pipeline.sh  ${VM_IP}  ${MAT_RERUN_PIPELINE_JSON}  120  4  premium  120  ${MAT_RERUN_BATCH_NAME}  disableDynamic


# -------------------------------------
After the run completes (typically 8 to 12 hours), on ${VM_LABEL}, run:

# render collection dump takes ...
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern '.*'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

# match collection dump takes 10 minutes
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern '.*'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/match

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
