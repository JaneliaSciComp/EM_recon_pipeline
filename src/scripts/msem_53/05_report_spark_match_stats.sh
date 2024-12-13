#!/bin/bash

if (( $# < 1 )); then
  echo "USAGE $0 <spark alignment base logs directory> (e.g. /groups/hess/hesslab/render/spark_output/trautmane/20230707_153855/logs)
"
  exit 1
fi

BASE_LOGS_DIR="${1}"

if [ ! -d "${BASE_LOGS_DIR}" ]; then
  echo "ERROR: ${BASE_LOGS_DIR} not found!"
  exit 1
fi

# 2023-07-07 15:51:59,104 [Executor task launch worker for task 29794] [partition 994] INFO  [org.janelia.alignment.match.stage.StageMatchPairCounts] logStats: for stage crossPass1, saved matches for 44 out of 99 pairs (44%), siftPoorCoverage: 1, ...
# 2024-01-17 09:40:20,836 [Executor task launch worker for task 893.0 in stage 2.0 (TID 12893)] INFO [StageMatchPairCounts]: logStats: for stage montageBorderPass1, saved matches for 29 out of 29 pairs (100%), siftPoorCoverage: 0

grep -h "logStats: " "${BASE_LOGS_DIR}"/worker-*-dir/app-*/*/stdout | awk '

BEGIN {
  job_count = 0
  job_total_seconds = 0
  max_job_seconds = 0
}

/Pass., saved matches for/ {
  gsub(/,/, "")
  gsub(/.*logStats: /, "")
  stage = $3
  totalSaved[stage] += $7
  totalProcessed[stage] += $10
  siftPoorCoverage[stage] += $14
  siftPoorQuantity[stage] += $16
  siftSaved[stage] += $18
  combinedPoorCoverage[stage] += $20
  combinedPoorQuantity[stage] += $22
  combinedSaved[stage] += $24
}

END {
  printf "%-20s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s\n", "",                        "",           "",          "",          "",          "",          "",          "",          "",          ""
  printf "%-20s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s\n", "",                        "",           "",          "",          "",          "",      "SIFT",      "SIFT",  "Combined",  "Combined"
  printf "%-20s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s\n", "",                   "Total",      "Total",   "Percent",      "SIFT",  "Combined",      "Poor",      "Poor",      "Poor",      "Poor"
  printf "%-20s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s\n", "Stage",           "Processed",     "Saved",     "Saved",     "Saved",     "Saved",  "Quantity",  "Coverage",  "Quantity",  "Coverage"
  printf "%-20s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s\n", "---------------", "---------", "---------", "---------", "---------", "---------", "---------", "---------", "---------", "---------"
  processed_pair_count = 0
  saved_pair_count = 0
  n = asorti(totalSaved, sortedStages)
  for (i=1; i<=n; i++) {
    stage = sortedStages[i]
    pass_pair_count = totalSaved[stage]
    processedPercentage = 0
    if (totalProcessed[stage] > 0) {
      processedPercentage = totalSaved[stage] / totalProcessed[stage] * 100
    }
    printf "%-20s  %9d  %9d  %9.1f  %9d  %9d  %9d  %9d  %9d  %9d\n", stage, totalProcessed[stage], totalSaved[stage], processedPercentage, siftSaved[stage],  combinedSaved[stage],  siftPoorQuantity[stage],  siftPoorCoverage[stage],  combinedPoorQuantity[stage],  combinedPoorCoverage[stage]
    if (totalProcessed[stage] > processed_pair_count) {
      processed_pair_count = totalProcessed[stage]
    }
    saved_pair_count += totalSaved[stage]
  }
}
'