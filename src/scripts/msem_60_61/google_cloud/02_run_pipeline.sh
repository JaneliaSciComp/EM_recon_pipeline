#!/bin/bash

if (( $# < 6 )); then
  echo "
Usage:    ./02_run_pipeline <render-ws-internal-ip> <pipeline-json-rel-path>
                            <number-spark-exec-instances> <number-spark-exec-cores>
                            <premium | standard> <max-executors>

          number-spark-exec-instances must be at least 2
          number-spark-exec-cores must be 4, 8, or 16

Examples: $0 10.150.0.2 01_match/pipe.01.360.match.json 16 4 standard 200
          $0 10.150.0.2 02_align/pipe.02.360.align.json 2 16 premium 10
          $0 10.150.0.2 03_correct_intensity/pipe.03.36n.ic.json 32 4 standard 500
  "
  exit 1
fi

RENDER_WS_IP="${1}"
PIPELINE_JSON_REL_PATH="${2}"
SPARK_EXEC_INSTANCES="${3}"
SPARK_EXEC_CORES=${4}
COMPUTE_TIER="${5}"
MAX_EXECUTORS="${6}"

if (( SPARK_EXEC_INSTANCES < 2 )); then
  echo "ERROR: must request at least 2 spark executors"
  exit 1
fi

if (( SPARK_EXEC_CORES != 4 && SPARK_EXEC_CORES != 8 && SPARK_EXEC_CORES != 16 )); then
  echo "ERROR: number of spark executor cores must be 4, 8, or 16"
  exit 1
fi

# For Dataproc properties, see https://cloud.google.com/dataproc-serverless/docs/concepts/properties.md
if [ "${COMPUTE_TIER}" == "premium" ]; then

  # For premium compute tier and spark runtime, total of spark.memory.offHeap.size,
  # spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 24576mb per core.
  # Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.

  SINGLE_CORE_MB=22300 # leave room for spark.executor.memoryOverhead, 22300 + 2230 = 24530 < 24576

elif [ "${COMPUTE_TIER}" == "standard" ]; then

  # For standard compute tier and spark runtime, total of spark.memory.offHeap.size,
  # spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 7424mb per core.
  # Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.

  SINGLE_CORE_MB=6700 # leave room for spark.executor.memoryOverhead, 6700 + 670 = 7370 < 7424
  SPARK_PROPS=""

else
  echo "ERROR: invalid compute tier ${COMPUTE_TIER} (must be 'standard' or 'premium')"
  exit 1
fi

if (( MAX_EXECUTORS < SPARK_EXEC_INSTANCES )); then
  echo "ERROR: max-executors ${MAX_EXECUTORS} must be at least number of spark executor instances ${SPARK_EXEC_INSTANCES}"
  exit 1
fi

if (( MAX_EXECUTORS > 500 )); then
  echo "ERROR: max-executors must be at most 500"
  exit 1
fi

SPARK_EXEC_MEMORY_MB=$(( SPARK_EXEC_CORES * SINGLE_CORE_MB ))

SPARK_PROPS="spark.dataproc.driver.compute.tier=${COMPUTE_TIER},spark.dataproc.executor.compute.tier=${COMPUTE_TIER}"
SPARK_PROPS="${SPARK_PROPS},spark.default.parallelism=240,spark.executor.instances=${SPARK_EXEC_INSTANCES}"
SPARK_PROPS="${SPARK_PROPS},spark.executor.cores=${SPARK_EXEC_CORES},spark.executor.memory=${SPARK_EXEC_MEMORY_MB}mb"
SPARK_PROPS="${SPARK_PROPS},spark.dynamicAllocation.maxExecutors=${MAX_EXECUTORS}"

RUN_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/spark-runtime-1.1
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/dataproc-serverless-versions
SPARK_VERSION="1.1"

GS_JAR_URL="gs://janelia-spark-test/library/render-ws-spark-client-4.3.0-SNAPSHOT-standalone.jar"
GS_PIPELINE_JSON_DIR_URL="https://storage.googleapis.com/janelia-spark-test/library/pipeline_json"

echo "
Running gcloud dataproc batches submit spark with:
  --jars=${GS_JAR_URL}
  --properties=${SPARK_PROPS}
  --baseDataUrl http://${RENDER_WS_IP}:8080/render-ws/v1
  --pipelineJson ${GS_PIPELINE_JSON_DIR_URL}/${PIPELINE_JSON_REL_PATH}
"

# use --async to return immediately
gcloud dataproc batches submit spark \
  --region=us-east4 \
  --jars=${GS_JAR_URL} \
  --class=org.janelia.render.client.spark.pipeline.AlignmentPipelineClient \
  --batch=render-alignment-pipeline-"${RUN_TIMESTAMP}" \
  --version=${SPARK_VERSION} \
  --properties="${SPARK_PROPS}" \
  --async \
  -- \
  --baseDataUrl http://"${RENDER_WS_IP}":8080/render-ws/v1 \
  --pipelineJson ${GS_PIPELINE_JSON_DIR_URL}/${PIPELINE_JSON_REL_PATH}
