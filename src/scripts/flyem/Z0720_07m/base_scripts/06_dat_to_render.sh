#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

DAT_DIR="/nearline/flyem2/data/${FLY_REGION_TAB}/dat"

if [[ ! -d ${DAT_DIR} ]]; then
  echo "ERROR: cannot find ${DAT_DIR}"
  exit 1
fi

RUN_TIME=`date +"%Y%m%d_%H%M%S"`
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p ${LOG_DIR}
LOG_FILE="${LOG_DIR}/run_${RUN_TIME}.log"

echo """
Running $0 on ${HOSTNAME} at ${RUN_TIME} ...
""" | tee -a ${LOG_FILE}

DASK_WORKER_SPACE="${LOG_DIR}/dask_work_${RUN_TIME}"
mkdir -p ${DASK_WORKER_SPACE}

RENDER_CONNECT_JSON="${DASK_WORKER_SPACE}/render_connect.json"

echo """{
  \"host\": \"${RENDER_HOST}\",
  \"port\": ${RENDER_PORT},
  \"owner\": \"${RENDER_OWNER}\",
  \"project\": \"${RENDER_PROJECT}\",
  \"web_only\": true,
  \"validate_client\": false,
  \"client_scripts\": \"/groups/flyTEM/flyTEM/render/bin\",
  \"memGB\": \"${RENDER_CLIENT_HEAP}\"
}""" > ${RENDER_CONNECT_JSON}

source /groups/flyem/data/render/bin/miniconda3/source_me.sh 

conda activate fibsem_tools

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

python /groups/flyem/data/render/git/fibsem-tools/dat_to_render.py \
  --source ${DAT_DIR} \
  --stack_name ${ACQUIRE_STACK} \
  --num_workers ${DASK_DAT_TO_RENDER_WORKERS} \
  --dask_worker_space ${DASK_WORKER_SPACE} \
  --image_dir ${STACK_DATA_DIR} \
  --mask_dir /groups/flyem/data/render/pre_iso/masks \
  --restart_context_layers 2 \
  --render_connect_json ${RENDER_CONNECT_JSON} | tee -a ${LOG_FILE}

# override z-resolution and set to 8x8x8
for STACK in ${ACQUIRE_STACK} ${ACQUIRE_STACK}_restart; do
  URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${STACK}/resolutionValues"
  curl -v -X PUT --header "Content-Type: application/json" --header "Accept: application/json" -d "[8,8,8]" "${URL}"
done
