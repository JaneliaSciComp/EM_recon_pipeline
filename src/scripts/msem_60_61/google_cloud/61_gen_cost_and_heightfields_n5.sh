#!/bin/bash

set -e

if (( $# < 4 )); then
  echo """
USAGE: $0 <number of nodes> <render project> <raw stack> <bottomLayerCost>

Examples:
  $0 60 w61_serial_070_to_079 w61_s079_r00 210
"""
  exit 1
fi

N_NODES="${1}"
RENDER_PROJECT="${2}"
RAW_STACK="${3}"
BOTTOM_LAYER_COST="${4}"

# appended to the cost and heightfields dataset names (e.g. cost_v3)
CH_RUN_VERSION="b${BOTTOM_LAYER_COST}"

# values we ultimately used for wafer_53d in cost_v3:
SURFACE_INIT_MAX_DELTA="0.01"      # other options: 0.2
SURFACE_MAX_DELTA_Z="0.02"         # other options: 0.2

#-----------------------------------------------------------
N5_PATH="gs://janelia-spark-test/hess_wafers_60_61_export"
IC2D_PATH="${N5_PATH}/render/${RENDER_PROJECT}/${RAW_STACK}_gc_par_align_ic2d"

SOURCE_PATH="${IC2D_PATH}___norm-layer"
if ! gcloud storage ls "${SOURCE_PATH}" 2>/dev/null | grep -q .; then
  echo "ERROR: source path ${SOURCE_PATH} not found"
  exit 1
fi

MASK_PATH="${IC2D_PATH}___mask"
if ! gcloud storage ls "${MASK_PATH}" 2>/dev/null | grep -q .; then
  echo "ERROR: mask path ${MASK_PATH} not found"
  exit 1
fi

# /render/w61_serial_070_to_079/w61_s079_r00_gc_par_align_ic2d___mask
MASK_N5_PARENT=${MASK_PATH/*\/render/\/render}
MASK_N5_GROUP="${MASK_N5_PARENT}/s0"

#-----------------------------------------------------------
# must export this for flintstone

export RUNTIME="233:59"

#-----------------------------------------------------------
RUN_TIME=$(date +"%Y%m%d_%H%M%S")
CLASS="org.janelia.saalfeldlab.hotknife.SparkComputeCostMultiSem"

# /render/w61_serial_070_to_079/w61_s079_r00_gc_par_align_ic2d___pixel
SOURCE_DATASET=${SOURCE_PATH/*\/render/\/render}

# /cost_v1/w61_serial_070_to_079/w61_s079_r00_gc_par_align_ic2d___pixel
COST_DATASET=${SOURCE_DATASET/\/render\//\/cost_${CH_RUN_VERSION}\/}

if gcloud storage ls "${N5_PATH}${COST_DATASET}" 2>/dev/null | grep -q .; then
  echo "ERROR: ${N5_PATH}${COST_DATASET} already exists"
  exit 1
fi

# /heightfields_v1/w61_serial_070_to_079/w61_s079_r00_gc_par_align_ic2d___pixel
HEIGHT_FIELDS_DATASET=${SOURCE_DATASET/\/render\//\/heightfields_${CH_RUN_VERSION}\/}

# zero surfaceMaxDistance means use last z layer of slab - this is needed for the wafer 60 and 61 data
ARGV="\
--inputN5Path=${N5_PATH} \
--inputN5Group=${SOURCE_DATASET}/s0 \
--outputN5Path=${N5_PATH} \
--costN5Group=${COST_DATASET} \
--maskN5Group=${MASK_N5_GROUP} \
--firstStepScaleNumber=1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--costSteps=2,2,1 \
--topLayerCost=105 \
--bottomLayerCost=${BOTTOM_LAYER_COST} \
--surfaceN5Output=${HEIGHT_FIELDS_DATASET} \
--surfaceMinDistance=15 \
--surfaceMaxDistance=0 \
--surfaceBlockSize=1024,1024 \
--surfaceFirstScale=8 \
--surfaceLastScale=1 \
--surfaceInitMaxDeltaZ=${SURFACE_INIT_MAX_DELTA} \
--surfaceMaxDeltaZ=${SURFACE_MAX_DELTA_Z} \
--finalMaxDeltaZ=0.2 \
--median \
--smoothCost"

echo "${ARGV}" | gcloud storage cp - "${N5_PATH}${COST_DATASET}"/args.txt

SPARK_DRIVER_CORES=16
SPARK_EXEC_CORES=4

# For standard compute tier and spark runtime, total of spark.memory.offHeap.size,
# spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 7424mb per core.
# Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.
SINGLE_CORE_MB=6700 # leave room for spark.executor.memoryOverhead, 6700 + 670 = 7370 < 7424
COMPUTE_TIER="standard"
DYNAMIC_ALLOCATION="spark.dynamicAllocation.enabled=false"

SPARK_DRIVER_MEMORY_MB=$(( SPARK_DRIVER_CORES * SINGLE_CORE_MB ))
SPARK_EXEC_MEMORY_MB=$(( SPARK_EXEC_CORES * SINGLE_CORE_MB ))

SPARK_PROPS="spark.dataproc.driver.compute.tier=${COMPUTE_TIER},spark.dataproc.executor.compute.tier=${COMPUTE_TIER}"
SPARK_PROPS="${SPARK_PROPS},spark.default.parallelism=240,spark.executor.instances=${N_NODES}"
SPARK_PROPS="${SPARK_PROPS},spark.executor.cores=${SPARK_EXEC_CORES},spark.executor.memory=${SPARK_EXEC_MEMORY_MB}m"
SPARK_PROPS="${SPARK_PROPS},spark.driver.cores=${SPARK_DRIVER_CORES},spark.driver.memory=${SPARK_DRIVER_MEMORY_MB}m"
SPARK_PROPS="${SPARK_PROPS},${DYNAMIC_ALLOCATION}"
#SPARK_PROPS="${SPARK_PROPS},spark.log.level.org.janelia.alignment.match=WARN"

RUN_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/spark-runtime-1.1
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/dataproc-serverless-versions
SPARK_VERSION="1.1"

GS_JAR_URL="gs://janelia-spark-test/library/hot-knife-0.0.7-SNAPSHOT.jar"
# HOT_KNIFE_JAR="/groups/hess/hesslab/render/lib/hot-knife-0.0.7-SNAPSHOT.jar"
BATCH_NAME=$(echo "cost-${RUN_TIMESTAMP}-${RAW_STACK}" | sed "s/_/-/g")

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