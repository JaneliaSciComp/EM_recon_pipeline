#!/bin/bash

# BASE_SCP="ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
BASE_SSH="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

for J in 2 5 8; do
  JEISS_HOST="jeiss${J}.hhmi.org"
  echo "
${JEISS_HOST} ...
"
  ${BASE_SSH} ${JEISS_HOST} ls "/cygdrive/d/UploadFlags"
  RETURN_CODE="$?"
  echo "return code: ${RETURN_CODE}"
done
