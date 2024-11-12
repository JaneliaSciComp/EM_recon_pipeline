#!/bin/bash

if (( $# < 3 )); then
  echo "
USAGE $0 <spark alignment base logs directory> <p tile id> <q tile id>

EXAMPLE: $0 /groups/hess/hesslab/render/spark_output/trautmane/20230707_153855/logs 145_000003_054_20220920_141910.88.0 145_000003_054_20220921_221300.89.0
"
  exit 1
fi

BASE_LOGS_DIR="${1}"
P_TILE_ID="${2}"
Q_TILE_ID="${3}"

if [ ! -d "${BASE_LOGS_DIR}" ]; then
  echo "ERROR: ${BASE_LOGS_DIR} not found!"
  exit 1
fi

grep "${P_TILE_ID}.*and ${Q_TILE_ID}" "${BASE_LOGS_DIR}"/worker-*-dir/app-*/*/stdout
