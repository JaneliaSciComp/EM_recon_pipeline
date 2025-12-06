#!/bin/bash

set -e

if (( $# != 2 )); then
  echo "
Usage:    $0 <max-executors> <wafer> <region> <serial-num> [serial-num] ...

          max-executors must be at least 2

Examples:

  $0  100  w61  r00  79 80 81
"
  exit 1
fi

MAX_EXECUTORS="${1}"
if (( MAX_EXECUTORS < 2 )); then
  echo "ERROR: max-executors must be at least 2"
  exit 1
elif (( MAX_EXECUTORS > 500 )); then
  echo "ERROR: max-executors must be at most 500"
  exit 1
fi

WAFER="${2}"
REGION="${3}"
shift 3 # all remaining args should be serial numbers

# used to produce path like /render/w61_serial_070_to_079/w61_s079_r00_gc_par_align_ic2d___norm-layer/s0
RAW_DATASET_SUFFIX="_gc_par_align_ic2d___norm-layer"

# used to produce path like /heightfields_v3/w61_serial_070_to_079/w61_s079_r00_gc_par_align_ic2d___norm-layer/s1/max
MAX_DATASET_ROOT="heightfields_v3"

N5_PATH="gs://janelia-spark-test/hess_wafers_60_61_export"

# using blockFactorXY 2 instead of default 8 to avoid OOM with larger 1024,1024,maxZ blocks
ARGV="\
--n5PathInput=${N5_PATH} \
--rawDatasetSuffix=${RAW_DATASET_SUFFIX} \
--maxDatasetRoot=${MAX_DATASET_ROOT} \
--blockFactorXY 2 \
--blockFactorZ 1"

RUN_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
unset BATCH_NAME
for SERIAL_NUM in "$@"; do
  SERIAL_NUM_PADDED=$(printf "%03d" "${SERIAL_NUM}")
  RAW_STACK="${WAFER}_s${SERIAL_NUM_PADDED}_r${REGION}"
  ARGV="${ARGV} --rawStack ${RAW_STACK}"
  if [[ -z "${BATCH_NAME}" ]]; then
    NUMBER_OF_STACK_MINUS_ONE=$(( $# - 1 ))
    BATCH_NAME=$(echo "clahe-${RUN_TIMESTAMP}-${RAW_STACK}-with-${NUMBER_OF_STACK_MINUS_ONE}" | sed "s/_/-/g")
  fi
done

SPARK_EXEC_CORES=4

# For standard compute tier and spark runtime, total of spark.memory.offHeap.size,
# spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 7424mb per core.
# Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.
SINGLE_CORE_MB=6700 # leave room for spark.executor.memoryOverhead, 6700 + 670 = 7370 < 7424
COMPUTE_TIER="standard"
DYNAMIC_ALLOCATION="spark.dynamicAllocation.enabled=false" # TODO: test with dynamic allocation enabled

SPARK_EXEC_MEMORY_MB=$(( SPARK_EXEC_CORES * SINGLE_CORE_MB ))

SPARK_PROPS="spark.dataproc.driver.compute.tier=${COMPUTE_TIER},spark.dataproc.executor.compute.tier=${COMPUTE_TIER}"
SPARK_PROPS="${SPARK_PROPS},spark.default.parallelism=240,spark.executor.instances=${MAX_EXECUTORS}"
SPARK_PROPS="${SPARK_PROPS},spark.executor.cores=${SPARK_EXEC_CORES},spark.executor.memory=${SPARK_EXEC_MEMORY_MB}mb"
SPARK_PROPS="${SPARK_PROPS},${DYNAMIC_ALLOCATION}"
#SPARK_PROPS="${SPARK_PROPS},spark.log.level.org.janelia.alignment.match=WARN"

# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/spark-runtime-1.1
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/dataproc-serverless-versions
SPARK_VERSION="1.1"

CLASS="org.janelia.saalfeldlab.hotknife.SparkMaskedCLAHEMultiSEM"
GS_JAR_URL="gs://janelia-spark-test/library/hot-knife-0.0.7-SNAPSHOT.jar"
# HOT_KNIFE_JAR="/groups/hess/hesslab/render/lib/hot-knife-0.0.7-SNAPSHOT.jar"

echo "
Running gcloud dataproc batches submit spark with:
  --region=us-east4
  --jars=${GS_JAR_URL}
  --class=${CLASS}
  --batch=${BATCH_NAME}
  --version=${SPARK_VERSION}
  --properties=${SPARK_PROPS}
  --async
  --
  ${ARGV}

"

# use --async to return immediately
# shellcheck disable=SC2086
gcloud dataproc batches submit spark \
  --region=us-east4 \
  --jars=${GS_JAR_URL} \
  --class=${CLASS} \
  --batch="${BATCH_NAME}" \
  --version=${SPARK_VERSION} \
  --properties="${SPARK_PROPS}" \
  --async \
  -- \
  ${ARGV}
