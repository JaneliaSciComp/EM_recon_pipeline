#!/bin/bash

set -e

ABSOLUTE_CONFIG=$(readlink -m "$0")
CONFIG_DIR=$(dirname "${ABSOLUTE_CONFIG}")
export CONFIG_DIR

export LAB_OR_PROJECT_GROUP="hess"
export RENDER_OWNER="hess_wafer_53"
export RENDER_PROJECT="cut_000_to_009" # default project to first cut

export BASE_DATA_DIR="/nrs/${LAB_OR_PROJECT_GROUP}/data"
export DATA_RAW_DIR="${BASE_DATA_DIR}/${RENDER_OWNER}/raw"
export DATA_MIPMAP_DIR="${BASE_DATA_DIR}/${RENDER_OWNER}/mipmaps"

# reduce total number of mipmap files by only going to level 3 which covers scales >= 0.0625 (125x109 pixels)
export MAX_MIPMAP_LEVEL=3

export BILL_TO="${LAB_OR_PROJECT_GROUP}"     # needed for legacy render LSF pipeline scripts
export LSF_PROJECT="${LAB_OR_PROJECT_GROUP}" # needed for spark-janelia flintstone.sh script

# ============================================================================
# The following parameters are either derived from ones above or have static
# standard values.  There is no need to modify these unless you want to
# specify non-standard values.

# IP address and port for the render web services
export RENDER_HOST="10.40.3.113" # e06u08
export RENDER_PORT="8080"
export SERVICE_HOST="${RENDER_HOST}:${RENDER_PORT}"
export RENDER_CLIENT_SCRIPTS="/groups/flyTEM/flyTEM/render/bin"
export RENDER_CLIENT_SCRIPT="$RENDER_CLIENT_SCRIPTS/run_ws_client.sh"
export RENDER_CLIENT_HEAP="1G"

# ============================================================================
# Common Spark job parameters

# Write spark logs to backed-up filesystem rather than user home so that they are readable by others for analysis.
# NOTE: must consolidate logs when changing run parent dir
export SPARK_JANELIA_ARGS="--consolidate_logs --run_parent_dir /groups/hess/hesslab/render/spark_output/${USER}"
#export SPARK_JANELIA_ARGS="--consolidate_logs --run_parent_dir /groups/${LAB_OR_PROJECT_GROUP}/${LAB_OR_PROJECT_GROUP}/render/spark_output/${USER}"

# Avoid "Could not initialize class ch.systemsx.cisd.hdf5.CharacterEncoding" exceptions
# (see https://github.com/PreibischLab/BigStitcher-Spark/issues/8 ).
#H5_LIBPATH="-Dnative.libpath.jhdf5=/groups/flyem/data/render/lib/jhdf5/native/jhdf5/amd64-Linux/libjhdf5.so"
#export SUBMIT_ARGS="--conf spark.executor.extraJavaOptions=${H5_LIBPATH} --conf spark.driver.extraJavaOptions=${H5_LIBPATH}"

#-----------------------------------------------------------
# "Standard" Spark executor setup with 11 cores per worker ...
export N_EXECUTORS_PER_NODE=2
export N_CORES_PER_EXECUTOR=5
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1
