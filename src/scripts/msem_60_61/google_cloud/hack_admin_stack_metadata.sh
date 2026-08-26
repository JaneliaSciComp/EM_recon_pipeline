#!/bin/bash

set -e

ADMIN_SMD="admin__stack_meta_data"

if [ ! -f ${ADMIN_SMD}.bson.gz ]; then
  echo "ERROR: ${ADMIN_SMD}.bson.gz not found"
  exit 1
fi

gunzip -c ${ADMIN_SMD}.bson.gz > ${ADMIN_SMD}.bson

BSON_DUMP_TOOL="/groups/hess/hesslab/render/mongodb/mongodb-database-tools-rhel93-x86_64-100.10.0/bin/bsondump"
if [ ! -x "${BSON_DUMP_TOOL}" ]; then
  echo "ERROR: ${BSON_DUMP_TOOL} not found or not executable"
  exit 1
fi

${BSON_DUMP_TOOL} ${ADMIN_SMD}.bson | jq '.' > ${ADMIN_SMD}.json

printf "\ncreated ${ADMIN_SMD}.json\n\n"

read -rp "Is it okay to remove admin.*(.bson | .bson.gz | .metadata.json.gz | .query.txt) files? (y/n): " CONFIRM
if [[ ! ${CONFIRM} =~ ^[Yy]$ ]]; then
  printf "\nexiting without cleaning up files\n\n"
  exit 0
fi

rm ${ADMIN_SMD}.bson ${ADMIN_SMD}.bson.gz ${ADMIN_SMD}.metadata.json.gz ${ADMIN_SMD}.query.txt

echo "
Edit ${ADMIN_SMD}.json as needed, then use db-restore-collections.sh to import it to the database.

Join ~79 lines to get each stack on one line and then delete unwanted stacks

"