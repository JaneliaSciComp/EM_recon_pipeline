#!/bin/bash

if (( $# < 7 )); then
  echo "
Usage:    ./02_run_pipeline <render-ws-internal-ip> <pipeline-json-rel-path>
                            <number-spark-exec-instances> <number-spark-exec-cores>
                            <premium | standard> <max-executors> <batch-id-suffix> [disableDynamic]

          number-spark-exec-instances must be at least 2
          number-spark-exec-cores must be 4, 8, or 16

Examples:

  Rough Align:
    $0  10.150.0.2  00_rough_align/pipe.00a.w61.bc-match-mat.json          120  4  premium  120  rough-w61-s070-to-s074      disableDynamic
    $0  10.150.0.2  00_rough_align/pipe.00b.w6n.rerun-mat.json             120  4  premium  120  rough-mat-w61-s075-to-s079  disableDynamic

  Match:
    $0  10.150.0.3  01_match/pipe.01a.w6n.diff-mfov-match-patch.json       100  4  premium  100  match-w61-s105-to-s109  disableDynamic
    $0  10.150.0.3  01_match/pipe.01b.w6n.creep-correct.json                25  4  premium   25  creep-w61-s105-to-s109  disableDynamic

  Align:
    $0  10.150.0.4  02_align/pipe.02.w6n.align-stitch-only.json             48  4  premium   48  aso-w61-s130-to-s135    disableDynamic

  Correct Intensity:
    $0  10.150.0.5  03_correct_intensity/pipe.03.w6n.ic2d-stitch-only.json  15  4  premium   15  ic2d-w61-s145-to-149    disableDynamic

  3D Align:
    $0  10.150.0.6  04_3d_align/pipe.04.w6n.layer-as-tile.json              50  4  premium   50  a3d-w61-s150-to-s154    disableDynamic
    $0  10.150.0.6  04_3d_align/pipe.04.w61.remove-scans.json                2  4  premium    2  remove-bad-scans-from-04b_3d_align-data  disableDynamic

  Import SOFIMA:
    $0  10.150.0.7  05_import_sofima/pipe.05.w6n.import-sofima.json         25  4  premium   25  import-sofima-w61-s070-to-s074  disableDynamic
  "
  exit 1
fi

RENDER_WS_IP="${1}"
PIPELINE_JSON_REL_PATH="${2}"
SPARK_EXEC_INSTANCES="${3}"
SPARK_EXEC_CORES=${4}
DATAPROC_TIER="${5}"
MAX_EXECUTORS="${6}"
BATCH_ID_SUFFIX="${7}"

if (( SPARK_EXEC_INSTANCES < 2 )); then
  echo "ERROR: must request at least 2 spark executors"
  exit 1
fi

if (( SPARK_EXEC_CORES != 4 && SPARK_EXEC_CORES != 8 && SPARK_EXEC_CORES != 16 )); then
  echo "ERROR: number of spark executor cores must be 4, 8, or 16"
  exit 1
fi

# For Dataproc properties, see https://cloud.google.com/dataproc-serverless/docs/concepts/properties.md
if [ "${DATAPROC_TIER}" == "premium" ]; then

  # For premium compute tier and spark runtime, total of spark.memory.offHeap.size,
  # spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 24576mb per core.
  # Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.

  SINGLE_CORE_MB=22300 # leave room for spark.executor.memoryOverhead, 22300 + 2230 = 24530 < 24576

elif [ "${DATAPROC_TIER}" == "standard" ]; then

  # For standard compute tier and spark runtime, total of spark.memory.offHeap.size,
  # spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 7424mb per core.
  # Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.

  SINGLE_CORE_MB=6700 # leave room for spark.executor.memoryOverhead, 6700 + 670 = 7370 < 7424

else
  echo "ERROR: invalid compute tier ${DATAPROC_TIER} (must be 'standard' or 'premium')"
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

if (( $# == 8 )); then
  if [ "$8" == "disableDynamic" ]; then
    DYNAMIC_ALLOCATION="spark.dynamicAllocation.enabled=false"
  else
    echo "ERROR: when specified, eighth parameter should be 'disableDynamic' (not $8)"
    exit 1
  fi
else
  DYNAMIC_ALLOCATION="spark.dynamicAllocation.enabled=true,spark.dynamicAllocation.maxExecutors=${MAX_EXECUTORS}"
  DYNAMIC_ALLOCATION="${DYNAMIC_ALLOCATION},spark.dynamicAllocation.executorIdleTimeout=120"       # default is 60
  DYNAMIC_ALLOCATION="${DYNAMIC_ALLOCATION},spark.dynamicAllocation.cachedExecutorIdleTimeout=240" # default is ?
fi

SPARK_EXEC_MEMORY_MB=$(( SPARK_EXEC_CORES * SINGLE_CORE_MB ))

SPARK_PROPS="dataproc.tier=${DATAPROC_TIER},spark.default.parallelism=240,spark.executor.instances=${SPARK_EXEC_INSTANCES}"
SPARK_PROPS="${SPARK_PROPS},spark.executor.cores=${SPARK_EXEC_CORES},spark.executor.memory=${SPARK_EXEC_MEMORY_MB}mb"
SPARK_PROPS="${SPARK_PROPS},${DYNAMIC_ALLOCATION}"
SPARK_PROPS="${SPARK_PROPS},spark.dataproc.executor.disk.size=250g"
#SPARK_PROPS="${SPARK_PROPS},spark.log.level.org.janelia.alignment.match=WARN"

RUN_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# The 3.0 runtime provides Spark 4.0.x on Java 21 with Scala 2.13.
# It is required (not just preferred) because render jars are now compiled for Java 21 and
# will not load on the Java 17 and Java 11 runtimes used by the 2.x and 1.x runtimes.
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/spark-runtime-3.0
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/dataproc-serverless-versions
SPARK_VERSION="3.0"

GS_JAR_URL="gs://janelia-spark-test/library/render-ws-spark-client-5.0.0-SNAPSHOT-standalone.jar"
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
  --ttl=24h \
  --jars=${GS_JAR_URL} \
  --class=org.janelia.render.client.spark.pipeline.AlignmentPipelineClient \
  --batch=rp-"${RUN_TIMESTAMP}-${BATCH_ID_SUFFIX}" \
  --version=${SPARK_VERSION} \
  --properties="${SPARK_PROPS}" \
  --async \
  -- \
  --baseDataUrl http://"${RENDER_WS_IP}":8080/render-ws/v1 \
  --pipelineJson ${GS_PIPELINE_JSON_DIR_URL}/${PIPELINE_JSON_REL_PATH}
