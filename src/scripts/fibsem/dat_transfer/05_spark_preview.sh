#!/bin/bash

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"

# Set up LSF
source /misc/lsf/conf/profile.lsf

# loading LSF profile returns error code, so need to wait until here to set -e
set -e

if (( $# < 1 )); then
  echo "USAGE $0 <transfer JSON directory>     e.g. /groups/fibsem/home/fibsemxfer/config"
  exit 1
fi

TRANSFER_JSON_DIR="${1}"
if [ ! -d "${TRANSFER_JSON_DIR}" ]; then
  echo "ERROR: ${TRANSFER_JSON_DIR} is not a directory"
  exit 1
else
  echo "
Using transfer JSON directory: ${TRANSFER_JSON_DIR}
"
fi

if compgen -G "${TRANSFER_JSON_DIR}/volume_transfer_info.*.json" > /dev/null; then
    cd "${TRANSFER_JSON_DIR}"
    TRANSFER_JSON_FILES=$(ls volume_transfer_info.*.json)
else
  echo "WARNING: no volume_transfer_info JSON files found in ${TRANSFER_JSON_DIR}"
  exit 0
fi

#-----------------------------------------------------------
# Setup parameters used for all Spark jobs ...

export JAVA_HOME="/misc/sc/jdks/zulu11.56.19-ca-jdk11.0.15-linux_x64"
export PATH="${JAVA_HOME}/bin:${PATH}"

JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.n5.H5TileToN5PreviewClient"

# Avoid "Could not initialize class ch.systemsx.cisd.hdf5.CharacterEncoding" exceptions
# (see https://github.com/PreibischLab/BigStitcher-Spark/issues/8 ).
H5_LIBPATH="-Dnative.libpath.jhdf5=${FIBSEMXFER_DIR}/lib/jhdf5/native/jhdf5/amd64-Linux/libjhdf5.so"

export SUBMIT_ARGS="--conf spark.executor.extraJavaOptions=${H5_LIBPATH} --conf spark.driver.extraJavaOptions=${H5_LIBPATH}"

# preview code needs newer GSON library to parse HDF5 attributes
GSON_JAR="${FIBSEMXFER_DIR}/lib/gson/gson-2.10.1.jar"
export SUBMIT_ARGS="${SUBMIT_ARGS} --conf spark.executor.extraClassPath=${GSON_JAR}"

# setup for 11 cores per worker (allows 4 workers to fit on one 48 core node with 4 cores to spare for other jobs)
export N_EXECUTORS_PER_NODE=5
export N_CORES_PER_EXECUTOR=2
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

#-----------------------------------------------------------
# Loop over all transfer JSON files and launch Spark job for each one ...

JQ="${FIBSEMXFER_DIR}/bin/jq"

for TRANSFER_JSON_FILE in ${TRANSFER_JSON_FILES}; do

  echo "
checking ${TRANSFER_JSON_FILE} for EXPORT_PREVIEW_VOLUME task ..."
  EXPORT_PREVIEW_VOLUME_COUNT=$(grep -c "EXPORT_PREVIEW_VOLUME" "${TRANSFER_JSON_FILE}" || true)  # grep exits with status code 1 if the string is not found so use || true to avoid script exit

  echo "EXPORT_PREVIEW_VOLUME_COUNT is ${EXPORT_PREVIEW_VOLUME_COUNT}"

  if (( EXPORT_PREVIEW_VOLUME_COUNT == 1 )); then

    RENDER_HOST=$(${JQ} -r '.render_data_set.connect.host' "${TRANSFER_JSON_FILE}")
    RENDER_PORT=$(${JQ} -r '.render_data_set.connect.port' "${TRANSFER_JSON_FILE}")
    ALIGN_H5_PATH=$(${JQ} -r '.cluster_root_paths.align_h5 // "undefined"' "${TRANSFER_JSON_FILE}")
    EXPORT_N5_PATH=$(${JQ} -r '.cluster_root_paths.export_n5 // "undefined"' "${TRANSFER_JSON_FILE}")
    BILL_TO=$(${JQ} -r '.cluster_job_project_for_billing' "${TRANSFER_JSON_FILE}")
    NUM_WORKERS=$(${JQ} -r '.number_of_preview_workers // "10"' "${TRANSFER_JSON_FILE}") # default to 10 workers

    if [ "${ALIGN_H5_PATH}" == "undefined" ]; then

      echo "cluster_root_paths.align_h5 not defined in ${TRANSFER_JSON_FILE}, nothing to do"

    elif [ ! -d "${ALIGN_H5_PATH}" ]; then

      echo "cluster_root_paths.align_h5 ${ALIGN_H5_PATH} in ${TRANSFER_JSON_FILE} does not exist, nothing to do"

    elif [ "${EXPORT_N5_PATH}" == "undefined" ]; then

      echo "cluster_root_paths.export_n5 not defined in ${TRANSFER_JSON_FILE}, nothing to do"

    else

      ARGS="--baseDataUrl http://${RENDER_HOST}:${RENDER_PORT}/render-ws/v1"
      ARGS="${ARGS} --transferInfo ${TRANSFER_JSON_DIR}/${TRANSFER_JSON_FILE}"

      # must export this for flintstone
      export LSF_PROJECT="${BILL_TO}"

      LOG_DIR="${ALIGN_H5_PATH}/logs"
      SPARK_LOG_DIR="${LOG_DIR}/spark"
      mkdir -p "${SPARK_LOG_DIR}"

      LAUNCH_LOG_FILE="${LOG_DIR}/preview-$(date +"%Y%m%d_%H%M%S").log"

       # set job runtime to be ten days to avoid job being killed by LSF
      export RUNTIME="240:00"

      # ensure all workers are available before starting driver
      export MIN_WORKERS="${NUM_WORKERS}"

      # Write spark logs to backed-up filesystem rather than user home so that they are readable by others for analysis.
      # NOTE: must consolidate logs when changing run parent dir
      export SPARK_JANELIA_ARGS="--consolidate_logs --run_parent_dir ${SPARK_LOG_DIR}"

# use shell group to tee all output to log file
{
  echo "
Running with arguments:
${ARGS}
"
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $NUM_WORKERS $JAR $CLASS $ARGS
} 2>&1 | tee -a "${LAUNCH_LOG_FILE}"

    fi

  fi

  # wait a few seconds before launching next job
  sleep 5

done




