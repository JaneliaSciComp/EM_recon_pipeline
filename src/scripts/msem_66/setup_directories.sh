#!/bin/bash

OWNER="hess_wafer_66"

DIRS="
/nrs/hess/data/${OWNER}
/nrs/hess/data/${OWNER}/export
/nrs/hess/data/${OWNER}/export/${OWNER}.n5
/nrs/hess/data/${OWNER}/tiles_mfov
"

for DIR in ${DIRS}; do
  mkdir "${DIR}"
  chmod 2775 "${DIR}"
done