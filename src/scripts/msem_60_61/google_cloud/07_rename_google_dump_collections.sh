#!/bin/bash

BASE_NAME="hess_wafers_60_61__w60_serial_360_to_369__w60_s360_r00_gc_"
QUALIFIER="20250815a"

MONGO_BIN="/groups/hess/hesslab/render/mongodb/mongodb-database-tools-rhel93-x86_64-100.10.0/bin"

gunzip -c admin__stack_meta_data.bson.gz > admin__stack_meta_data.bson
${MONGO_BIN}/bsondump admin__stack_meta_data.bson > admin__stack_meta_data.json
sed -i "s/w60_s360_r00_gc_/w60_s360_r00_gc_${QUALIFIER}_/" admin__stack_meta_data.json

# need to remove the gzipped bson admin data so that it is not imported
rm admin__stack_meta_data.bson.gz admin__stack_meta_data.bson admin__stack_meta_data.query.txt

# remove metadata files to simplify things
rm *.metadata.json.gz prelude.json.gz

SUFFIX_NAMES="
mat_render_align__section.bson.gz
mat_render_align__section.metadata.json.gz
mat_render_align__tile.bson.gz
mat_render_align__tile.metadata.json.gz
mat_render_align__transform.bson.gz
mat_render_align__transform.metadata.json.gz
mat_render__section.bson.gz
mat_render__section.metadata.json.gz
mat_render__tile.bson.gz
mat_render__tile.metadata.json.gz
mat_render__transform.bson.gz
mat_render__transform.metadata.json.gz
mat__section.bson.gz
mat__section.metadata.json.gz
mat__tile.bson.gz
mat__tile.metadata.json.gz
mat__transform.bson.gz
mat__transform.metadata.json.gz
rough__section.bson.gz
rough__section.metadata.json.gz
rough__tile.bson.gz
rough__tile.metadata.json.gz
rough__transform.bson.gz
rough__transform.metadata.json.gz
"

for SUFFIX in ${SUFFIX_NAMES}; do
  mv ${BASE_NAME}${SUFFIX} ${BASE_NAME}${QUALIFIER}${SUFFIX}
done