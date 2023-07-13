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

awk '
BEGIN {
  job_count = 0
  job_total_seconds = 0
  max_job_seconds = 0
}

/Pass., saved matches for/ {
  gsub(/,/, "")
  stage = $17
  totalSaved[stage] += $21
  totalProcessed[stage] += $24
  siftPoorCoverage[stage] += $28
  siftPoorQuantity[stage] += $30
  siftSaved[stage] += $32
  combinedPoorCoverage[stage] += $34
  combinedPoorQuantity[stage] += $36
  combinedSaved[stage] += $38
}

END {
  printf "\n\n"
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
' "${BASE_LOGS_DIR}"/04-driver.log "${BASE_LOGS_DIR}"/worker-*-dir/app-*/*/stdout