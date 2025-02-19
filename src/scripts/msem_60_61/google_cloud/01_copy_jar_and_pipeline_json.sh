#!/bin/bash

# ----------------------------------------------------------------------------
# Copy the render-ws-spark-client jar file and pipeline JSON files to Google Cloud Storage.
#
# The render-ws-spark-client jar file is expected to be in the target directory of the render-ws-spark-client project.
# The pipeline JSON files are expected to be in the pipeline_json directory of the EM_recon_pipeline project.
#
# The jar file is copied to gs://janelia-spark-test/library and
# the pipeline JSON files are copied to gs://janelia-spark-test/library/pipeline_json.

set -e

BASE_GIT_DIR="/Users/trautmane/projects/git"
JAR_FILE_NAME="render-ws-spark-client-4.3.0-SNAPSHOT-standalone.jar"
BASE_GOOGLE_BUCKET_DIR="gs://janelia-spark-test/library"

# --------------------------
FULL_JAR_PATH="${BASE_GIT_DIR}/render/render-ws-spark-client/target/${JAR_FILE_NAME}"
GS_JAR_URL="${BASE_GOOGLE_BUCKET_DIR}/${JAR_FILE_NAME}"

if gsutil ls "${GS_JAR_URL}"; then
  read -p "${GS_JAR_URL} already exists. Do you want to overwrite it? (y/n) " -n 1 -r
  echo
  if [[ "$REPLY" == [yY] ]]; then
    gsutil cp "${FULL_JAR_PATH}" "${GS_JAR_URL}"
  fi
fi

PIPELINE_JSON_DIR="${BASE_GIT_DIR}/EM_recon_pipeline/src/scripts/msem_60_61/pipeline_json"

for JSON_FILE_PATH in "${PIPELINE_JSON_DIR}"/*/*.json; do

  JSON_FILE_NAME=$(basename "${JSON_FILE_PATH}")
  JSON_PARENT_DIR=$(dirname "${JSON_FILE_PATH}")
  JSON_PARENT_NAME=$(basename "${JSON_PARENT_DIR}")

  GS_JSON_URL="${BASE_GOOGLE_BUCKET_DIR}/pipeline_json/${JSON_PARENT_NAME}/${JSON_FILE_NAME}"

  if gsutil ls "${GS_JSON_URL}"; then
    read -p "${GS_JSON_URL} already exists. Do you want to overwrite it? (y/n) " -n 1 -r
    echo
    if [[ "$REPLY" == [yY] ]]; then
      gsutil cp "${JSON_FILE_PATH}" "${GS_JSON_URL}"
    fi
  else
    gsutil cp "${JSON_FILE_PATH}" "${GS_JSON_URL}"
  fi
  
done