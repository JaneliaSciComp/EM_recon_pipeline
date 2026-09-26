#!/bin/bash

set -e

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_RENDER_WS_IP=""
ARG_STACK=""
ARG_PROJECT=""
ARG_MAX_EXECUTORS="5"
ARG_DATASET_SUFFIX="pixel"
ARG_TIER="premium"
ARG_STACK_RESOLUTION="8,8,8"
ARG_SKIP_TIMESTAMP="false"
ARG_DOWNSAMPLE_ONLY="false"

usage() {
  echo "
USAGE $0 --render-ws-ip <ip> --stack <stack> [options]

  --render-ws-ip     internal ip of the render web service VM (required, e.g. 10.150.0.2)
  --stack            render stack (required, e.g. w61_s070_r00_gc_bc_par_cc_asoi_3d)
  --project          render project (default: derived from the stack name,
                     e.g. w61_s070_r00_... is in w61_serial_070_to_079)
  --max-executors    2 to 500 (default: ${ARG_MAX_EXECUTORS})
  --dataset-suffix   pixel or mask (default: ${ARG_DATASET_SUFFIX})
  --tier             premium or standard compute tier (default: ${ARG_TIER}),
                     premium allows up to 24576mb per core instead of 7424mb
  --stack-resolution full scale x,y,z pixel resolution (default: ${ARG_STACK_RESOLUTION}),
                     only used with --downsample-only
  --skip-timestamp   reuse an existing dataset name instead of appending the run time
  --downsample-only  skip the full scale export and only build the scale pyramid for an
                     existing s0 dataset (requires s0 to exist and s1 to not exist)

Examples:

  $0 --render-ws-ip 10.150.0.2 --stack w61_s070_r00_gc_bc_par_cc_asoi_3d

  $0 --render-ws-ip 10.150.0.2 --stack w61_s070_r00_gc_bc_par_cc_asoi_3d \\
     --dataset-suffix mask --max-executors 10

  $0 --render-ws-ip 10.150.0.2 --stack w61_s070_r00_gc_bc_par_cc_asoi_3d --downsample-only

  $0 --render-ws-ip 10.150.0.2 --stack w61_s070_r00_gc_bc_par_cc_asoi_3d --tier standard
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --render-ws-ip)
      ARG_RENDER_WS_IP="${2:?'--render-ws-ip requires a value'}"
      shift 2
      ;;
    --stack)
      ARG_STACK="${2:?'--stack requires a value'}"
      shift 2
      ;;
    --project)
      ARG_PROJECT="${2:?'--project requires a value'}"
      shift 2
      ;;
    --max-executors)
      ARG_MAX_EXECUTORS="${2:?'--max-executors requires a value'}"
      shift 2
      ;;
    --dataset-suffix)
      ARG_DATASET_SUFFIX="${2:?'--dataset-suffix requires a value'}"
      shift 2
      ;;
    --tier)
      ARG_TIER="${2:?'--tier requires a value'}"
      shift 2
      ;;
    --stack-resolution)
      ARG_STACK_RESOLUTION="${2:?'--stack-resolution requires a value'}"
      shift 2
      ;;
    --skip-timestamp)
      ARG_SKIP_TIMESTAMP="true"
      shift
      ;;
    --downsample-only)
      ARG_DOWNSAMPLE_ONLY="true"
      shift
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

for NAME in --render-ws-ip --stack; do
  case "${NAME}" in
    --render-ws-ip) VALUE="${ARG_RENDER_WS_IP}" ;;
    --stack)        VALUE="${ARG_STACK}" ;;
  esac
  if [ -z "${VALUE}" ]; then
    echo "ERROR: ${NAME} is required"
    usage
  fi
done

# When --project is not given, derive it from the stack name the same way
# 12_run_n5_export_batch.sh does, e.g. w61_s070_r00_gc_bc_par_cc_asoi_3d is in
# project w61_serial_070_to_079.
if [ -n "${ARG_PROJECT}" ]; then

  RENDER_PROJECT="${ARG_PROJECT}"

else

  if [[ ! "${ARG_STACK}" =~ ^([a-zA-Z0-9]+)_s([0-9]{3})_ ]]; then
    echo "ERROR: cannot derive the project because --stack does not start with" \
         "<wafer>_s<serial>_ (not '${ARG_STACK}'), use --project to specify it"
    exit 1
  fi

  WAFER="${BASH_REMATCH[1]}"
  # force base 10 so that a zero padded serial (e.g. 070) is not treated as octal
  SERIAL_NUMBER=$(( 10#${BASH_REMATCH[2]} ))
  FIRST_PROJECT_SERIAL=$(( (SERIAL_NUMBER / 10) * 10 ))
  RENDER_PROJECT=$(printf "%s_serial_%03d_to_%03d" \
                          "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )))

fi

if [[ ! "${ARG_MAX_EXECUTORS}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-executors must be an integer (not '${ARG_MAX_EXECUTORS}')"
  exit 1
fi

if (( ARG_MAX_EXECUTORS < 2 )) || (( ARG_MAX_EXECUTORS > 500 )); then
  echo "ERROR: --max-executors must be between 2 and 500 (not ${ARG_MAX_EXECUTORS})"
  exit 1
fi

case "${ARG_DATASET_SUFFIX}" in
  pixel) MASK_ARG="" ;;
  mask)  MASK_ARG="--exportMask" ;;
  *)
    echo "ERROR: --dataset-suffix must be 'pixel' or 'mask' (not '${ARG_DATASET_SUFFIX}')"
    exit 1
    ;;
esac

case "${ARG_TIER}" in
  premium|standard)
    ;;
  *)
    echo "ERROR: --tier must be 'premium' or 'standard' (not '${ARG_TIER}')"
    exit 1
    ;;
esac

# ----------------------------------------------------------------------------
# Derive dataset names

RUN_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

RENDER_OWNER="hess_wafers_60_61"
N5_PATH="gs://janelia-spark-test/hess_wafers_60_61_export"               # /nrs/hess/data/hess_wafers_60_61/export/hess_wafers_60_61.n5
N5_DATASET="/render/${RENDER_PROJECT}/${ARG_STACK}___${ARG_DATASET_SUFFIX}" # /render/w60_serial_360_to_369/w60_s360_r00_d20_gc_align___20250320_131555

if [ "${ARG_DOWNSAMPLE_ONLY}" = "false" ] && [ "${ARG_SKIP_TIMESTAMP}" = "false" ]; then
  if gcloud storage ls "${N5_PATH}${N5_DATASET}" 2>/dev/null | grep -q .; then
    echo "
  Note: appending run time to dataset name since ${N5_PATH}${N5_DATASET} exists"
    N5_DATASET="${N5_DATASET}_${RUN_TIMESTAMP}"
  fi
fi

# ----------------------------------------------------------------------------
# Build the spark job
#
# For the standard compute tier, the total of spark.memory.offHeap.size, spark.executor.memory
# and spark.executor.memoryOverhead must be between 1024mb and 7424mb per core.
# The premium tier raises that ceiling to 24576mb per core.
# Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.
#
# dataproc.tier is the only tier property to set.  For premium it implies the driver and
# executor compute tiers (and switches spark.dataproc.engine to lightningEngine), so setting
# those tiers as well is rejected.  Both halves of that were learned the hard way:
#   without dataproc.tier -> Premium Resource Requires Premium Tier in and above 3.0 versions.
#                            Add dataproc.tier=premium to the properties.
#   with all three        -> Driver compute tier and compute class cannot be set at the same time

SPARK_EXEC_CORES=4 # must be 4, 8, or 16

# these match the per tier values in ../02_run_pipeline.sh
if [ "${ARG_TIER}" = "premium" ]; then
  SINGLE_CORE_MB=22300 # leave room for spark.executor.memoryOverhead, 22300 + 2230 = 24530 < 24576
else
  SINGLE_CORE_MB=6700  # leave room for spark.executor.memoryOverhead, 6700 + 670 = 7370 < 7424
fi

SPARK_EXEC_MEMORY_MB=$(( SPARK_EXEC_CORES * SINGLE_CORE_MB ))

SPARK_PROPS="dataproc.tier=${ARG_TIER},spark.default.parallelism=240,spark.executor.instances=${ARG_MAX_EXECUTORS}"
SPARK_PROPS="${SPARK_PROPS},spark.dynamicAllocation.maxExecutors=${ARG_MAX_EXECUTORS}"
SPARK_PROPS="${SPARK_PROPS},spark.executor.cores=${SPARK_EXEC_CORES},spark.executor.memory=${SPARK_EXEC_MEMORY_MB}mb"
SPARK_PROPS="${SPARK_PROPS},spark.dataproc.executor.disk.size=250g"

# The 3.0 runtime provides Spark 4.0.x on Java 21 with Scala 2.13.
# It is required (not just preferred) because render jars are now compiled for Java 21 and
# will not load on the Java 17 and Java 11 runtimes used by the 2.x and 1.x runtimes.
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/spark-runtime-3.0
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/dataproc-serverless-versions
SPARK_VERSION="3.0"

GS_JAR_URL="gs://janelia-spark-test/library/render-ws-spark-client-5.0.0-SNAPSHOT-standalone.jar"

if [ "${ARG_DOWNSAMPLE_ONLY}" = "true" ]; then

  # The full scale data must already be there and the pyramid must not have been started,
  # since a partial pyramid from a failed run would be skipped instead of rebuilt.
  if ! gcloud storage ls "${N5_PATH}${N5_DATASET}/s0/" 2>/dev/null | grep -q .; then
    echo "ERROR: ${N5_PATH}${N5_DATASET}/s0 does not exist"
    exit 1
  fi

  if gcloud storage ls "${N5_PATH}${N5_DATASET}/s1/" 2>/dev/null | grep -q .; then
    echo "ERROR: ${N5_PATH}${N5_DATASET}/s1 already exists, remove it before downsampling again"
    exit 1
  fi

  BATCH_ID_PREFIX="rds" # render downsample, distinguishes these runs from full exports
  CLASS="org.janelia.render.client.spark.n5.DownsampleHelper"

  ARGS="--basePathOrStorageUrl ${N5_PATH}"
  ARGS="${ARGS} --fullResolutionDataset ${N5_DATASET}/s0"
  ARGS="${ARGS} --factors 2,2,1"
  # --translate is not passed because DownsampleHelper derives it from the renderExport
  # attribute that N5Client wrote when it created the s0 dataset
  ARGS="${ARGS} --stackResolution ${ARG_STACK_RESOLUTION}"

else

  BATCH_ID_PREFIX="rex" # render export
  CLASS="org.janelia.render.client.spark.n5.N5Client"

  ARGS="--baseDataUrl http://${ARG_RENDER_WS_IP}:8080/render-ws/v1"
  ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ARG_STACK}"
  ARGS="${ARGS} --n5Path ${N5_PATH} "
  ARGS="${ARGS} --n5Dataset ${N5_DATASET}"

  # block z size of 200 will be reset to (stackDeltaZ + 1) when stackDeltaZ < 200
  ARGS="${ARGS} --tileWidth 2048 --tileHeight 2048 --blockSize 1024,1024,200 --factors 2,2,1"

  #ARGS="${ARGS} --minZ 1 --maxZ ${MAX_Z}"
  # ARGS="${ARGS} --minX 84000 --maxX 94000 --minY 70000 --maxY 80000"
  ARGS="${ARGS} ${MASK_ARG}"

fi

BATCH_ID_SUFFIX=$(echo "${ARG_STACK}-${ARG_DATASET_SUFFIX}" | tr '_' '-')
BATCH_ID="${BATCH_ID_PREFIX}-${RUN_TIMESTAMP}-${BATCH_ID_SUFFIX}"
BATCH_ID="${BATCH_ID:0:63}" # batch IDs must be no more than 63 characters

echo "
Running gcloud dataproc batches submit spark with:
  project = ${RENDER_PROJECT}
  --batch=${BATCH_ID}
  --jars=${GS_JAR_URL}
  --class=${CLASS}
  --properties=${SPARK_PROPS}
  ${ARGS}
"

# use --async to return immediately
gcloud dataproc batches submit spark \
  --region=us-east4 \
  --ttl=24h \
  --jars=${GS_JAR_URL} \
  --class=${CLASS} \
  --batch=${BATCH_ID} \
  --version=${SPARK_VERSION} \
  --properties="${SPARK_PROPS}" \
  --async \
  -- \
  ${ARGS}
