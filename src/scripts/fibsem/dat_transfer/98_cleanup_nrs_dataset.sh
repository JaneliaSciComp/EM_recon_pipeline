#!/bin/bash

set -e

if (( $# != 1 )); then
  echo "USAGE: $0 <nrs-align-dir>    e.g.   /nrs/cellmap/data/jrc_mus-skin-2a/align"
  exit 1
fi

NRS_ALIGN_DIR="${1}"
if [ ! -d "${NRS_ALIGN_DIR}" ]; then
  echo "ERROR: ${NRS_ALIGN_DIR} does not exist"
  exit 1
fi

NRS_DATASET_DIR=$(dirname "${NRS_ALIGN_DIR}")
if [ ! -d "${NRS_DATASET_DIR}" ]; then
  echo "ERROR: ${NRS_DATASET_DIR} does not exist"
  exit 1
fi

printf "\n%s contains:\n\n" "${NRS_DATASET_DIR}"
ls -Al "${NRS_DATASET_DIR}"

cd "${NRS_DATASET_DIR}"

for DIR in align *.n5 raw tiles_destreak; do
  FULL_DIR="${NRS_DATASET_DIR}/${DIR}"
  if [ -d "${FULL_DIR}" ]; then
    printf "\n%s contains:\n\n" "${FULL_DIR}"
    ls -Al "${FULL_DIR}"
    echo
    read -p "Is it ok to delete ${FULL_DIR}  (y | n)? " -n 1 -r ANSWER
    printf "\n"
    if [[ ${ANSWER} =~ ^[Yy]$ ]]; then
      nohup rm -rf ${FULL_DIR} > /dev/null 2>&1 &
    fi
  fi
done